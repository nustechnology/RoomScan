//
//  CapturedRoomExportSelection.swift
//  roomscan
//

struct CapturedRoomContentSummary: Equatable {
    var wallCount: Int
    var floorCount: Int
    var doorCount: Int
    var windowCount: Int
    var openingCount: Int
    var objectCount: Int

    init(
        wallCount: Int = 0,
        floorCount: Int = 0,
        doorCount: Int = 0,
        windowCount: Int = 0,
        openingCount: Int = 0,
        objectCount: Int = 0
    ) {
        self.wallCount = wallCount
        self.floorCount = floorCount
        self.doorCount = doorCount
        self.windowCount = windowCount
        self.openingCount = openingCount
        self.objectCount = objectCount
    }

    var surfaceCount: Int {
        wallCount + floorCount + doorCount + windowCount + openingCount
    }

    var hasRenderableContent: Bool {
        surfaceCount > 0 || objectCount > 0
    }

    var hasMinimalStructure: Bool {
        wallCount > 0 && floorCount > 0
    }
}

enum CapturedRoomExportSource: Equatable {
    case processed
    case live
}

enum CapturedRoomExportSelection {
    /// Chooses the room that should be exported after Finish.
    ///
    /// Finish requires walls and a floor, so a source that still has that
    /// structure wins over one that does not, even if it has fewer surfaces.
    /// Among sources with the same structure completeness, a live snapshot
    /// with more architecture wins because RoomBuilder often drops
    /// low-confidence or adjacent surfaces. Equal (or processed-greater)
    /// counts keep the processed room because it is usually cleaner.
    static func preferredSource(
        processed: CapturedRoomContentSummary?,
        live: CapturedRoomContentSummary?
    ) -> CapturedRoomExportSource? {
        let usableProcessed = processed.flatMap { $0.hasRenderableContent ? $0 : nil }
        let usableLive = live.flatMap { $0.hasRenderableContent ? $0 : nil }

        switch (usableProcessed, usableLive) {
        case (let processed?, let live?):
            if processed.hasMinimalStructure != live.hasMinimalStructure {
                return live.hasMinimalStructure ? .live : .processed
            }
            return live.surfaceCount > processed.surfaceCount ? .live : .processed
        case (.some, nil):
            return .processed
        case (nil, .some):
            return .live
        case (nil, nil):
            return nil
        }
    }
}
