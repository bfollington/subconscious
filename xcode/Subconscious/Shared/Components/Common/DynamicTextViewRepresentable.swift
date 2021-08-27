//
//  DynamicTextViewRepresentable.swift
//  Subconscious (iOS)
//
//  Created by Gordon Brander on 7/6/21.
//

import SwiftUI

/// A textview that grows to the height of its content
struct DynamicTextViewRepresentable: UIViewRepresentable {
    /// Extends UITTextView to provide an intrinsicContentSize given a fixed width.
    class DynamicTextView: UITextView {
        var fixedWidth: CGFloat = 0
        override var intrinsicContentSize: CGSize {
            sizeThatFits(CGSize(width: fixedWidth, height: frame.height))
        }
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var representable: DynamicTextViewRepresentable

        init(_ representable: DynamicTextViewRepresentable) {
            self.representable = representable
        }

        /// Intercept text changes before they happen, and accept or reject them.
        /// See  <https://developer.apple.com/documentation/uikit/uitextviewdelegate/1618630-textview>
        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            // If user hit enter
            if range.length == 0 && text == "\n" {
                textView.resignFirstResponder()
                return false
            // If user pasted text containing newline
            } else if text.contains("\n") {
                let clean = text.replacingOccurrences(
                    of: "\n",
                    with: " "
                )
                if let range = Range(range, in: textView.text) {
                    textView.text.replaceSubrange(range, with: clean)
                    textView.invalidateIntrinsicContentSize()
                    return false
                }
                return true
            }
            return true
        }
        
        func textViewDidChange(_ view: UITextView) {
            representable.text = view.text
            view.invalidateIntrinsicContentSize()
        }
    }

    @Binding var text: String
    var fixedWidth: CGFloat
    var font: UIFont = UIFont.preferredFont(forTextStyle: .body)
    var textColor: UIColor = UIColor(.primary)
    var textContainerInset: UIEdgeInsets = .zero

    func makeUIView(context: Context) -> DynamicTextView {
        let view = DynamicTextView()
        view.delegate = context.coordinator
        view.fixedWidth = fixedWidth
        // Remove that extra bit of inner padding.
        // Text in view should now be flush with view edge.
        // This puts you in full control of view padding.
        view.textContainer.lineFragmentPadding = 0
        view.backgroundColor = .clear
        view.textColor = textColor
        return view
    }

    func updateUIView(_ view: DynamicTextView, context: Context) {
        if view.text != text {
            // Save selected range (cursor position).
            let selectedRange = view.selectedRange
            view.text = text
            // Restore selected range (cursor position) after setting text.
            view.selectedRange = selectedRange
        }

        if view.fixedWidth != fixedWidth {
            view.fixedWidth = fixedWidth
            view.invalidateIntrinsicContentSize()
        }

        if view.font != font {
            view.font = font
        }

        if view.textContainerInset != textContainerInset {
            // Set inner padding
            view.textContainerInset = textContainerInset
        }
    }

    func makeCoordinator() -> DynamicTextViewRepresentable.Coordinator {
        Coordinator(self)
    }

    func font(_ font: UIFont) -> Self {
        var view = self
        view.font = font
        return view
    }

    func insets(_ inset: EdgeInsets) -> Self {
        var view = self
        view.textContainerInset = UIEdgeInsets(
            top: inset.top,
            left: inset.leading,
            bottom: inset.bottom,
            right: inset.trailing
        )
        return view
    }
}

struct DynamicTextViewRepresentable_Preview: PreviewProvider {
    static var previews: some View {
        GeometryReader { geometry in
            VStack {
                DynamicTextViewRepresentable(
                    text: .constant("Text"),
                    fixedWidth: geometry.size.width
                )
                .fixedSize(horizontal: false, vertical: true)
                .background(Constants.Color.secondaryBackground)

                DynamicTextViewRepresentable(
                    text: .constant("Text"),
                    fixedWidth: geometry.size.width
                )
                .fixedSize(horizontal: false, vertical: true)
                .background(Constants.Color.secondaryBackground)
            }
        }
    }
}
