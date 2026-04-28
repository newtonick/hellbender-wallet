import SwiftUI
import UIKit

/// A text view that wraps by character instead of by word,
/// preventing line breaks at "/" and other word-boundary characters.
struct CharWrapText: UIViewRepresentable {
  let text: String
  let font: UIFont
  let textColor: Color

  init(_ text: String, font: UIFont = .monospacedSystemFont(ofSize: 10, weight: .regular), color: Color = .primary) {
    self.text = text
    self.font = font
    textColor = color
  }

  func makeUIView(context _: Context) -> CharWrapLabel {
    let label = CharWrapLabel()
    label.numberOfLines = 0
    label.lineBreakMode = .byCharWrapping
    label.font = font
    label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return label
  }

  func updateUIView(_ label: CharWrapLabel, context _: Context) {
    label.text = text
    label.font = font
    label.textColor = UIColor(textColor)
    label.invalidateIntrinsicContentSize()
  }
}

/// UILabel subclass that sets preferredMaxLayoutWidth on layout,
/// allowing character wrapping to work inside SwiftUI.
final class CharWrapLabel: UILabel {
  override func layoutSubviews() {
    super.layoutSubviews()
    if preferredMaxLayoutWidth != bounds.width {
      preferredMaxLayoutWidth = bounds.width
      invalidateIntrinsicContentSize()
    }
  }
}
