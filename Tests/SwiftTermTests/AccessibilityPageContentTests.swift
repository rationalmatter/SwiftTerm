//
//  AccessibilityPageContentTests.swift
//
//  Regression tests for the rows `TerminalView` reads while serving
//  `UIAccessibilityReadingContent`.
//
//  The page accessors derive their first row from `contentOffset`, which a
//  rubber-band bounce or a safe-area or keyboard inset leaves negative, and
//  which can still point past the content after the buffer shrank.  The line
//  accessors take whatever line number the assistive client hands back.  Each
//  of those rows must be clamped to the buffer before it indexes `lines`:
//  the circular list traps on a negative index (rationalmatter/Juno#1683).
//

#if os(iOS) || os(visionOS)
import XCTest
import UIKit

@testable import SwiftTerm

final class AccessibilityPageContentTests: XCTestCase {
    /// More lines than the view shows, so there is scrollback above the screen.
    private let lineCount = 60
    /// How far outside the content the out-of-range offsets and line numbers reach.
    private let overshootRows = 3

    private func line(_ number: Int) -> String {
        "line \(number)"
    }

    /// A terminal holding `lineCount` numbered lines, the last one on the
    /// buffer's bottom row.
    private func makeTerminalView() -> TerminalView {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        view.feed(text: (1...lineCount).map(line).joined(separator: "\r\n"))
        return view
    }

    private func lastRow(of view: TerminalView) -> Int {
        view.terminal.displayBuffer.lines.count - 1
    }

    private func scroll(_ view: TerminalView, toRow row: CGFloat) {
        view.contentOffset = CGPoint(x: 0, y: row * view.cellDimension.height)
    }

