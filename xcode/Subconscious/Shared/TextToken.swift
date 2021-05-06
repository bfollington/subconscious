//
//  TextToken.swift
//  Subconscious (iOS)
//
//  Created by Gordon Brander on 5/6/21.
//

import SwiftUI

struct TextToken: View {
    var text: String

    var body: some View {
        Text(text)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .foregroundColor(
                        Color("ButtonSecondary")
                    )
            )
    }
}

struct TextToken_Previews: PreviewProvider {
    static var previews: some View {
        TextToken(text: "#log")
    }
}
