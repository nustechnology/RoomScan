import Foundation
@testable import roomscan
import simd
import Testing

// MARK: - Test doubles

final class TestModelLoadingService: ModelLoadingService {
    func resolveSource(modelURL: URL?) async throws -> ModelSource {
        .sampleRoom
    }
}

struct ScanDetailVersionStub: ScanDetailService {
    func fetchScanDetail(id: String) async throws -> ScanDetail {
        ScanDetail(
            id: id,
            projectID: "project-1",
            name: "Kitchen",
            description: nil,
            thumbnail: nil,
            creatorID: "user-1",
            creatorEmail: nil,
            noteCount: 0,
            assetStatus: "UPLOADED",
            syncStatus: .synced,
            modelVersion: 1,
            createdAt: .now,
            updatedAt: .now,
            permissions: ScanDetailPermissions(
                role: "OWNER",
                canView: true,
                canEdit: true,
                canDelete: true
            )
        )
    }

    func updateScanDetail(id: String, name: String, description: String?) async throws -> ScanDetail {
        try await fetchScanDetail(id: id)
    }

    func deleteScanDetail(id: String) async throws {}
}

@MainActor
final class FailingNotesService: NotesService {
    enum Operation {
        case create
        case update
        case move
        case delete
    }

    var failingOperations: Set<Operation> = []
    private var notes: [SpatialNote]
    private let modelVersion = "sample-1"

    init(seedCount: Int) {
        let modelVersion = "sample-1"
        let now = Date()
        notes = (0..<seedCount).map { index in
            SpatialNote(
                id: "seed-\(index)",
                title: "Note \(index)",
                detail: "Detail \(index)",
                color: .yellow,
                position: SIMD3(Float(index), 1, 0),
                orientation: .zero,
                createdAt: now,
                updatedAt: now,
                modelVersion: modelVersion
            )
        }
    }

    func fetchNotes(scanID: String) async throws -> [SpatialNote] {
        notes
    }

    func fetchNote(noteID: String) async throws -> SpatialNote {
        guard let note = notes.first(where: { $0.id == noteID }) else {
            throw NotesServiceError.noteNotFound
        }
        return note
    }

    func createNote(scanID: String, input: CreateNoteInput) async throws -> SpatialNote {
        if failingOperations.contains(.create) {
            throw NotesServiceError.invalidContent
        }
        let now = Date()
        let note = SpatialNote(
            id: UUID().uuidString,
            title: input.title,
            detail: input.description,
            color: input.color,
            position: input.position,
            orientation: input.orientation,
            createdAt: now,
            updatedAt: now,
            modelVersion: input.modelVersion
        )
        notes.append(note)
        return note
    }

    func updateNote(
        scanID: String,
        noteID: String,
        title: String,
        description: String,
        color: NoteColor
    ) async throws -> SpatialNote {
        if failingOperations.contains(.update) {
            throw NotesServiceError.invalidContent
        }
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else {
            throw NotesServiceError.noteNotFound
        }
        notes[index].title = title
        notes[index].detail = description
        notes[index].color = color
        notes[index].updatedAt = Date()
        return notes[index]
    }

    func moveNote(noteID: String, input: MoveNoteInput) async throws -> SpatialNote {
        if failingOperations.contains(.move) {
            throw NotesServiceError.noteNotFound
        }
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else {
            throw NotesServiceError.noteNotFound
        }
        notes[index].position = input.position
        notes[index].orientation = input.orientation
        notes[index].modelVersion = input.modelVersion
        notes[index].updatedAt = Date()
        return notes[index]
    }

    func deleteNote(scanID: String, noteID: String) async throws {
        if failingOperations.contains(.delete) {
            throw NotesServiceError.noteNotFound
        }
        notes.removeAll { $0.id == noteID }
    }
}

@MainActor
final class GatedNotesService: NotesService {
    private var notes: [SpatialNote]
    private var createStartedContinuation: CheckedContinuation<Void, Never>?
    private var createReleaseContinuation: CheckedContinuation<Void, Never>?
    private var isWaitingForRelease = false
    private let modelVersion = "sample-1"

