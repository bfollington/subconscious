//
//  TranscludeView.swift
//  Subconscious (iOS)
//
//  Created by Gordon Brander on 7/22/21.
//

import SwiftUI

struct TranscludeView: View {
    var dom: Subtext

    init(dom: Subtext) {
        self.dom = dom.filter(Subtext.Block.isContent).prefix(2)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(dom.blocks) { block in
                BlockView(block: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 24)
        .contentShape(Rectangle())
        .background(Color.Sub.secondaryBackground)
        .cornerRadius(CGFloat(SubConstants.Theme.cornerRadius))
    }
}

struct TranscludeView_Previews: PreviewProvider {
    static var previews: some View {
        TranscludeView(
            dom: Subtext(
                markup: """
                # Namespaced wikilinks

                In a federated system, you sometimes want to be able to reference some particular “truth”. The default wikilink should refer to my view of the world (my documents for this term). However, you also want to be able to reference Alice and Bob’s views of this term.

                """
            )
        )
    }
}