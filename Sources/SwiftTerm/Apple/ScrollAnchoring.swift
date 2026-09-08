//
//  ScrollAnchoring.swift
//
//  Geometry for the "stick to the bottom while the viewport is parked there"
//  behaviour of the touch terminal view.  Kept free of UIKit so it can be
//  exercised by the test suite on any Apple platform.
//

#if os(macOS) || os(iOS) || os(visionOS)
import Foundation
import CoreGraphics

/// Pure decisions about whether a scroll view that renders terminal output should
/// follow new output, and how to keep a scrolled-back viewport still while the
/// scrollback trims lines off the top.
enum ScrollAnchoring {
    /// Tolerance, in points, for judging that a latched offset has not moved.
    private static let latchedOffsetTolerance: CGFloat = 1

    /// The content offset that parks the viewport's bottom edge at the bottom of the content.
    ///
    /// Content shorter than the (inset reduced) viewport cannot scroll at all and clamps to
    /// `-topInset`.  This is both the offset a view scrolls to in order to follow output and
    /// the offset ``isAnchoredToBottom(contentOffsetY:contentHeight:viewportHeight:topInset:bottomInset:rowHeight:)``
    /// measures against, so the test that decides to follow and the target it follows to
    /// cannot drift apart.
    ///
    /// - Parameters:
    ///   - contentHeight: Height of the whole content, including rows above the viewport.
    ///   - viewportHeight: Height of the scroll view's bounds.
    ///   - topInset: Adjusted content inset at the top.
    ///   - bottomInset: Adjusted content inset at the bottom, e.g. a software keyboard.
    /// - Returns: The bottom-most reachable vertical content offset.
    static func bottomOffsetY (contentHeight: CGFloat, viewportHeight: CGFloat, topInset: CGFloat, bottomInset: CGFloat) -> CGFloat
    {
        max (-topInset, contentHeight - viewportHeight + bottomInset)
    }

    /// Whether a follow that was latched when a touch began should resume now that the
    /// interaction has ended.
    ///
    /// Output arriving during a touch deliberately leaves the offset alone - the gesture owns
    /// it - so an offset still sitting where the latch was taken means the finger merely
    /// rested and following should continue.  Any larger movement is a real scroll, and the
    /// caller falls back to judging the geometry.
    ///
    /// - Parameters:
    ///   - latchedOffsetY: The vertical content offset recorded when the follow was latched.
    ///   - currentOffsetY: The scroll view's current vertical content offset.
    /// - Returns: `true` when the offset is within a point of where it was latched.
    static func resumesFollowing (latchedOffsetY: CGFloat, currentOffsetY: CGFloat) -> Bool
    {
        offsetIsUnmoved (latchedOffsetY: latchedOffsetY, currentOffsetY: currentOffsetY)
    }

    /// Whether an offset recorded earlier is still where it was recorded.
    ///
    /// ``resumesFollowing(latchedOffsetY:currentOffsetY:)`` is this question asked about a
    /// deferred follow. Bookkeeping that banks rows against a resting finger asks the same
    /// question about a different latch, so both go through one definition of "has not moved"
    /// and one tolerance.
    ///
    /// - Parameters:
    ///   - latchedOffsetY: The vertical content offset recorded earlier.
    ///   - currentOffsetY: The scroll view's current vertical content offset.
    /// - Returns: `true` when the offset is within a point of where it was recorded.
    static func offsetIsUnmoved (latchedOffsetY: CGFloat, currentOffsetY: CGFloat) -> Bool
    {
        abs (currentOffsetY - latchedOffsetY) <= latchedOffsetTolerance
    }

