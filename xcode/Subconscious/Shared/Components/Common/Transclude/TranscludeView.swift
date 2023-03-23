//
//  TranscludeView.swift
//  Subconscious
//
//  Created by Gordon Brander on 8/23/22.
//

import SwiftUI

struct TranscludeView: View {
    var pfp: Image
    var petname: String
    var slashlink: String
    var excerpt: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.unit) {
            BylineSmView(
                pfp: pfp,
                petname: petname,
                slug: slashlink
            )
            Text(excerpt)
        }
        .padding(.vertical, AppTheme.unit3)
        .padding(.horizontal, AppTheme.unit4)
        .overlay(
            RoundedRectangle(
                cornerRadius: AppTheme.cornerRadiusLg
            )
            .stroke(Color.separator, lineWidth: 0.5)
        )
    }
}

struct TranscludeView_Previews: PreviewProvider {
    static var previews: some View {
        TranscludeView(
            pfp: Image("pfp-dog"),
            petname: "@doge",
            slashlink: "/thoughts",
            excerpt: "Thoughts of Doge. Food food park park park run run play run fetch ball run water shlorp shlorp shlorp dog bork bork bork home sleep sleep dream sleep"
        )
    }
}