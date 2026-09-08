//
//  ScrollAnchoringTests.swift
//
//  Covers the pure geometry behind "follow output only while parked at the bottom".
//

import Foundation
import Testing

@testable import SwiftTerm

#if os(macOS) || os(iOS) || os(visionOS)
import CoreGraphics

final class ScrollAnchoringTests {
    private let rowHeight: CGFloat = 20
    private let viewportHeight: CGFloat = 500
    private let contentHeight: CGFloat = 2000

    private func isAnchored (offsetY: CGFloat, contentHeight: CGFloat? = nil, viewportHeight: CGFloat? = nil, topInset: CGFloat = 0, bottomInset: CGFloat = 0, rowHeight: CGFloat? = nil) -> Bool {
        ScrollAnchoring.isAnchoredToBottom (
            contentOffsetY: offsetY,
            contentHeight: contentHeight ?? self.contentHeight,
            viewportHeight: viewportHeight ?? self.viewportHeight,
            topInset: topInset,
            bottomInset: bottomInset,
            rowHeight: rowHeight ?? self.rowHeight)
    }

    private func bottomOffset (contentHeight: CGFloat? = nil, viewportHeight: CGFloat? = nil, topInset: CGFloat = 0, bottomInset: CGFloat = 0) -> CGFloat {
        ScrollAnchoring.bottomOffsetY (
            contentHeight: contentHeight ?? self.contentHeight,
            viewportHeight: viewportHeight ?? self.viewportHeight,
            topInset: topInset,
            bottomInset: bottomInset)
    }

    @Test func bottomOffsetOfScrollableContent () {
        #expect(bottomOffset () == contentHeight - viewportHeight)
    }

    @Test func bottomOffsetOfShortContentClampsToTheTopInset () {
        #expect(bottomOffset (contentHeight: 100) == 0)
        #expect(bottomOffset (contentHeight: 100, topInset: 40) == -40)
        // Exactly as tall as the viewport is still not scrollable.
        #expect(bottomOffset (contentHeight: viewportHeight, topInset: 40) == 0)
    }

    @Test func bottomOffsetIncludesTheBottomInset () {
        #expect(bottomOffset (bottomInset: 300) == contentHeight - viewportHeight + 300)
    }

    @Test func anchoringAgreesWithTheBottomOffsetAtTheBoundary () {
        // The follow target and the test that decides to follow must not drift apart: the
        // bottom offset is anchored, and so is everything within half a row above it.
        let cases: [(contentHeight: CGFloat, topInset: CGFloat, bottomInset: CGFloat)] = [
            (contentHeight, 0, 0),
            (contentHeight, 40, 0),
            (contentHeight, 0, 300),
            (contentHeight, 40, 300),
            (100, 40, 0),
        ]
        for testCase in cases {
            let bottom = bottomOffset (contentHeight: testCase.contentHeight, topInset: testCase.topInset, bottomInset: testCase.bottomInset)
            #expect(isAnchored (offsetY: bottom, contentHeight: testCase.contentHeight, topInset: testCase.topInset, bottomInset: testCase.bottomInset))
            #expect(isAnchored (offsetY: bottom - rowHeight / 2, contentHeight: testCase.contentHeight, topInset: testCase.topInset, bottomInset: testCase.bottomInset))
            #expect(!isAnchored (offsetY: bottom - rowHeight, contentHeight: testCase.contentHeight, topInset: testCase.topInset, bottomInset: testCase.bottomInset))
        }
    }

    @Test func followingResumesWhenTheOffsetDidNotMove () {
        #expect(ScrollAnchoring.resumesFollowing (latchedOffsetY: 1500, currentOffsetY: 1500))
    }

    @Test func followingResumesAfterSubPointDrift () {
        #expect(ScrollAnchoring.resumesFollowing (latchedOffsetY: 1500, currentOffsetY: 1500.25))
        #expect(ScrollAnchoring.resumesFollowing (latchedOffsetY: 1500, currentOffsetY: 1499.5))
    }

