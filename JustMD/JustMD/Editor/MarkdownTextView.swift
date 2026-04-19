import AppKit

@MainActor
final class MarkdownTextView: NSTextView {

    convenience init(storage: MarkdownTextStorage) {
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 720, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.heightTracksTextView = false
        layoutManager.addTextContainer(container)
        self.init(frame: .zero, textContainer: container)
        self.isRichText = false
        self.usesFindBar = false
        self.allowsUndo = true
        self.isAutomaticLinkDetectionEnabled = false
        self.isAutomaticSpellingCorrectionEnabled = false
        self.isAutomaticQuoteSubstitutionEnabled = false
        self.isAutomaticDashSubstitutionEnabled = false
        self.isAutomaticTextReplacementEnabled = false
        self.isAutomaticDataDetectionEnabled = false
        self.isContinuousSpellCheckingEnabled = false
        self.textContainerInset = NSSize(width: 40, height: 32)
    }
}
