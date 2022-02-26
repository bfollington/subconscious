//
//  BacklinksView.swift
//  Subconscious
//
//  Created by Gordon Brander on 9/20/21.
//

import SwiftUI

struct BacklinksView: View {
    var backlinks: [EntryStub]
    var onSelect: (EntryLink) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(
                    "Backlinks"
                )
                .font(Font(UIFont.appCaption))
                Spacer()
            }
            .padding(.horizontal, AppTheme.unit4)
            .padding(.vertical, AppTheme.unit2)
            ForEach(backlinks) { entry in
                Divider()
                Button(
                    action: {
                        onSelect(
                            EntryLink(
                                slug: entry.slug,
                                title: entry.title
                            )
                        )
                    },
                    label: {
                        EntryRow(entry: entry)
                    }
                )
                .buttonStyle(BacklinkButtonStyle())
            }
        }
    }
}

struct BacklinksView_Previews: PreviewProvider {
    static var previews: some View {
        BacklinksView(
            backlinks: [
                EntryStub(
                    slug: Slug("floop")!,
                    title: "Floop",
                    excerpt: "Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi.",
                    modified: Date.now
                )
            ],
            onSelect: { title in }
        )
    }
}
