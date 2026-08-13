//
//  RoomPlanModelCatalog.swift
//  roomscan
//

import Foundation
#if canImport(RoomPlan)
import RoomPlan
#endif

#if canImport(RoomPlan)
enum RoomPlanModelCatalogError: LocalizedError, Equatable {
    case cannotFindCatalog
    case emptyCatalog

    var errorDescription: String? {
        switch self {
        case .cannotFindCatalog, .emptyCatalog:
            String(localized: "scanning.error.missing_model_catalog")
        }
    }
}

/// Loads Apple's RoomPlan furniture catalog and builds a `ModelProvider` for USDZ export.
///
/// Catalog decode types follow the WWDC23 sample *Providing custom models for captured rooms
/// and structure exports* so they match `RoomPlanCatalog.bundle/catalog.plist`.
@available(iOS 17.0, *)
enum RoomPlanModelCatalog {
    static let bundleName = "RoomPlanCatalog"
    private static let catalogIndexFilename = "catalog.plist"
    private static let nullModelFilename = "$null"

    static func makeProvider(bundle: Bundle = .main) throws -> CapturedRoom.ModelProvider {
        guard let catalogURL = bundle.url(forResource: bundleName, withExtension: "bundle") else {
            throw RoomPlanModelCatalogError.cannotFindCatalog
        }
        return try load(at: catalogURL)
    }

    static func load(at url: URL) throws -> CapturedRoom.ModelProvider {
        let catalogPListURL = url.appending(path: catalogIndexFilename)
        let data = try Data(contentsOf: catalogPListURL)
        let catalog = try PropertyListDecoder().decode(RoomPlanCatalogIndex.self, from: data)

        var modelProvider = CapturedRoom.ModelProvider()
        for categoryAttribute in catalog.categoryAttributes {
            guard let modelFilename = categoryAttribute.modelFilename,
                  !modelFilename.isEmpty,
                  modelFilename != nullModelFilename else {
                continue
            }

            let modelURL = url
                .appending(path: categoryAttribute.folderRelativePath)
                .appending(path: modelFilename)
            guard FileManager.default.fileExists(atPath: modelURL.path) else { continue }

            if categoryAttribute.attributes.isEmpty {
                try? modelProvider.setModelFileURL(modelURL, for: categoryAttribute.category)
            } else {
                try? modelProvider.setModelFileURL(modelURL, for: categoryAttribute.attributes)
            }
        }

        guard !modelProvider.modelFileURLs.isEmpty else {
            throw RoomPlanModelCatalogError.emptyCatalog
        }
        return modelProvider
    }
}

@available(iOS 17.0, *)
private struct RoomPlanCatalogIndex: Decodable {
    let categoryAttributes: [RoomPlanCatalogCategoryAttribute]
}

@available(iOS 17.0, *)
private struct RoomPlanCatalogCategoryAttribute: Decodable {
    let folderRelativePath: String
    let category: CapturedRoom.Object.Category
    let attributes: [any CapturedRoomAttribute]
    let modelFilename: String?

    enum CodingKeys: String, CodingKey {
        case folderRelativePath
        case category
        case attributes
        case modelFilename
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        folderRelativePath = try container.decode(String.self, forKey: .folderRelativePath)
        category = try container.decode(CapturedRoom.Object.Category.self, forKey: .category)
        let attributesRepresentation = try container.decode(
            CapturedRoom.AttributesCodableRepresentation.self,
            forKey: .attributes
        )
        attributes = attributesRepresentation.attributes
        modelFilename = try container.decodeIfPresent(String.self, forKey: .modelFilename)
    }
}
#endif
