//
//  LinkLookupTests.swift
//
//
//  Created by Codex on 1/31/26.
//

import Foundation
import Testing

@testable import SwiftTerm

final class LinkLookupTests: TerminalDelegate {
    func send(source: Terminal, data: ArraySlice<UInt8>) {
    }

    private func write(_ text: String, terminal: Terminal, row: Int, col: Int = 0) {
        guard row >= 0 && row < terminal.displayBuffer.lines.count else {
            return
        }
        let line = terminal.displayBuffer.lines[row]
        var x = col
        for ch in text {
            guard x < terminal.cols else { break }
            line[x] = terminal.makeCharData(attribute: CharData.defaultAttr, char: ch)
            x += 1
        }
    }

    @Test func testExplicitLinkLookup() {
        let terminal = Terminal(delegate: self, options: TerminalOptions(cols: 10, rows: 1))
        terminal.feed(text: "abc")

        let payload = "id;https://example.com"
        let atom = TinyAtom.lookup(value: payload)!
        let line = terminal.displayBuffer.lines[0]
        var cd = line[1]
        cd.setPayload(atom: atom)
        line[1] = cd

        let link = terminal.link(at: .buffer(Position(col: 1, row: 0)), mode: .explicitOnly)
        #expect(link == "https://example.com")
    }

    @Test func testImplicitUrlLookup() {
        let terminal = Terminal(delegate: self, options: TerminalOptions(cols: 40, rows: 1))
        terminal.feed(text: "https://example.com tail")

        let link = terminal.link(at: .buffer(Position(col: 5, row: 0)), mode: .explicitAndImplicit)
        #expect(link == "https://example.com")
    }

    @Test func testImplicitFilePathLookup() {
        let terminal = Terminal(delegate: self, options: TerminalOptions(cols: 30, rows: 1))
        terminal.feed(text: "/tmp/example.txt")

        let link = terminal.link(at: .buffer(Position(col: 2, row: 0)), mode: .explicitAndImplicit)
        #expect(link == "/tmp/example.txt")
    }

    @Test func testImplicitUrlLookupAcrossWrappedLines() {
        let url = "https://example.com/path"
        let terminal = Terminal(delegate: self, options: TerminalOptions(cols: 8, rows: 4))
        terminal.feed(text: url)

        let topRowLink = terminal.link(at: .buffer(Position(col: 2, row: 0)), mode: .explicitAndImplicit)
        #expect(topRowLink == url)

        let wrappedRowLink = terminal.link(at: .buffer(Position(col: 1, row: 1)), mode: .explicitAndImplicit)
        #expect(wrappedRowLink == url)
    }

    @Test func testImplicitMatchReportsPerRowRangesAcrossWrap() {
        let url = "https://example.com/path"
        let terminal = Terminal(delegate: self, options: TerminalOptions(cols: 8, rows: 4))
        terminal.feed(text: url)

        guard let match = terminal.linkMatch(at: .buffer(Position(col: 1, row: 1)), mode: .explicitAndImplicit) else {
            Issue.record("Expected implicit link match on wrapped row")
            return
        }
        #expect(match.text == url)
        #expect(match.rowRanges.count >= 2)
        #expect(match.rowRanges.contains { $0.row == 0 })
        #expect(match.rowRanges.contains { $0.row == 1 })
        #expect(match.rowRanges.first(where: { $0.row == 1 })?.range.contains(1) == true)
    }

    @Test func testImplicitUrlLookupAcrossWrappedContinuationWithIndentation() {
        let terminal = Terminal(delegate: self, options: TerminalOptions(cols: 20, rows: 3))
        write("https://example.", terminal: terminal, row: 0)
        write("    com/path", terminal: terminal, row: 1)
        terminal.displayBuffer.lines[1].isWrapped = true

        let wrappedRowLink = terminal.link(at: .buffer(Position(col: 6, row: 1)), mode: .explicitAndImplicit)
        #expect(wrappedRowLink == "https://example.com/path")
    }