    private func trimmed(_ text: String?) -> String? {
        text?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Offsets inside the content

    func testPageStartsWithTheRowUnderTheOffset() {
        let view = makeTerminalView()
        XCTAssertGreaterThan(lastRow(of: view) + 1, view.terminal.rows, "the fixture must have scrollback")

        for row in [0, 10] {
            scroll(view, toRow: CGFloat(row))

            XCTAssertEqual(view.accessibilityPageContent()?.hasPrefix(line(row + 1)), true)
            XCTAssertEqual(view.accessibilityAttributedPageContent()?.string.hasPrefix(line(row + 1)), true)
        }
    }

    // MARK: - Offsets outside the content

    /// A bounce past the top, or a top inset the offset has not been adjusted
    /// for yet, reads the page at the top rather than a row above it.
    func testNegativeOffsetReadsThePageAtTheTop() {
        let view = makeTerminalView()
        scroll(view, toRow: 0)
        let top = view.accessibilityPageContent()
        let attributedTop = view.accessibilityAttributedPageContent()?.string

        scroll(view, toRow: -CGFloat(overshootRows))

        XCTAssertEqual(view.accessibilityPageContent(), top)
        XCTAssertEqual(view.accessibilityAttributedPageContent()?.string, attributedTop)
    }

    /// Half a row of bounce is enough to round the first row down to -1.
    func testFractionalNegativeOffsetReadsThePageAtTheTop() {
        let view = makeTerminalView()
        scroll(view, toRow: 0)
        let attributedTop = view.accessibilityAttributedPageContent()?.string

        scroll(view, toRow: -0.5)

        XCTAssertEqual(view.accessibilityAttributedPageContent()?.string, attributedTop)
    }

    /// An offset left below the content, e.g. after the buffer shrank, reads
    /// the last row rather than a row the buffer does not hold.
    func testOffsetPastTheEndReadsTheLastRow() {
        let view = makeTerminalView()
        let last = lastRow(of: view)

        scroll(view, toRow: CGFloat(last + 1 + overshootRows))

        XCTAssertEqual(trimmed(view.accessibilityPageContent()), line(lineCount))
        XCTAssertEqual(trimmed(view.accessibilityAttributedPageContent()?.string), line(lineCount))
    }

    // MARK: - Line numbers outside the buffer

    func testNegativeLineNumberReadsTheFirstLine() {
        let view = makeTerminalView()

        let first = view.accessibilityAttributedContent(forLineNumber: 0)?.string
        XCTAssertEqual(first, line(1))
        XCTAssertEqual(view.accessibilityAttributedContent(forLineNumber: -overshootRows)?.string, first)
    }

    func testLineNumberPastTheEndReadsTheLastLine() {
        let view = makeTerminalView()
        let last = lastRow(of: view)

        let lastLine = view.accessibilityAttributedContent(forLineNumber: last)?.string
        XCTAssertEqual(lastLine, line(lineCount))
        XCTAssertEqual(view.accessibilityAttributedContent(forLineNumber: last + 1 + overshootRows)?.string, lastLine)
    }

    // MARK: - Plain content and frame by line number

    /// In-range line numbers read their own row, and their frames are one row
    /// tall, as wide as the line, and one row further down per line number.
    func testPlainContentAndFrameOfAnInRangeLineNumber() {
        let view = makeTerminalView()
        scroll(view, toRow: 0)
        let row = 10
        let cell = view.cellDimension

        XCTAssertEqual(trimmed(view.accessibilityContent(forLineNumber: row)), line(row + 1))

        let first = view.accessibilityFrame(forLineNumber: 0)
        let frame = view.accessibilityFrame(forLineNumber: row)
        XCTAssertEqual(first.size, CGSize(width: CGFloat(view.terminal.cols) * cell.width, height: cell.height))
        XCTAssertEqual(frame.size, first.size)
        XCTAssertEqual(frame.minX, first.minX)
        XCTAssertEqual(frame.minY, first.minY + CGFloat(row) * cell.height, accuracy: 0.001)
    }

    func testPlainContentForNegativeLineNumberReadsTheFirstLine() {
        let view = makeTerminalView()

        let first = view.accessibilityContent(forLineNumber: 0)
        XCTAssertEqual(trimmed(first), line(1))
        for row in [-1, -overshootRows] {
            XCTAssertEqual(view.accessibilityContent(forLineNumber: row), first)
        }
    }

    func testPlainContentForLineNumberPastTheEndReadsTheLastLine() {
        let view = makeTerminalView()
        let last = lastRow(of: view)

        let lastLine = view.accessibilityContent(forLineNumber: last)
        XCTAssertEqual(trimmed(lastLine), line(lineCount))
        XCTAssertEqual(view.accessibilityContent(forLineNumber: last + 1 + overshootRows), lastLine)
    }

    func testFrameForNegativeLineNumberIsTheFirstLinesFrame() {
        let view = makeTerminalView()
        scroll(view, toRow: 0)

        let first = view.accessibilityFrame(forLineNumber: 0)
        for row in [-1, -overshootRows] {
            XCTAssertEqual(view.accessibilityFrame(forLineNumber: row), first)
        }
    }

    func testFrameForLineNumberPastTheEndIsTheLastLinesFrame() {
        let view = makeTerminalView()
        let last = lastRow(of: view)
        scroll(view, toRow: CGFloat(last))

        XCTAssertEqual(view.accessibilityFrame(forLineNumber: last + 1 + overshootRows),
                       view.accessibilityFrame(forLineNumber: last))
    }

    // MARK: - Synchronized output

    /// Opens a synchronized-output block and switches to the alternate screen
    /// inside it. The display buffer stays frozen on the normal screen and its
    /// scrollback, while the live buffer is now the alternate screen, which is
    /// only as tall as the view.
    private func enterAlternateScreenDuringSynchronizedOutput(_ view: TerminalView) {
        let displayedRows = view.terminal.displayBuffer.lines.count

        view.feed(text: "\u{1b}[?2026h\u{1b}[?1049h")

        XCTAssertTrue(view.terminal.synchronizedOutputActive)
        XCTAssertEqual(view.terminal.displayBuffer.lines.count, displayedRows, "the display buffer must stay frozen")
        XCTAssertLessThan(view.terminal.buffer.lines.count, displayedRows, "the live buffer must be shorter than the display")
    }

    /// Line numbers are rows of the display buffer the content is laid out
    /// from, so the last displayed row is read even when the live buffer
    /// holds fewer rows.
    func testLineNumberReadsTheDisplayBufferDuringSynchronizedOutput() {
        let view = makeTerminalView()
        let last = lastRow(of: view)

        enterAlternateScreenDuringSynchronizedOutput(view)

        XCTAssertEqual(view.accessibilityAttributedContent(forLineNumber: last)?.string, line(lineCount))
        XCTAssertEqual(view.accessibilityAttributedContent(forLineNumber: last + 1 + overshootRows)?.string, line(lineCount))
        XCTAssertEqual(trimmed(view.accessibilityContent(forLineNumber: last)), line(lineCount))
        XCTAssertEqual(trimmed(view.accessibilityContent(forLineNumber: last + 1 + overshootRows)), line(lineCount))
        XCTAssertEqual(view.accessibilityFrame(forLineNumber: last + 1 + overshootRows),
                       view.accessibilityFrame(forLineNumber: last))
    }

    /// The rows a wrapped line spans are found in the same display buffer the
    /// text is read from, not in the live buffer's wrap flags.
    func testWrappedLineReadsWholeFromTheDisplayBufferDuringSynchronizedOutput() {
        let view = makeTerminalView()
        let cols = view.terminal.cols
        let wrapped = String(repeating: "w", count: cols + cols / 2)
        view.feed(text: "\r\n" + wrapped)
        let last = lastRow(of: view)
        XCTAssertTrue(view.terminal.displayBuffer.lines[last].isWrapped, "the fixture must end in a wrapped line")

        enterAlternateScreenDuringSynchronizedOutput(view)

        XCTAssertEqual(view.accessibilityAttributedContent(forLineNumber: last)?.string, wrapped)
        XCTAssertEqual(trimmed(view.accessibilityContent(forLineNumber: last)), wrapped)
    }
}
#endif
