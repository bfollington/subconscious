//
//  WikilinkBarView.swift
//  Subconscious
//
//  Created by Gordon Brander on 4/21/22.
//

import SwiftUI

/// Toolbar that displays entry links in a horizontal bar
struct SlashlinkBarView: View {
    var links: [EntryLink]
    var onSelectLink: (EntryLink) -> Void
    var max = 2

    var body: some View {
        HStack(alignment: .center, spacing: AppTheme.unit4) {
            ForEach(links.prefix(max)) { link in
                Button(
                    action: {
                        onSelectLink(link)
                    },
                    label: {
                        Text(link.slug.toSlashlink())
                            .lineLimit(1)
                    }
                )
                Divider()
            }
        }
    }
}

struct SlashlinkBarView_Previews: PreviewProvider {
    static var previews: some View {
        SlashlinkBarView(
            links: [
                EntryLink(title: "Finn the Human")!,
                EntryLink(title: "Land of OOO")!
            ],
            onSelectLink: { _ in }
        )
    }
}