    @Test func testImplicitUrlLookupAcrossEditorSoftWrapWithoutWrappedFlag() {
        let terminal = Terminal(delegate: self, options: TerminalOptions(cols: 92, rows: 4))
        let firstSegment = "https://example.com/this/is/a/long/url/segment/that/reaches/the/visual/wrap/"
        write(firstSegment, terminal: terminal, row: 0)
        write("    and/keeps/going", terminal: terminal, row: 1)

        let firstRowLink = terminal.link(at: .buffer(Position(col: 20, row: 0)), mode: .explicitAndImplicit)
        #expect(firstRowLink == firstSegment + "and/keeps/going")

        let wrappedRowLink = terminal.link(at: .buffer(Position(col: 8, row: 1)), mode: .explicitAndImplicit)
        #expect(wrappedRowLink == firstSegment + "and/keeps/going")
    }

    @Test func testImplicitUrlLookupDoesNotJoinUnrelatedRows() {
        let terminal = Terminal(delegate: self, options: TerminalOptions(cols: 92, rows: 3))
        write("https://example.com", terminal: terminal, row: 0)
        write("nextline", terminal: terminal, row: 1)

        let urlRowLink = terminal.link(at: .buffer(Position(col: 10, row: 0)), mode: .explicitAndImplicit)
        #expect(urlRowLink == "https://example.com")

        let nextRowLink = terminal.link(at: .buffer(Position(col: 2, row: 1)), mode: .explicitAndImplicit)
        #expect(nextRowLink == nil)
    }

    @Test func testImplicitBareDomainDoesNotMatch() {
        let terminal = Terminal(delegate: self, options: TerminalOptions(cols: 30, rows: 1))
        terminal.feed(text: "example.com")

        let link = terminal.link(at: .buffer(Position(col: 3, row: 0)), mode: .explicitAndImplicit)
        #expect(link == nil)
    }

    @Test func testWhitespaceReturnsNil() {
        let terminal = Terminal(delegate: self, options: TerminalOptions(cols: 10, rows: 1))
        terminal.feed(text: "a b")

        let link = terminal.link(at: .buffer(Position(col: 1, row: 0)), mode: .explicitAndImplicit)
        #expect(link == nil)
    }

    @Test func testScreenCoordinates() {
        let terminal = Terminal(delegate: self, options: TerminalOptions(cols: 32, rows: 2))
        terminal.feed(text: "https://www.example.com")

        let link = terminal.link(at: .screen(Position(col: 10, row: 0)), mode: .explicitAndImplicit)
        #expect(link == "https://www.example.com")
    }

    // MARK: - Row ranges reported for rendering

    @Test func testImplicitLinkRowRangesReportOneRangePerWrappedRow() {
        let terminal = Terminal(delegate: self, options: TerminalOptions(cols: 8, rows: 4))
        terminal.feed(text: "https://example.com/path")

        #expect(terminal.implicitLinkRowRanges(row: 0) == [.init(row: 0, range: 0..<8)])
        #expect(terminal.implicitLinkRowRanges(row: 1) == [.init(row: 1, range: 0..<8)])
        #expect(terminal.implicitLinkRowRanges(row: 2) == [.init(row: 2, range: 0..<8)])
    }

    @Test func testImplicitLinkRowRangesReportEveryLinkOnTheRow() {
        let terminal = Terminal(delegate: self, options: TerminalOptions(cols: 60, rows: 2))
        terminal.feed(text: "https://a.com https://b.com")

        let ranges = terminal.implicitLinkRowRanges(row: 0)
        #expect(ranges == [.init(row: 0, range: 0..<13), .init(row: 0, range: 14..<27)])
    }

    @Test func testImplicitLinkRowRangesAreEmptyWithoutLinks() {
        let terminal = Terminal(delegate: self, options: TerminalOptions(cols: 40, rows: 2))
        terminal.feed(text: "no links on this row")

        #expect(terminal.implicitLinkRowRanges(row: 0).isEmpty)
        #expect(terminal.implicitLinkRowRanges(row: 1).isEmpty)
        #expect(terminal.implicitLinkRowRanges(row: -1).isEmpty)
    }

