//
//  LoopbackHostPortDetectionTests.swift
//
//
//  Covers the implicit link detection options: scheme-less loopback host and
//  port pairs, and turning file system path detection off.
//

import Foundation
import Testing

@testable import SwiftTerm

final class LoopbackHostPortDetectionTests: TerminalDelegate {
    func send(source: Terminal, data: ArraySlice<UInt8>) {
    }

    private static let loopbackOptions = Terminal.ImplicitLinkDetectionOptions(detectsLoopbackHostPorts: true)

    private func makeTerminal(for input: String, options: Terminal.ImplicitLinkDetectionOptions) -> Terminal {
        let cols = max(256, input.count + 8)
        let terminal = Terminal(delegate: self, options: TerminalOptions(cols: cols, rows: 1))
        terminal.implicitLinkDetection = options
        terminal.feed(text: input)
        return terminal
    }

    private func assertMatch(input: String, expected: String, options: Terminal.ImplicitLinkDetectionOptions) {
        let terminal = makeTerminal(for: input, options: options)

        guard let expectedRange = input.range(of: expected) else {
            Issue.record("expected match not found in input: \(expected)")
            return
        }

        let expectedStart = input.distance(from: input.startIndex, to: expectedRange.lowerBound)
        let hitOffset = expectedStart + min(1, max(expected.count - 1, 0))
        let link = terminal.link(at: .buffer(Position(col: hitOffset, row: 0)), mode: .explicitAndImplicit)
        #expect(link == expected, "input: \(input)")
    }

    private func assertNoMatch(input: String, options: Terminal.ImplicitLinkDetectionOptions) {
        let terminal = makeTerminal(for: input, options: options)

        let colsToCheck = max(1, input.count)
        for col in 0..<colsToCheck {
            let link = terminal.link(at: .buffer(Position(col: col, row: 0)), mode: .explicitAndImplicit)
            #expect(link == nil, "input: \(input) at column \(col)")
        }
    }

    @Test func testLoopbackHostPortPositiveCases() {
        let cases: [(String, String)] = [
            ("localhost:8050", "localhost:8050"),
            ("localhost:8050/", "localhost:8050/"),
            ("127.0.0.1:8050", "127.0.0.1:8050"),
            ("127.0.0.1:8050/api?x=1", "127.0.0.1:8050/api?x=1"),
            ("127.1.2.3:80", "127.1.2.3:80"),
            ("0.0.0.0:8000", "0.0.0.0:8000"),
            ("[::1]:8080", "[::1]:8080"),
            ("localhost:8050.", "localhost:8050"),
            ("(localhost:8050)", "localhost:8050"),
            ("\"localhost:8050\"", "localhost:8050")
        ]

        for (input, expected) in cases {
            assertMatch(input: input, expected: expected, options: Self.loopbackOptions)
        }
    }

    @Test func testLoopbackHostPortServerBanners() {
        let cases: [(String, String)] = [
            ("Dash is running on http://127.0.0.1:8050/", "http://127.0.0.1:8050/"),
            (" * Running on http://127.0.0.1:5000", "http://127.0.0.1:5000"),
            ("INFO:     Uvicorn running on http://127.0.0.1:8000 (Press CTRL+C to quit)", "http://127.0.0.1:8000"),
            ("Serving on localhost:8000, press Ctrl+C", "localhost:8000")
        ]

        for (input, expected) in cases {
            assertMatch(input: input, expected: expected, options: Self.loopbackOptions)
        }
    }

    @Test func testLoopbackHostPortSuffixesAndPortBoundary() {
        let cases: [(String, String)] = [
            ("localhost:8080?token=abc", "localhost:8080?token=abc"),
            ("127.0.0.1:8050#top", "127.0.0.1:8050#top"),
            ("localhost:8050/x?y=1", "localhost:8050/x?y=1")
        ]

        for (input, expected) in cases {
            assertMatch(input: input, expected: expected, options: Self.loopbackOptions)
        }

        // A longer port is not a link, and must not be clipped to its first five digits.
        assertNoMatch(input: "localhost:123456", options: Self.loopbackOptions)
    }

    @Test func testLoopbackHostPortGluedSuffixesAndBrackets() {
        assertMatch(input: "see 127.0.0.1:8050/x(1) here", expected: "127.0.0.1:8050/x(1)", options: Self.loopbackOptions)
        assertMatch(input: "(localhost:8050)", expected: "localhost:8050", options: Self.loopbackOptions)
        assertMatch(input: "localhost:8050, then", expected: "localhost:8050", options: Self.loopbackOptions)
        assertNoMatch(input: "localhost:8050abc", options: Self.loopbackOptions)
        assertNoMatch(input: "localhost:8050\u{0661}", options: Self.loopbackOptions)
        assertNoMatch(input: "127.0.0.\u{0661}:8050", options: Self.loopbackOptions)
    }

    @Test func testLoopbackHostPortNoMatchCases() {
        let noMatchCases = [
            "localhost",
            "main.py:12",
            "foo.py:8",
            "error:42",
            "example.com:8080",
            "192.168.1.5:5000",
            "x.localhost:1",
            "foo@localhost:1"
        ]

        for input in noMatchCases {
            assertNoMatch(input: input, options: Self.loopbackOptions)
        }
    }

    @Test func testLoopbackHostPortIsOffByDefault() {
        let defaultOptions = Terminal.ImplicitLinkDetectionOptions()
        #expect(defaultOptions.detectsFilePaths)
        #expect(!defaultOptions.detectsLoopbackHostPorts)

        assertNoMatch(input: "localhost:8050", options: defaultOptions)
        assertMatch(input: "http://localhost:8050", expected: "http://localhost:8050", options: defaultOptions)
    }

    @Test func testFilePathDetectionCanBeDisabled() {
        let options = Terminal.ImplicitLinkDetectionOptions(detectsFilePaths: false, detectsLoopbackHostPorts: true)

        assertNoMatch(input: "/tmp/example.txt", options: options)
        assertNoMatch(input: "./foo/bar.py", options: options)

        assertMatch(input: "https://example.com", expected: "https://example.com", options: options)
        assertMatch(input: "localhost:1", expected: "localhost:1", options: options)
    }

    @Test func testChangingOptionsUpdatesDetection() {
        let terminal = Terminal(delegate: self, options: TerminalOptions(cols: 40, rows: 1))
        terminal.feed(text: "localhost:8050")

        #expect(terminal.link(at: .buffer(Position(col: 2, row: 0)), mode: .explicitAndImplicit) == nil)

        terminal.implicitLinkDetection = Self.loopbackOptions
        #expect(terminal.link(at: .buffer(Position(col: 2, row: 0)), mode: .explicitAndImplicit) == "localhost:8050")

        terminal.implicitLinkDetection = Terminal.ImplicitLinkDetectionOptions()
        #expect(terminal.link(at: .buffer(Position(col: 2, row: 0)), mode: .explicitAndImplicit) == nil)
    }
}
