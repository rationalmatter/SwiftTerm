//
//  TextInputOffsetTests.swift
//
//  Regression tests for the offsets `TerminalView` uses to index its
//  `textInputStorage` while serving `UITextInput`.
//
//  The text input system keeps `UITextPosition`/`UITextRange` objects across
//  edits, and it measures the strings we hand back from `text(in:)` in UTF-16.
//  `textInputStorage` is a `String` that is indexed by `Character`, so for text
//  whose UTF-16 length differs from its `Character` count -- Arabic with
//  harakat, combining marks, emoji ZWJ sequences -- the two models drift apart
//  and the offsets we receive can point past the end of the storage.  Every one
//  of those offsets must be clamped to the storage before it becomes a
//  `String.Index`, otherwise the process traps with "String index is out of
//  bounds" (rationalmatter/Juno#1602).
//

#if os(iOS) || os(visionOS)
import XCTest
import UIKit

@testable import SwiftTerm

final class TextInputOffsetTests: XCTestCase {
    /// "مرحبا" with harakat: 5 grapheme clusters, 9 UTF-16 code units.
    private let arabic = "مَرْحَبًا"
    /// "e" plus a combining acute accent: 1 grapheme cluster, 2 UTF-16 code units.
    private let combining = "e\u{301}"
    /// A family emoji: 1 grapheme cluster, 8 UTF-16 code units.
    private let zwjEmoji = "👨‍👩‍👧"

    private func makeTerminalView() -> TerminalView {
        TerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
    }

    /// Types `text`, then hands back the document range the input system would
    /// be holding on to, and clears the input buffer the way the return key
    /// does.  What is left is a range whose offsets no longer fit the storage.
    private func staleDocumentRange(after text: String, in view: TerminalView) -> UITextRange {
        view.insertText(text)
        guard let range = view.textRange(from: view.beginningOfDocument, to: view.endOfDocument) else {
            fatalError("the terminal view must vend a document range")
        }
        view.insertText("\n")
        XCTAssertEqual(view.textInputStorage, "", "the return key resets the input buffer")
        return range
    }

    // MARK: - The text input protocol and the storage must agree on one unit

    func testDocumentLengthIsExpressedInStorageUnits() {
        let view = makeTerminalView()
        view.insertText(arabic)

        XCTAssertEqual(view.textInputStorage, arabic)
        XCTAssertNotEqual(arabic.count, arabic.utf16.count, "the fixture must be multi-unit")

        let documentLength = view.offset(from: view.beginningOfDocument, to: view.endOfDocument)
        XCTAssertEqual(documentLength, arabic.count)

        guard let documentRange = view.textRange(from: view.beginningOfDocument, to: view.endOfDocument) else {
            return XCTFail("the terminal view must vend a document range")
        }
        XCTAssertEqual(view.text(in: documentRange), arabic)
    }

    func testMultiUnitTextRoundTripsThroughTheInputBuffer() {
        let view = makeTerminalView()
        for text in [combining, zwjEmoji, arabic] {
            view.insertText(text)
        }

        let expected = combining + zwjEmoji + arabic
        XCTAssertEqual(view.textInputStorage, expected)
        XCTAssertEqual(view.offset(from: view.beginningOfDocument, to: view.endOfDocument), expected.count)
        XCTAssertEqual(view.offset(from: view.beginningOfDocument, to: view.selectedTextRange!.start), expected.count)
    }

    // MARK: - Offsets that outlive the text they were measured against

    func testInsertTextWithStaleMarkedRangeDoesNotTrap() {
        let view = makeTerminalView()
        let stale = staleDocumentRange(after: arabic, in: view)

        // The keyboard reinstates the marked range it was still holding.
        view.markedTextRange = stale
        view.insertText("ا")

        XCTAssertEqual(view.textInputStorage, "ا")
        XCTAssertNil(view.markedTextRange)
    }

