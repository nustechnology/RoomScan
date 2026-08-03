//
//  SharedThumbnailView.swift
//  roomscan
//

import SwiftUI
import UIKit

struct SharedThumbnailView: View {
    let thumbnailName: String?

    var body: some View {
        Group {
            if let thumbnailName, UIImage(named: thumbnailName) != nil {
                Image(thumbnailName)
                    .resizable()
                    .scaledToFill()
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
    }
}
