//
//  LegalDocumentView.swift
//  roomscan
//

import SwiftUI

struct LegalDocumentView: View {
    let titleKey: LocalizedStringKey
    let bodyKey: LocalizedStringKey

    var body: some View {
        ScrollView {
            Text(bodyKey)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(titleKey)
        .navigationBarTitleDisplayMode(.inline)
    }
}
