//  Constants.swift
//  Subconscious (iOS)
//
//  Created by Gordon Brander on 6/10/21.
//
import SwiftUI
import os

struct Constants {
    static let rdns = "com.subconscious.Subconscious"

    static let logger = Logger(
        subsystem: rdns,
        category: "main"
    )

    static let databaseURL = try! FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
    ).appendingPathComponent("database.sqlite")

    static let documentDirectoryURL = FileManager.default.documentDirectoryUrl!

    struct Color {
        static let accent = SwiftUI.Color.accentColor
        static let background = SwiftUI.Color(.systemBackground)
        static let secondaryBackground = SwiftUI.Color(.secondarySystemBackground)
        static let text = SwiftUI.Color.primary
        static let secondaryText = SwiftUI.Color.secondary
        static let placeholderText = SwiftUI.Color(.placeholderText)
        static let link = accent
        static let inputBackground = secondaryBackground
        static let primaryButtonBackground = secondaryBackground
        static let primaryButtonPressedBackground = secondaryBackground
        static let primaryButtonDisabledBackground = secondaryBackground
        static let separator = SwiftUI.Color(.separator)
        static let icon = text
        static let secondaryIcon = secondaryText
        static let accentIcon = accent
        static let quotedText = accent
    }

    struct Text {
        static var textFont: AttributeContainer {
            var attributes = AttributeContainer()
            attributes.font = UIFont.preferredFont(forTextStyle: .body)
            return attributes
        }

        static var text: AttributeContainer {
            var attributes = AttributeContainer()
            attributes.foregroundColor = Constants.Color.text
            return attributes
        }

        static var heading: AttributeContainer {
            var attributes = AttributeContainer()
            let font = UIFont.preferredFont(forTextStyle: .body)
            if let desc = font.fontDescriptor.withSymbolicTraits(.traitBold) {
                // 0 means "keep same size"
                attributes.font = UIFont(descriptor: desc, size: 0)
            } else {
                attributes.font = font
            }
            attributes.foregroundColor = Constants.Color.text
            return attributes
        }

        static var secondary: AttributeContainer {
            var attributes = AttributeContainer()
            attributes.foregroundColor = Constants.Color.secondaryText
            return attributes
        }
    }

    struct Theme {
        static let cornerRadius: Double = 12
        static let buttonHeight: CGFloat = 40
    }

    struct Duration {
        static let fast: Double = 0.128
        static let `default`: Double = 0.2
    }
}

extension Shadow {
    static let lightShadow = Shadow(
        color: Color.black.opacity(0.05),
        radius: 2,
        x: 0,
        y: 0
    )
}