    @Test func testImplicitLinkRowRangesSkipVeryLongLogicalLines() {
        let shortEnough = Terminal(delegate: self, options: TerminalOptions(cols: 200, rows: 40))
        shortEnough.feed(text: "https://example.com/" + String(repeating: "a", count: 3000))
        #expect(!shortEnough.implicitLinkRowRanges(row: 0).isEmpty)

        let tooLong = Terminal(delegate: self, options: TerminalOptions(cols: 200, rows: 40))
        tooLong.feed(text: "https://example.com/" + String(repeating: "a", count: 5000))
        #expect(tooLong.implicitLinkRowRanges(row: 0).isEmpty)
    }

    @Test func testImplicitLinkRowRangesFollowRowContents() {
        let terminal = Terminal(delegate: self, options: TerminalOptions(cols: 40, rows: 2))
        terminal.feed(text: "https://example.com")
        #expect(terminal.implicitLinkRowRanges(row: 0) == [.init(row: 0, range: 0..<19)])

        // Rewriting the row must not serve the previously cached ranges.
        terminal.feed(text: "\r\u{1b}[2Kplain text")
        #expect(terminal.implicitLinkRowRanges(row: 0).isEmpty)
    }

    @Test func testImplicitLinkRowRangesFollowContinuationIndentation() {
        let terminal = Terminal(delegate: self, options: TerminalOptions(cols: 20, rows: 3))
        terminal.feed(text: "https://example.com/abc")

        #expect(terminal.implicitLinkRowRanges(row: 0) == [.init(row: 0, range: 0..<20)])
        #expect(terminal.implicitLinkRowRanges(row: 1) == [.init(row: 1, range: 0..<3)])

        // Indenting the continuation row leaves the joined text of the logical line untouched,
        // so the cached match still applies, but the columns it covers moved.
        write("   abc", terminal: terminal, row: 1)

        #expect(terminal.implicitLinkRowRanges(row: 1) == [.init(row: 1, range: 3..<6)])
        #expect(terminal.implicitLinkRowRanges(row: 0) == [.init(row: 0, range: 0..<20)])
    }

    @Test func testImplicitLinkRowRangesFollowAReflow() {
        let terminal = Terminal(delegate: self, options: TerminalOptions(cols: 20, rows: 3))
        terminal.feed(text: "https://example.com/abcdefghij\r\n")
        _ = terminal.implicitLinkRowRanges(row: 0)
        _ = terminal.implicitLinkRowRanges(row: 1)

        // Narrowing keeps the same two rows and the same joined text, but moves the split.
        terminal.resize(cols: 18, rows: 3)

        let match = terminal.linkMatch(at: .buffer(Position(col: 0, row: 0)), mode: .explicitAndImplicit)
        #expect(match != nil)
        for row in 0..<2 {
            let expected = (match?.rowRanges ?? []).filter { $0.row == row }
            #expect(terminal.implicitLinkRowRanges(row: row) == expected)
        }
    }

    @Test func testImplicitLinkRowRangesMarkOtherRowsOfTheLineForRedraw() {
        let terminal = Terminal(delegate: self, options: TerminalOptions(cols: 8, rows: 4))
        terminal.feed(text: "https://exampleZZ")

        // Prime the ranges that the renderer has been handed for every row of the logical line.
        for row in 0..<3 {
            _ = terminal.implicitLinkRowRanges(row: row)
        }
        #expect(!terminal.implicitLinkRowRanges(row: 2).isEmpty)
        terminal.clearUpdateRange()

        // Rewriting the first row destroys the link on the continuation rows, which were not
        // touched and would otherwise keep their underlines.
        write("plain   ", terminal: terminal, row: 0)
        #expect(terminal.implicitLinkRowRanges(row: 0).isEmpty)

        let updated = terminal.getUpdateRange()
        #expect(updated?.startY == 1)
        #expect(updated?.endY == 2)

        // Drawing a row that was marked finds the same ranges again and marks nothing further.
        terminal.clearUpdateRange()
        _ = terminal.implicitLinkRowRanges(row: 1)
        #expect(terminal.getUpdateRange() == nil)
    }

#if os(macOS)
    // MARK: - View level activation and underlining

