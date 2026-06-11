import Foundation

/// Computes the minimal character window that must be restyled after an edit,
/// by diffing the block list from before the edit against the one after it.
///
/// Attributes ride along with characters in `NSTextStorage`, so a block that
/// merely *moved* (everything below an insertion/deletion) needs no work — its
/// styling moved with it. Only blocks whose structure or content changed need
/// a base-attribute reset and re-application. Restyling the whole document on
/// every keystroke is what made typing feel half-a-second slow.
nonisolated enum BlockDiff {

    /// - Parameters:
    ///   - old: blocks from the previous highlight pass (pre-edit coordinates).
    ///   - new: blocks from the fresh parse (post-edit coordinates).
    ///   - delta: net change in document length since the previous pass.
    ///   - editedRange: accumulated edited range, post-edit coordinates.
    ///   - newLength: current document length.
    /// - Returns: the contiguous range (post-edit coordinates) to restyle.
    ///   Always covers `editedRange` and every changed block entirely.
    static func changedWindow(
        old: [Block],
        new: [Block],
        delta: Int,
        editedRange: NSRange,
        newLength: Int
    ) -> NSRange {
        // Prefix: identical blocks that end before the edit. Identity of range
        // + payload is only trustworthy for text the edit didn't touch, so stop
        // at the first block reaching into the edited range.
        var prefix = 0
        let maxCommon = min(old.count, new.count)
        while prefix < maxCommon {
            let candidate = new[prefix]
            guard candidate == old[prefix],
                  NSMaxRange(candidate.range) <= editedRange.location else { break }
            prefix += 1
        }

        // Suffix: blocks past the edit whose pre-edit twin sits exactly `delta`
        // characters earlier. Type/payload equality catches structural cascades
        // (an opened code fence re-interprets everything below it).
        var suffix = 0
        while suffix < maxCommon - prefix {
            let candidate = new[new.count - 1 - suffix]
            guard candidate.range.location >= NSMaxRange(editedRange),
                  old[old.count - 1 - suffix].offset(by: delta) == candidate else { break }
            suffix += 1
        }

        var start = editedRange.location
        var end = NSMaxRange(editedRange)
        if prefix < new.count - suffix {
            start = min(start, new[prefix].range.location)
            end = max(end, NSMaxRange(new[new.count - 1 - suffix].range))
        }
        start = max(0, min(start, newLength))
        end = max(start, min(end, newLength))
        return NSRange(location: start, length: end - start)
    }
}
