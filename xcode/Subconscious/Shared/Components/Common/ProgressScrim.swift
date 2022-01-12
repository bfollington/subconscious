//
//  ProgressScrim.swift
//  Subconscious
//
//  Created by Gordon Brander on 1/12/22.
//

import SwiftUI

/// A progress view that takes up the whole space of its parent
struct ProgressScrim: View {
    var body: some View {
        VStack(alignment: .center) {
            Spacer()
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            Spacer()
        }
        .background(Color.background)
        .transition(.opacity)
    }
}

struct ProgressScrim_Previews: PreviewProvider {
    static var previews: some View {
        ProgressScrim()
    }
}
