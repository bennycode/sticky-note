import AppKit

/// Popover content with a small "A", the current size and a large "A". It stays open so you can click repeatedly.
final class FontSizeViewController: NSViewController {
  var onSmaller: () -> Void = {}
  var onBigger: () -> Void = {}

  private let smallerButton = NSButton()
  private let biggerButton = NSButton()
  private let sizeLabel = NSTextField(labelWithString: "")

  override func loadView() {
    configure(smallerButton, fontSize: 11, action: #selector(smaller), label: "Smaller")
    configure(biggerButton, fontSize: 18, action: #selector(bigger), label: "Bigger")

    sizeLabel.alignment = .center
    sizeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    sizeLabel.textColor = .secondaryLabelColor
    sizeLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true

    let stackView = NSStackView(views: [smallerButton, sizeLabel, biggerButton])
    stackView.spacing = 6
    stackView.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
    view = stackView
  }

  func update(fontSize: Double, canShrink: Bool, canGrow: Bool) {
    _ = view
    sizeLabel.stringValue = "\(Int(fontSize)) pt"
    smallerButton.isEnabled = canShrink
    biggerButton.isEnabled = canGrow
  }

  private func configure(_ button: NSButton, fontSize: CGFloat, action: Selector, label: String) {
    button.title = "A"
    button.font = .systemFont(ofSize: fontSize, weight: .medium)
    button.bezelStyle = .accessoryBarAction
    button.target = self
    button.action = action
    button.setAccessibilityLabel(label)
    button.toolTip = label
    button.widthAnchor.constraint(equalToConstant: 32).isActive = true
    button.heightAnchor.constraint(equalToConstant: 28).isActive = true
  }

  @objc private func smaller() {
    onSmaller()
  }

  @objc private func bigger() {
    onBigger()
  }
}
