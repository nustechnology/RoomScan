//
//  ViewerModels.swift
//  roomscan
//

import Foundation
import simd
import SwiftUI

struct ViewerInput: Hashable, Identifiable, Sendable {
    var id: String { scanID }

    let scanID: String
    let scanName: String
    /// When nil, model loading fails and the viewer shows its error state.
    let modelURL: URL?

    init(scanID: String, scanName: String, modelURL: URL? = nil) {
        self.scanID = scanID
        self.scanName = scanName
        self.modelURL = modelURL
    }
}

enum ViewerMode: String, CaseIterable, Identifiable, Sendable {
    case threeD
    case topView

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .threeD:
            return String(localized: "viewer.mode.threeD")
        case .topView:
            return String(localized: "viewer.mode.topView")
        }
    }
}

enum NoteColor: String, CaseIterable, Identifiable, Codable, Sendable {
    case red
    case orange
    case yellow
    case green
    case cyan
    case blue
    case purple
    case gray

    var id: String { rawValue }

    static let `default`: NoteColor = .yellow

    var swiftUIColor: Color {
        switch self {
        case .red: return AppColors.noteRed
        case .orange: return AppColors.noteOrange
        case .yellow: return AppColors.noteYellow
        case .green: return AppColors.noteGreen
        case .cyan: return AppColors.noteCyan
        case .blue: return AppColors.noteBlue
        case .purple: return AppColors.notePurple
        case .gray: return AppColors.noteGray
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .red: return String(localized: "viewer.note.color.red")
        case .orange: return String(localized: "viewer.note.color.orange")
        case .yellow: return String(localized: "viewer.note.color.yellow")
        case .green: return String(localized: "viewer.note.color.green")
        case .cyan: return String(localized: "viewer.note.color.cyan")
        case .blue: return String(localized: "viewer.note.color.blue")
        case .purple: return String(localized: "viewer.note.color.purple")
        case .gray: return String(localized: "viewer.note.color.gray")
        }
    }

    var pinImageName: String {
        switch self {
        case .red:
            return "PinRed"
        case .orange:
            return "PinOrange"
        case .yellow:
            return "PinYellow"
        case .green:
            return "PinGreen"
        case .cyan:
            return "PinCyan"
        case .blue:
            return "PinBlue"
        case .purple:
            return "PinPurple"
        case .gray:
            return "PinGray"
        }
    }
}

struct SpatialNote: Identifiable, Equatable, Sendable {
    let id: String
    var title: String
    var detail: String
    var color: NoteColor
    var position: SIMD3<Float>
    var createdAt: Date
    var updatedAt: Date
    var modelVersion: String
}

enum ModelSource: Equatable, Sendable {
    case sampleRoom
    case file(URL)
}

enum ModelLoadingError: Error, Equatable, Sendable {
    case fileNotFound
    case loadFailed
}

enum NotesServiceError: Error, Equatable, Sendable {
    case noteNotFound
    case invalidContent
}

enum CameraCommand: Equatable, Sendable {
    case zoomIn
    case zoomOut
    case reset
    case focus(SIMD3<Float>)
}

enum NoteContentLimits {
    static let title = 50
    static let description = 2_000
}

enum NoteEditorMode: Equatable, Sendable, Identifiable {
    case create(position: SIMD3<Float>)
    case edit(SpatialNote)

    var id: String {
        switch self {
        case .create(let position):
            return "create-\(position.x)-\(position.y)-\(position.z)"
        case .edit(let note):
            return "edit-\(note.id)"
        }
    }
}

enum ViewerPlacementMode: Equatable, Sendable {
    case idle
    case placingNew
    case moving(noteID: String)
}