    func testInsertTextClampsAMarkedRangeMeasuredInUTF16() {
        let view = makeTerminalView()
        view.insertText(arabic)

        // The state the reported crash traps in: a marked range whose offsets
        // were measured in UTF-16 units of the Arabic text, applied to a
        // storage that indexes the same text by Character.
        view._markedTextRange = TextRange(from: TextPosition(offset: 0),
                                          to: TextPosition(offset: arabic.utf16.count))
        view.insertText("ا")

        XCTAssertEqual(view.textInputStorage, "ا")
        XCTAssertNil(view.markedTextRange)
    }

    func testTextInStaleRangeDoesNotTrap() {
        let view = makeTerminalView()
        let stale = staleDocumentRange(after: arabic, in: view)

        XCTAssertEqual(view.text(in: stale), "")
    }

    func testReplaceWithStaleRangeDoesNotTrap() {
        let view = makeTerminalView()
        let stale = staleDocumentRange(after: arabic, in: view)

        view.replace(stale, withText: "x")

        XCTAssertEqual(view.textInputStorage, "x")
    }

    func testDeleteBackwardWithStaleMarkedRangeDoesNotTrap() {
        let view = makeTerminalView()
        let stale = staleDocumentRange(after: arabic, in: view)

        view.markedTextRange = stale
        view.deleteBackward()

        XCTAssertEqual(view.textInputStorage, "")
    }

    func testSetMarkedTextWithStaleMarkedRangeDoesNotTrap() {
        let view = makeTerminalView()
        let stale = staleDocumentRange(after: arabic, in: view)

        view.markedTextRange = stale
        view.setMarkedText(combining, selectedRange: NSRange(location: combining.utf16.count, length: 0))

        XCTAssertEqual(view.textInputStorage, combining)
        XCTAssertEqual(view.offset(from: view.beginningOfDocument, to: view.selectedTextRange!.start), combining.count)
    }

    // MARK: - UTF-16 ranges handed to setMarkedText

    func testMarkedTextSelectionIsConvertedFromUTF16() {
        let view = makeTerminalView()
        // The selected range of setMarkedText is measured in UTF-16 units of the
        // marked text, not in the units the storage indexes by.
        view.setMarkedText(arabic, selectedRange: NSRange(location: arabic.utf16.count, length: 0))

        XCTAssertEqual(view.textInputStorage, arabic)
        XCTAssertEqual(view.offset(from: view.beginningOfDocument, to: view.selectedTextRange!.start), arabic.count)

        view.unmarkText()
        XCTAssertNil(view.markedTextRange)
        XCTAssertEqual(view.textInputStorage, arabic)
    }

    func testMarkedTextSelectionInsideAGraphemeClusterDoesNotTrap() {
        let view = makeTerminalView()
        // A UTF-16 offset that falls between the base letter and its combining
        // mark has no equivalent position in the storage's own units.
        view.setMarkedText(combining, selectedRange: NSRange(location: 1, length: 0))

        XCTAssertEqual(view.textInputStorage, combining)
        let caret = view.offset(from: view.beginningOfDocument, to: view.selectedTextRange!.start)
        XCTAssertTrue((0...combining.count).contains(caret), "caret \(caret) must stay inside the storage")
    }

    func testMarkedTextSelectionPastTheEndDoesNotTrap() {
        let view = makeTerminalView()
        // A range the marked text cannot hold at all, e.g. a keyboard that
        // measured the caret against a longer, already replaced composition.
        view.setMarkedText(zwjEmoji, selectedRange: NSRange(location: zwjEmoji.utf16.count + 1, length: 0))

        XCTAssertEqual(view.textInputStorage, zwjEmoji)
        let caret = view.offset(from: view.beginningOfDocument, to: view.selectedTextRange!.start)
        XCTAssertTrue((0...zwjEmoji.count).contains(caret), "caret \(caret) must stay inside the storage")
    }
}
#endif