    @Test func testAlwaysIncludingImplicitAllowsClickingImplicitLinks() {
        let view = TerminalView(frame: CGRect(origin: .zero, size: .init(width: 800, height: 200)))
        view.linkHighlightMode = .alwaysIncludingImplicit
        view.terminal.feed(text: "visit https://example.com now")

        let position = Position(col: 8, row: 0)
        guard let match = view.terminal.linkMatch(at: .buffer(position), mode: .explicitAndImplicit) else {
            Issue.record("Expected an implicit link match")
            return
        }
        #expect(!match.isExplicit)
        #expect(view.linkVisibleForClick(match: match, hasCommandModifier: false))
        #expect(view.linkForClick(at: position, hasCommandModifier: false)?.link == "https://example.com")

        // Hover based modes still require the hovered range to be the matched one.
        view.linkHighlightMode = .hover
        #expect(!view.linkVisibleForClick(match: match, hasCommandModifier: false))
    }

    @Test func testLinkForClickHonorsLinkReporting() {
        let view = TerminalView(frame: CGRect(origin: .zero, size: .init(width: 800, height: 200)))
        view.linkHighlightMode = .alwaysIncludingImplicit
        view.terminal.feed(text: "visit https://example.com now")

        let position = Position(col: 8, row: 0)
        view.linkReporting = .none
        #expect(view.linkForClick(at: position, hasCommandModifier: false) == nil)

        view.linkReporting = .explicit
        #expect(view.linkForClick(at: position, hasCommandModifier: false) == nil)

        view.linkReporting = .implicit
        #expect(view.linkForClick(at: position, hasCommandModifier: false)?.link == "https://example.com")
    }

    @Test func testAlwaysIncludingImplicitUnderlinesCoveredCells() {
        let view = TerminalView(frame: CGRect(origin: .zero, size: .init(width: 800, height: 200)))
        view.linkHighlightMode = .alwaysIncludingImplicit
        view.terminal.feed(text: "visit https://example.com now")

        let ranges = view.implicitLinkRangesForUnderline(row: 0)
        #expect(ranges == [.init(row: 0, range: 6..<25)])

        let line = view.terminal.displayBuffer.lines[0]
        #expect(view.shouldUnderlineLink(row: 0, column: 8, width: 1, cell: line[8], implicitRanges: ranges))
        #expect(!view.shouldUnderlineLink(row: 0, column: 0, width: 1, cell: line[0], implicitRanges: ranges))

        // Other modes do not underline an implicit match that is not hovered.
        view.linkHighlightMode = .always
        #expect(view.implicitLinkRangesForUnderline(row: 0).isEmpty)
        #expect(!view.shouldUnderlineLink(row: 0, column: 8, width: 1, cell: line[8]))
    }

    @Test func testLinkReportingNoneDisablesUnderlining() {
        let view = TerminalView(frame: CGRect(origin: .zero, size: .init(width: 800, height: 200)))
        view.linkHighlightMode = .alwaysIncludingImplicit
        view.terminal.feed(text: "visit https://example.com now")

        let ranges = view.implicitLinkRangesForUnderline(row: 0)
        let line = view.terminal.displayBuffer.lines[0]
        #expect(view.shouldUnderlineLink(row: 0, column: 8, width: 1, cell: line[8], implicitRanges: ranges))

        view.linkReporting = .none
        #expect(view.implicitLinkRangesForUnderline(row: 0).isEmpty)
        #expect(!view.shouldUnderlineLink(row: 0, column: 8, width: 1, cell: line[8], implicitRanges: ranges))
    }

    @Test func testImplicitLinkDetectionSetterRedrawsTheView() {
        let view = TerminalView(frame: CGRect(origin: .zero, size: .init(width: 800, height: 200)))
        view.terminal.clearUpdateRange()

        view.implicitLinkDetection = Terminal.ImplicitLinkDetectionOptions(detectsLoopbackHostPorts: true)
        #expect(view.terminal.getUpdateRange() != nil)

        // Setting the same value again is not a change, and does not queue another redraw.
        view.terminal.clearUpdateRange()
        view.implicitLinkDetection = Terminal.ImplicitLinkDetectionOptions(detectsLoopbackHostPorts: true)
        #expect(view.terminal.getUpdateRange() == nil)
    }
#endif
}
