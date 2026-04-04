//
//  Created by Alex Staravoitau on 08/10/2023.
//

#if os(iOS) || os(visionOS)
import Foundation

public extension TerminalView {

    /// Wraps terminal mutations in the correct `feedPrepare` / `feedFinish` bookkeeping
    /// so the UI refreshes properly afterward.
    func dispatchTerminalUpdates(_ handler: (Terminal) -> Void) {
        feedPrepare()
        handler(getTerminal())
        feedFinish()
    }

    func resetToInitialState() {
        resetCmd(nil)
        updateScroller()
    }

    func getText() -> String {
        let start = Position(col: 0, row: 0)
        let end = Position(col: terminal.cols - 1, row: terminal.buffer.lines.maxLength - 1)
        return terminal.getText(start: start, end: end)
    }
}

public extension Terminal {

    /// Retrieves contents of the line starting at the given scroll-invariant position,
    /// including any wrapped continuation rows.
    func getWrappedLineCharData(scrollInvariantStartingPosition start: Position) -> [CharData] {
        var data: [CharData] = []
        data += buffer.lines[start.row].data[start.col...]
        var row = start.row
        while (row + 1) < buffer.lines.count && buffer.lines[row + 1].isWrapped {
            row += 1
            data += buffer.lines[row].data
        }
        data = data.filter { $0.code != 0 }
        return data
    }

    /// Erases cells to the end of the current line starting at the given scroll-invariant
    /// position, including any wrapped continuation rows.
    func clearWrappedLine(scrollInvariantStartingPosition start: Position) {
        eraseInBufferLine(y: start.row - buffer.yDisp, start: start.col, end: cols)
        var row = start.row
        while (row + 1) < buffer.lines.count && buffer.lines[row + 1].isWrapped {
            row += 1
            eraseInBufferLine(y: row - buffer.yDisp, start: 0, end: cols)
        }
    }

    /// Cursor position counted from the beginning of the buffer (scroll-invariant).
    func getScrollInvariantCursorPosition() -> Position {
        Position(col: buffer.x, row: buffer.yDisp + buffer.y)
    }

    /// Sets the cursor position counted from the beginning of the buffer (scroll-invariant).
    func setScrollInvariantCursorPosition(_ position: Position) {
        setCursor(col: position.col, row: position.row - buffer.yDisp)
    }

    /// Feeds a byte array and ensures the cursor wraps to the next line if it lands at the
    /// end of the current row.
    func feedWithCursorWraparound(byteArray: [UInt8]) {
        feed(byteArray: byteArray)
        if getScrollInvariantCursorPosition().col >= cols {
            feed(text: " ")
            let newCursorPosition = Position(col: 0, row: getScrollInvariantCursorPosition().row)
            clearWrappedLine(scrollInvariantStartingPosition: newCursorPosition)
            setScrollInvariantCursorPosition(newCursorPosition)
        }
    }

    /// Converts a buffer position (with wrapped rows) to a wraparound-invariant position
    /// — as if every line had unlimited columns.
    /// Both positions are scroll-invariant (counted from the buffer start).
    func getWraparoundInvariantPosition(forBufferPosition position: Position) -> Position? {
        guard position.row != 0 else { return position }
        guard position.row > 0 && position.row < buffer.lines.count else { return nil }

        var currentWraparoundInvariantRow = 0
        var currentWrappedRows = 0
        var currentBufferRow = 1
        while currentBufferRow <= position.row {
            if buffer.lines[currentBufferRow].isWrapped {
                currentWrappedRows += 1
            } else {
                currentWraparoundInvariantRow += 1
                currentWrappedRows = 0
            }
            currentBufferRow += 1
        }
        return Position(col: position.col + currentWrappedRows * cols, row: currentWraparoundInvariantRow)
    }

    /// Converts a wraparound-invariant position back to a buffer position with wrapped rows.
    /// Both positions are scroll-invariant (counted from the buffer start).
    func getBufferPosition(forWraparoundInvariantPosition position: Position) -> Position? {
        var currentBufferRow = 0
        var currentWraparoundInvariantRow = 0
        while currentBufferRow < buffer.lines.count {
            if !buffer.lines[currentBufferRow].isWrapped && currentBufferRow != 0 {
                currentWraparoundInvariantRow += 1
            }
            if currentWraparoundInvariantRow == position.row {
                let additionalWrappedCols = position.col % cols
                let additionalWrappedRows = position.col / cols
                if currentBufferRow + additionalWrappedRows >= buffer.lines.count {
                    return nil
                }
                if !buffer.lines[currentBufferRow + additionalWrappedRows].isWrapped && additionalWrappedRows > 0 {
                    return nil
                }
                return Position(col: additionalWrappedCols, row: currentBufferRow + additionalWrappedRows)
            }
            currentBufferRow += 1
        }
        return nil
    }
}
#endif
