//
//  BlockView.swift
//  Subconscious
//
//  Created by Gordon Brander on 4/7/21.
//

import SwiftUI

/// Provides a single concrete view for all kinds of block
struct BlockView: View, Equatable {
    var block: Subtext2.BlockNode

    var body: some View {
        VStack(alignment: .leading) {
            Text(
                block.renderMarkupAttributedString(
                    url: { wikitext in
                        SubURL.wikilinkToURL(wikitext)
                    }
                )
            ).multilineTextAlignment(.leading)
        }
    }
}
