//
//  FABButtonStyle.swift
//  Subconscious
//
//  Created by Gordon Brander on 12/14/21.
//

import SwiftUI
import SwiftSubsurface

/// Wraps
struct FABView: View {
    var image: Image = Image(systemName: "doc.text.magnifyingglass")
    var action: () -> Void

    var body: some View {
        Button(
            action: action,
            label: {
                image.font(.system(size: 20))
            }
        )
        .buttonStyle(
            FABButtonStyle(
                orbShaderEnabled: Config.default.orbShaderEnabled
            )
        )
    }
}

struct FABButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var orbShaderEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            if orbShaderEnabled {
                SubsurfaceView(speed: 0.05, density: 0.75, corner_radius: 64)
                    .clipped()
                    .clipShape(Circle())
                    .frame(
                        width: AppTheme.fabSize,
                        height: AppTheme.fabSize,
                        alignment: .center
                    )
                    .shadow(
                        radius: 8,
                        x: 0,
                        y: 4
                    )
            } else {
                Circle()
                    .foregroundColor(Color.fabBackground)
                    .frame(
                        width: AppTheme.fabSize,
                        height: AppTheme.fabSize,
                        alignment: .center
                    )
                    .shadow(
                        radius: 8,
                        x: 0,
                        y: 4
                    )
            }
            configuration.label
                .foregroundColor(
                    isEnabled ? Color.fabText : Color.fabTextDisabled
                )
                .contentShape(
                    Circle()
                )
        }
        .scaleEffect(configuration.isPressed ? 0.8 : 1, anchor: .center)
        .animation(
            .easeOutCubic(duration: Duration.fast),
            value: configuration.isPressed
        )
        .animation(
            .easeOutCubic(duration: Duration.keyboard),
            value: isEnabled
        )
        .opacity(isEnabled ? 1 : 0)
        .transition(
            .opacity.combined(
                with: .scale(scale: 0.8, anchor: .center)
            )
        )
    }
}
