//
//  SharedThumbnailView.swift
//  roomscan
//

import SwiftUI
import UIKit

struct SharedThumbnailView: View {
    let thumbnailName: String?

    @State private var loadedImage: UIImage?

    private static let thumbnailWidth: CGFloat = 88

    var body: some View {
        let normalizedThumbnailName = Self.normalizedThumbnailName(thumbnailName)

        Group {
            if let loadedImage {
                Image(uiImage: loadedImage)
                    .resizable()
                    .scaledToFit()
            } else if let normalizedThumbnailName, UIImage(named: normalizedThumbnailName) != nil {
                Image(normalizedThumbnailName)
                    .resizable()
                    .scaledToFit()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.secondarySystemFill))
                    Image(systemName: "cube.transparent")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
        .task(id: normalizedThumbnailName) {
            loadedImage = nil
            guard let thumbnailPath = normalizedThumbnailName,
                  UIImage(named: thumbnailPath) == nil else {
                return
            }

            let image = await ScanThumbnailLoader.load(
                from: thumbnailPath,
                maxPixelSize: Self.thumbnailMaxPixelSize
            )
            guard !Task.isCancelled else { return }
            loadedImage = image
        }
    }

    private static var thumbnailMaxPixelSize: Int {
        Int(thumbnailWidth * UIScreen.main.scale)
    }

    nonisolated static func normalizedThumbnailName(_ thumbnailName: String?) -> String? {
        let trimmed = thumbnailName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
