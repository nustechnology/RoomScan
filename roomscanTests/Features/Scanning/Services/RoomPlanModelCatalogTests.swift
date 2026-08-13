//
//  RoomPlanModelCatalogTests.swift
//  roomscanTests
//

@testable import roomscan
import XCTest
#if canImport(RoomPlan)
import RoomPlan
#endif

#if canImport(RoomPlan)
@available(iOS 17.0, *)
final class RoomPlanModelCatalogTests: XCTestCase {
    func testMakeProvider_loadsBundledAppleCatalog() throws {
        let provider = try RoomPlanModelCatalog.makeProvider(
            bundle: Bundle(for: RoomPlanCaptureService.self)
        )

        XCTAssertFalse(provider.modelFileURLs.isEmpty)
        let tableURL = try XCTUnwrap(try provider.modelFileURL(for: .table))
        XCTAssertEqual(tableURL.lastPathComponent, "DefaultTable.rooms.usdc")
    }

    func testLoad_throwsWhenEveryFilenameIsNull() throws {
        let catalogURL = try makeTemporaryCatalog(
            entries: [
                CatalogEntry(
                    folderRelativePath: "Resources/Storage/Default",
                    categoryKey: "storage",
                    modelFilename: "$null"
                )
            ]
        )
        defer { try? FileManager.default.removeItem(at: catalogURL) }

        XCTAssertThrowsError(try RoomPlanModelCatalog.load(at: catalogURL)) { error in
            XCTAssertEqual(error as? RoomPlanModelCatalogError, .emptyCatalog)
        }
    }

    func testMakeProvider_throwsWhenBundleIsMissing() {
        XCTAssertThrowsError(try RoomPlanModelCatalog.makeProvider(bundle: Bundle(for: RoomPlanModelCatalogTests.self))) { error in
            XCTAssertEqual(error as? RoomPlanModelCatalogError, .cannotFindCatalog)
        }
    }

    func testLoad_throwsWhenCatalogIndexIsMissing() throws {
        let emptyDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RoomPlanModelCatalogTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: emptyDirectory) }

        XCTAssertThrowsError(try RoomPlanModelCatalog.load(at: emptyDirectory))
    }

    private struct CatalogEntry {
        let folderRelativePath: String
        let categoryKey: String
        let modelFilename: String
    }

    private func makeTemporaryCatalog(entries: [CatalogEntry]) throws -> URL {
        let catalogURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TestRoomPlanCatalog-\(UUID().uuidString).bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: catalogURL, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "categoryAttributes": entries.map { entry in
                [
                    "attributes": [String: String](),
                    "category": [entry.categoryKey: [String: String]()],
                    "folderRelativePath": entry.folderRelativePath,
                    "modelFilename": entry.modelFilename
                ]
            }
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        try plistData.write(to: catalogURL.appendingPathComponent("catalog.plist"))
        return catalogURL
    }
}
#endif