    /// Whether the viewport is parked at the bottom of the content, and so should keep
    /// following output as it arrives.
    ///
    /// The bottom is ``bottomOffsetY(contentHeight:viewportHeight:topInset:bottomInset:)``,
    /// the same offset following scrolls to; content shorter than the (inset reduced)
    /// viewport cannot scroll at all and clamps to `-topInset`, which counts as being at the
    /// bottom.  Half a row of tolerance absorbs both fractional offsets left by deceleration
    /// and a viewport that is not an exact multiple of the row height.
    ///
    /// - Parameters:
    ///   - contentOffsetY: The scroll view's current vertical content offset.
    ///   - contentHeight: Height of the whole content, including rows above the viewport.
    ///   - viewportHeight: Height of the scroll view's bounds.
    ///   - topInset: Adjusted content inset at the top.
    ///   - bottomInset: Adjusted content inset at the bottom, e.g. a software keyboard.
    ///   - rowHeight: Height of a single terminal row; drives the tolerance.
    /// - Returns: `true` when the viewport's bottom edge is within half a row of the
    ///   content's bottom, or the content is too short to scroll.
    static func isAnchoredToBottom (contentOffsetY: CGFloat, contentHeight: CGFloat, viewportHeight: CGFloat, topInset: CGFloat, bottomInset: CGFloat, rowHeight: CGFloat) -> Bool
    {
        let bottom = bottomOffsetY (contentHeight: contentHeight, viewportHeight: viewportHeight, topInset: topInset, bottomInset: bottomInset)
        let tolerance = max (0, rowHeight) / 2
        return contentOffsetY >= bottom - tolerance
    }

    /// Turns a buffer's monotonically growing `linesTop` into "rows dropped off the top
    /// since the last reading".
    ///
    /// The reading is only meaningful against the buffer it came from: switching to the
    /// alternate screen, or resetting the terminal, installs a different buffer whose
    /// `linesTop` bears no relation to the recorded one. Both that case and a `linesTop`
    /// that went backwards (clearing the scrollback resets it to zero without a
    /// notification) report no trim and re-baseline, so the count can never go negative or
    /// carry across buffers.
    struct TrimTracker {
        /// Identity of the buffer the recorded reading came from. Comparing identities
        /// rather than holding a reference keeps this a value type; a freed buffer whose
        /// address is reused by a new one fails closed, because a new buffer starts at
        /// `linesTop` zero and so reports no trim.
        private var bufferID: ObjectIdentifier?
        private var linesTop: Int = 0

        init () {}

        /// Rows dropped off the top since the previous call.
        ///
        /// - Parameters:
        ///   - bufferID: Identity of the buffer being read.
        ///   - linesTop: That buffer's current `linesTop`.
        /// - Returns: The number of rows trimmed since the last reading of the same buffer,
        ///   and zero for the first reading of a buffer or a reading that went backwards.
        mutating func consume (bufferID: ObjectIdentifier, linesTop: Int) -> Int
        {
            defer {
                self.bufferID = bufferID
                self.linesTop = linesTop
            }
            guard bufferID == self.bufferID else {
                return 0
            }
            return max (0, linesTop - self.linesTop)
        }
    }

    /// The offset that keeps the same rows on screen after the scrollback dropped
    /// `trimmedRows` lines off the top.
    ///
    /// Once the scrollback is full the line count no longer grows: every new line trims one
    /// from the top, so the content slides up underneath a viewport that is not following,
    /// and the same offset would show a row lower on each append.  Subtracting the trimmed
    /// height cancels that drift.
    ///
    /// - Parameters:
    ///   - currentOffsetY: The scroll view's current vertical content offset.
    ///   - trimmedRows: Rows dropped off the top since the last update; zero or negative
    ///     values leave the offset alone.
    ///   - rowHeight: Height of a single terminal row.
    ///   - minimumOffsetY: The topmost reachable offset, normally `-topInset`.
    /// - Returns: The compensated offset, never above `minimumOffsetY`.
    static func compensatedOffsetY (currentOffsetY: CGFloat, trimmedRows: Int, rowHeight: CGFloat, minimumOffsetY: CGFloat) -> CGFloat
    {
        guard trimmedRows > 0, rowHeight > 0 else {
            return currentOffsetY
        }
        return max (minimumOffsetY, currentOffsetY - CGFloat (trimmedRows) * rowHeight)
    }
}
#endif