    init() {
        let now = Date()
        notes = [
            SpatialNote(
                id: "gated-seed",
                title: "Seed",
                detail: "Seed detail",
                color: .yellow,
                position: .zero,
                orientation: .zero,
                createdAt: now,
                updatedAt: now,
                modelVersion: modelVersion
            )
        ]
    }

    func waitUntilCreateStarted() async {
        if isWaitingForRelease { return }
        await withCheckedContinuation { continuation in
            createStartedContinuation = continuation
        }
    }

    func releaseCreate() {
        createReleaseContinuation?.resume()
        createReleaseContinuation = nil
    }

    func fetchNotes(scanID: String) async throws -> [SpatialNote] {
        notes
    }

    func fetchNote(noteID: String) async throws -> SpatialNote {
        guard let note = notes.first(where: { $0.id == noteID }) else {
            throw NotesServiceError.noteNotFound
        }
        return note
    }

    func createNote(scanID: String, input: CreateNoteInput) async throws -> SpatialNote {
        isWaitingForRelease = true
        createStartedContinuation?.resume()
        createStartedContinuation = nil

        await withCheckedContinuation { continuation in
            createReleaseContinuation = continuation
        }

        let now = Date()
        let note = SpatialNote(
            id: UUID().uuidString,
            title: input.title,
            detail: input.description,
            color: input.color,
            position: input.position,
            orientation: input.orientation,
            createdAt: now,
            updatedAt: now,
            modelVersion: input.modelVersion
        )
        notes.append(note)
        return note
    }

    func updateNote(
        scanID: String,
        noteID: String,
        title: String,
        description: String,
        color: NoteColor
    ) async throws -> SpatialNote {
        throw NotesServiceError.noteNotFound
    }

    func moveNote(noteID: String, input: MoveNoteInput) async throws -> SpatialNote {
        throw NotesServiceError.noteNotFound
    }

    func deleteNote(scanID: String, noteID: String) async throws {
        throw NotesServiceError.noteNotFound
    }
}

@MainActor
final class DelayedNotesService: NotesService {
    private let delayNanoseconds: UInt64
    private let shouldBlockFetchUntilReleased: Bool
    private var notes: [SpatialNote] = []
    private(set) var moveCallCount = 0
    private let modelVersion = "sample-1"

    private var fetchNotesStarted = false
    private var fetchNotesStartedContinuation: CheckedContinuation<Void, Never>?
    private var fetchNotesReleaseContinuation: CheckedContinuation<Void, Never>?

    init(
        delayNanoseconds: UInt64,
        shouldBlockFetchUntilReleased: Bool = false
    ) {
        self.delayNanoseconds = delayNanoseconds
        self.shouldBlockFetchUntilReleased = shouldBlockFetchUntilReleased

        let now = Date()
        notes = [
            SpatialNote(
                id: "delayed-1",
                title: "Seed",
                detail: "Seed detail",
                color: .blue,
                position: .zero,
                orientation: .zero,
                createdAt: now,
                updatedAt: now,
                modelVersion: modelVersion
            )
        ]
    }

    func fetchNotes(scanID: String) async throws -> [SpatialNote] {
        fetchNotesStarted = true
        fetchNotesStartedContinuation?.resume()
        fetchNotesStartedContinuation = nil

        if shouldBlockFetchUntilReleased {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                fetchNotesReleaseContinuation = continuation
            }
        }