    /// The banked-trim bookkeeping asks "has this offset moved?" about a different latch than
    /// the deferred follow does; both must answer with the same tolerance.
    @Test func unmovedAgreesWithResumingAFollow () {
        for currentOffsetY: CGFloat in [1500, 1500.25, 1499.5, 1500 - rowHeight, 1500 + rowHeight] {
            #expect(ScrollAnchoring.offsetIsUnmoved (latchedOffsetY: 1500, currentOffsetY: currentOffsetY)
                    == ScrollAnchoring.resumesFollowing (latchedOffsetY: 1500, currentOffsetY: currentOffsetY))
        }
    }

    @Test func followingDoesNotResumeAfterARowOfMovement () {
        #expect(!ScrollAnchoring.resumesFollowing (latchedOffsetY: 1500, currentOffsetY: 1500 - rowHeight))
        #expect(!ScrollAnchoring.resumesFollowing (latchedOffsetY: 1500, currentOffsetY: 1500 + rowHeight))
    }

    @Test func anchoredExactlyAtTheBottom () {
        #expect(isAnchored (offsetY: contentHeight - viewportHeight))
    }

    @Test func anchoredWithinHalfARow () {
        let bottom = contentHeight - viewportHeight
        #expect(isAnchored (offsetY: bottom - rowHeight / 2))
        #expect(isAnchored (offsetY: bottom - rowHeight / 4))
    }

    @Test func notAnchoredOneRowAbove () {
        #expect(!isAnchored (offsetY: contentHeight - viewportHeight - rowHeight))
    }

    @Test func notAnchoredWhenScrolledWellBack () {
        #expect(!isAnchored (offsetY: 0))
    }

    @Test func anchoredWhenContentIsShorterThanTheViewport () {
        #expect(isAnchored (offsetY: 0, contentHeight: 100))
    }

    @Test func bottomInsetShiftsTheAnchorPoint () {
        // A software keyboard raises the bottom inset, which pushes the bottom-most
        // reachable offset down by the same amount.
        let bottomInset: CGFloat = 300
        let bottom = contentHeight - viewportHeight + bottomInset
        #expect(isAnchored (offsetY: bottom, bottomInset: bottomInset))
        #expect(!isAnchored (offsetY: contentHeight - viewportHeight, bottomInset: bottomInset))
    }

    @Test func topInsetOnlyMovesTheShortContentAnchor () {
        let topInset: CGFloat = 40
        // Short content clamps to -topInset, and that counts as being at the bottom.
        #expect(isAnchored (offsetY: -topInset, contentHeight: 100, topInset: topInset))
        // Scrollable content still anchors at the same place as with no top inset.
        #expect(isAnchored (offsetY: contentHeight - viewportHeight, topInset: topInset))
        #expect(!isAnchored (offsetY: contentHeight - viewportHeight - rowHeight, topInset: topInset))
    }

    @Test func overscrollPastTheBottomCountsAsAnchored () {
        #expect(isAnchored (offsetY: contentHeight - viewportHeight + 60))
    }

    @Test func zeroRowHeightDoesNotDivideByZero () {
        let bottom = contentHeight - viewportHeight
        #expect(isAnchored (offsetY: bottom, rowHeight: 0))
        #expect(!isAnchored (offsetY: bottom - 1, rowHeight: 0))
    }

    @Test func compensatesForASingleTrimmedRow () {
        let result = ScrollAnchoring.compensatedOffsetY (
            currentOffsetY: 400, trimmedRows: 1, rowHeight: rowHeight, minimumOffsetY: 0)
        #expect(result == 380)
    }

    @Test func compensatesForSeveralTrimmedRows () {
        let result = ScrollAnchoring.compensatedOffsetY (
            currentOffsetY: 400, trimmedRows: 3, rowHeight: rowHeight, minimumOffsetY: 0)
        #expect(result == 340)
    }

    @Test func compensationClampsAtTheMinimumOffset () {
        let result = ScrollAnchoring.compensatedOffsetY (
            currentOffsetY: 10, trimmedRows: 5, rowHeight: rowHeight, minimumOffsetY: -40)
        #expect(result == -40)
    }

    @Test func noTrimLeavesTheOffsetAlone () {
        let result = ScrollAnchoring.compensatedOffsetY (
            currentOffsetY: 400, trimmedRows: 0, rowHeight: rowHeight, minimumOffsetY: 0)
        #expect(result == 400)
    }

    @Test func compensationWithZeroRowHeightLeavesTheOffsetAlone () {
        let result = ScrollAnchoring.compensatedOffsetY (
            currentOffsetY: 400, trimmedRows: 3, rowHeight: 0, minimumOffsetY: 0)
        #expect(result == 400)
    }

    // MARK: - Tolerance boundary

    /// A row height that is not a whole number of points is the normal case for a scaled
    /// font, so the half-row tolerance has to hold exactly there too.
    @Test func toleranceBoundaryWithAFractionalRowHeight () {
        let fractionalRowHeight: CGFloat = 13.5
        let bottom = bottomOffset ()
        #expect(isAnchored (offsetY: bottom, rowHeight: fractionalRowHeight))
        #expect(isAnchored (offsetY: bottom - fractionalRowHeight / 2, rowHeight: fractionalRowHeight))
        #expect(!isAnchored (offsetY: bottom - fractionalRowHeight / 2 - 1, rowHeight: fractionalRowHeight))
    }

    // MARK: - Trim tracking

    private final class BufferStandIn {}

    @Test func trimTrackerReportsNothingForTheFirstReading () {
        var tracker = ScrollAnchoring.TrimTracker ()
        let buffer = BufferStandIn ()
        #expect(tracker.consume (bufferID: ObjectIdentifier (buffer), linesTop: 7) == 0)
    }

    @Test func trimTrackerReportsTheAdvanceSinceTheLastReading () {
        var tracker = ScrollAnchoring.TrimTracker ()
        let buffer = ObjectIdentifier (BufferStandIn ())
        #expect(tracker.consume (bufferID: buffer, linesTop: 0) == 0)
        #expect(tracker.consume (bufferID: buffer, linesTop: 1) == 1)
        #expect(tracker.consume (bufferID: buffer, linesTop: 4) == 3)
        #expect(tracker.consume (bufferID: buffer, linesTop: 4) == 0)
    }

    @Test func trimTrackerReportsNothingAcrossADifferentBuffer () {
        var tracker = ScrollAnchoring.TrimTracker ()
        let first = BufferStandIn ()
        let second = BufferStandIn ()
        #expect(tracker.consume (bufferID: ObjectIdentifier (first), linesTop: 0) == 0)
        #expect(tracker.consume (bufferID: ObjectIdentifier (first), linesTop: 5) == 5)
        // The alternate screen: a different buffer, whose linesTop means something else.
        #expect(tracker.consume (bufferID: ObjectIdentifier (second), linesTop: 0) == 0)
        // Back to the first buffer: its reading is a first reading again, then advances.
        #expect(tracker.consume (bufferID: ObjectIdentifier (first), linesTop: 5) == 0)
        #expect(tracker.consume (bufferID: ObjectIdentifier (first), linesTop: 6) == 1)
    }

    @Test func trimTrackerReportsNothingWhenLinesTopGoesBackwards () {
        var tracker = ScrollAnchoring.TrimTracker ()
        let buffer = ObjectIdentifier (BufferStandIn ())
        #expect(tracker.consume (bufferID: buffer, linesTop: 9) == 0)
        // Clearing the scrollback resets linesTop without a notification.
        #expect(tracker.consume (bufferID: buffer, linesTop: 0) == 0)
        #expect(tracker.consume (bufferID: buffer, linesTop: 2) == 2)
    }
}
#endif
