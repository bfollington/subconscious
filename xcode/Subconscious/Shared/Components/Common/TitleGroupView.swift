//
//  TitleGroupView.swift
//  Subconscious
//
//  Created by Gordon Brander on 1/19/22.
//

import SwiftUI

/// A title/subtitle pair.
/// Often used in list views.
/// Each line is at least 1 icon in height.
struct TitleGroupView: View, Equatable {
    var title: Text
    var subtitle: Text
    var lineHeight: CGFloat = AppTheme.icon

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                title
                    .foregroundColor(Color.primary)
                Spacer()
            }
            .frame(minHeight: AppTheme.icon)
            HStack {
                subtitle
                    .font(.caption)
                    .foregroundColor(Color.secondary)
                Spacer()
            }
            .frame(minHeight: AppTheme.captionSize)
        }
    }
}

struct TitleGroup_Previews: PreviewProvider {
    static var previews: some View {
        TitleGroupView(
            title: Text("Foo"),
            subtitle: Text("Bar")
        )
    }
}