        try await Task.sleep(nanoseconds: delayNanoseconds)
        return notes
    }

    func waitUntilFetchNotesStarted() async {
        if fetchNotesStarted { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            fetchNotesStartedContinuation = continuation
        }
    }

    func releaseFetchNotes() {
        fetchNotesReleaseContinuation?.resume()
        fetchNotesReleaseContinuation = nil
    }

    func fetchNote(noteID: String) async throws -> SpatialNote {
        guard let note = notes.first(where: { $0.id == noteID }) else {
            throw NotesServiceError.noteNotFound
        }
        return note
    }

    func createNote(scanID: String, input: CreateNoteInput) async throws -> SpatialNote {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        let now = Date()
        let note = SpatialNote(
            id: UUID().uuidString,
            title: input.title,
            detail: input.description,
            color: input.color,
            position: input.position,
            orientation: input.orientation,
            createdAt: now,
            updatedAt: now,
            modelVersion: input.modelVersion
        )
        notes.append(note)
        return note
    }

    func updateNote(
        scanID: String,
        noteID: String,
        title: String,
        description: String,
        color: NoteColor
    ) async throws -> SpatialNote {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else {
            throw NotesServiceError.noteNotFound
        }
        notes[index].title = title
        notes[index].detail = description
        notes[index].color = color
        return notes[index]
    }

    func moveNote(noteID: String, input: MoveNoteInput) async throws -> SpatialNote {
        moveCallCount += 1
        try await Task.sleep(nanoseconds: delayNanoseconds)
        guard let index = notes.firstIndex(where: { $0.id == noteID }) else {
            throw NotesServiceError.noteNotFound
        }
        notes[index].position = input.position
        notes[index].orientation = input.orientation
        notes[index].modelVersion = input.modelVersion
        return notes[index]
    }

    func deleteNote(scanID: String, noteID: String) async throws {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        notes.removeAll { $0.id == noteID }
    }
}

@MainActor
final class CancellableDetailNotesService: NotesService {
    private let notes = [
        SpatialNote(
            id: "first",
            title: "First",
            detail: "First detail",
            color: .yellow,
            position: .zero,
            orientation: .zero,
            createdAt: .now,
            updatedAt: .now,
            modelVersion: "1"
        ),
        SpatialNote(
            id: "second",
            title: "Second",
            detail: "Second detail",
            color: .blue,
            position: SIMD3(1, 1, 1),
            orientation: .zero,
            createdAt: .now,
            updatedAt: .now,
            modelVersion: "1"
        )
    ]

    private var detailFetchStarted = false
    private var detailFetchCancelled = false
    private(set) var cancelledNoteIDs: [String] = []

    func waitUntilDetailFetchStarted() async {
        while !detailFetchStarted {
            await Task.yield()
        }
    }

    func waitUntilDetailFetchCancelled() async {
        while !detailFetchCancelled {
            await Task.yield()
        }
    }

    func fetchNotes(scanID: String) async throws -> [SpatialNote] {
        notes
    }

    func fetchNote(noteID: String) async throws -> SpatialNote {
        detailFetchStarted = true
        do {
            try await Task.sleep(for: .seconds(30))
        } catch {
            detailFetchCancelled = true
            cancelledNoteIDs.append(noteID)
            throw error
        }
        return try #require(notes.first(where: { $0.id == noteID }))
    }

    func createNote(scanID: String, input: CreateNoteInput) async throws -> SpatialNote {
        throw NotesServiceError.invalidContent
    }

    func updateNote(
        scanID: String,
        noteID: String,
        title: String,
        description: String,
        color: NoteColor
    ) async throws -> SpatialNote {
        throw NotesServiceError.invalidContent
    }

    func moveNote(noteID: String, input: MoveNoteInput) async throws -> SpatialNote {
        throw NotesServiceError.invalidContent
    }

    func deleteNote(scanID: String, noteID: String) async throws {
        throw NotesServiceError.invalidContent
    }
}

@MainActor
enum ViewerViewModelTestHelpers {
    static func loadedViewModel(scanID: String) async -> ViewerViewModel {
        let viewModel = ViewerViewModel(
            input: ViewerInput(scanID: scanID, scanName: "Room"),
            notesService: MockNotesService(),
            modelLoadingService: TestModelLoadingService()
        )
        await viewModel.load()
        return viewModel
    }

    static func waitUntilIdle(_ viewModel: ViewerViewModel) async {
        for _ in 0..<50 where viewModel.isBusy {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
