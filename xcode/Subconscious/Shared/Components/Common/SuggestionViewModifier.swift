//
//  SuggestionViewModifier.swift
//  Subconscious
//
//  Created by Gordon Brander on 9/28/21.
//

import SwiftUI

/// SuggestionView is a row in a `List` of suggestions.
/// It sets the basic list styles we use for suggestions.
/// Apply it to the "row" view which is an immediate child of `List`.
struct SuggestionViewModifier: ViewModifier {
    var insets: EdgeInsets = EdgeInsets(
        top: AppTheme.unit2,
        leading: AppTheme.padding,
        bottom: AppTheme.unit2,
        trailing: AppTheme.padding
    )

    func body(content: Content) -> some View {
        content
            .labelStyle(
                SuggestionLabelStyle(
                    spacing: insets.leading
                )
            )
            .listRowInsets(insets)
            .listRowSeparator(.hidden, edges: .all)
    }
}