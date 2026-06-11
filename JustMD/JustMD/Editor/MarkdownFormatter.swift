import Foundation

/// Pure-logic helper for toggling markdown bold/italic delimiters around a selection.
///
/// Rules:
/// - Empty selection inserts the paired delimiter and places the caret between them.
/// - Non-empty selection whose contents start and end with the delimiter is unwrapped
///   (delimiters stripped from the selected substring).
/// - Non-empty selection that is immediately surrounded by the delimiter in the source
///   is unwrapped by removing the surrounding delimiters from the source.
/// - Otherwise the selected substring is wrapped in the delimiter and the new selection
///   covers the original substring (without the newly added delimiters).
nonisolated struct MarkdownFormatter {

    enum Delimiter {
        case bold    // **
        case italic  // *

        var string: String {
            self == .bold ? "**" : "*"
        }
    }

    struct WrapResult: Equatable {
        let newString: String
        let newSelection: NSRange
    }

    static func wrap(source: String, selection rawSelection: NSRange, delimiter: Delimiter) -> WrapResult {
        let ns = source as NSString
        let delim = delimiter.string
        let delimNS = delim as NSString
        let delimLen = delimNS.length

        // Shrink the selection to exclude leading/trailing whitespace and newlines.
        // Triple-click selections include the trailing newline, and CommonMark
        // emphasis delimiters cannot sit adjacent to whitespace — `**para\n**`
        // would not parse, so the highlighter would silently drop the styling.
        let selection = trimmed(selection: rawSelection, in: ns)

        // Empty selection: insert "<delim><delim>" and place caret between them.
        if selection.length == 0 {
            let insertion = delim + delim
            let newString = ns.replacingCharacters(in: selection, with: insertion)
            let caret = NSRange(location: selection.location + delimLen, length: 0)
            return WrapResult(newString: newString, newSelection: caret)
        }

        let selectedText = ns.substring(with: selection)
        let selectedNS = selectedText as NSString

        // Case: selection already includes the delimiters on both sides.
        if selectedNS.length >= delimLen * 2
            && selectedNS.hasPrefix(delim)
            && selectedNS.hasSuffix(delim) {
            let innerRange = NSRange(location: delimLen, length: selectedNS.length - delimLen * 2)
            let inner = selectedNS.substring(with: innerRange)
            let newString = ns.replacingCharacters(in: selection, with: inner)
            let newSelection = NSRange(location: selection.location, length: (inner as NSString).length)
            return WrapResult(newString: newString, newSelection: newSelection)
        }

        // Case: selection is surrounded by the delimiters in the source (outside the selection).
        if selection.location >= delimLen
            && selection.location + selection.length + delimLen <= ns.length {
            let prefixRange = NSRange(location: selection.location - delimLen, length: delimLen)
            let suffixRange = NSRange(location: selection.location + selection.length, length: delimLen)
            if ns.substring(with: prefixRange) == delim && ns.substring(with: suffixRange) == delim {
                // Remove the surrounding delimiters.
                let removeRange = NSRange(location: selection.location - delimLen,
                                          length: selection.length + delimLen * 2)
                let newString = ns.replacingCharacters(in: removeRange, with: selectedText)
                let newSelection = NSRange(location: selection.location - delimLen, length: selection.length)
                return WrapResult(newString: newString, newSelection: newSelection)
            }
        }

        // Default: wrap the selection in the delimiter.
        let wrapped = delim + selectedText + delim
        let newString = ns.replacingCharacters(in: selection, with: wrapped)
        let newSelection = NSRange(location: selection.location + delimLen, length: selection.length)
        return WrapResult(newString: newString, newSelection: newSelection)
    }

    /// Shrinks `selection` so it starts and ends on non-whitespace. A selection
    /// that is entirely whitespace collapses to an empty range at its start.
    private static func trimmed(selection: NSRange, in ns: NSString) -> NSRange {
        guard selection.length > 0, NSMaxRange(selection) <= ns.length else { return selection }
        let ws = CharacterSet.whitespacesAndNewlines
        var start = selection.location
        var end = NSMaxRange(selection)
        while start < end {
            guard let scalar = Unicode.Scalar(ns.character(at: start)), ws.contains(scalar) else { break }
            start += 1
        }
        while end > start {
            guard let scalar = Unicode.Scalar(ns.character(at: end - 1)), ws.contains(scalar) else { break }
            end -= 1
        }
        if start == end { return NSRange(location: selection.location, length: 0) }
        return NSRange(location: start, length: end - start)
    }
}
