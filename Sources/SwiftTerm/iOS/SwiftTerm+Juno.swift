//
//  Created by Alex Staravoitau on 08/10/2023.
//

import Foundation

public extension TerminalView {

    /// Makes sure the UI is updated correctly after terminal manipulations in the `handler`.
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

    /// Retrieves contents of the line, starting with specified position, also appending any rows with wrapped parts of the current line.
    func getWrappedLineCharData(scrollInvariantStartingPosition start: Position) -> [CharData] {
        var data: [CharData] = []
        // Append rest of the line on the start row
        data += buffer.lines[start.row].data[start.col...]
        var row = start.row
        // Append contents of wrapped rows
        while (row + 1) < buffer.lines.count && buffer.lines[row + 1].isWrapped {
            row += 1
            data += buffer.lines[row].data
        }
        // Remove all empty cells
        data = data.filter { $0.code != 0 }
        return data
    }
    
    /// Erases cells to the end of the current line, starting with specified position, also clearing any rows with wrapped parts of the current line.
    func clearWrappedLine(scrollInvariantStartingPosition start: Position) {
        // Clear rest of the line on the start row
        eraseInBufferLine(y: start.row - buffer.yDisp, start: start.col, end: cols)
        var row = start.row
        // Clear contents of wrapped rows
        while (row + 1) < buffer.lines.count && buffer.lines[row + 1].isWrapped {
            row += 1
            eraseInBufferLine(y: row - buffer.yDisp, start: 0, end: cols)
        }
    }

    /// Retrieves cursor position counting from the beginning of buffer, not from the first visible row.
    func getScrollInvariantCursorPosition() -> Position {
        Position(col: buffer.x, row: buffer.yDisp + buffer.y)
    }
    
    /// Sets cursor position counting from the beginning of buffer, not from the first visible row.
    func setScrollInvariantCursorPosition(_ position: Position) {
        setCursor(col: position.col, row: position.row - buffer.yDisp)
    }
    
    /// Feeds byte array, making sure that the cursor is carried over to the next line, if the data happened to fill the current row to the end.
    func feedWithCursorWraparound (byteArray: [UInt8]) {
        feed(byteArray: byteArray)
        // Make sure the cursor is not on the end of the line
        if getScrollInvariantCursorPosition().col >= cols {
            feed(text: " ")
            let newCursorPosition = Position(col: 0, row: getScrollInvariantCursorPosition().row)
            clearWrappedLine(scrollInvariantStartingPosition: newCursorPosition)
            setScrollInvariantCursorPosition(newCursorPosition)
        }
    }

    /// Calculates wraparound-invariant position in buffer — that is, position as if there was no wrapping, and every line had as many columns as it needed — based on a position in buffer with wrapped lines. Both positions are scroll-invariant, i.e. counting from the beginning of buffer, not from the first visible row.
    func getWraparoundInvariantPosition(forBufferPosition position: Position) -> Position? {
        guard position.row != 0 else { return position }
        guard position.row > 0 && position.row < buffer.lines.count else { return nil }

        var currentWraparoundInvariantRow = 0
        var currentWrappedRows = 0
        var currentBufferRow = 1
        while currentBufferRow <= position.row {
            if buffer.lines[currentBufferRow].isWrapped {
                currentWrappedRows += 1
            }
            else {
                currentWraparoundInvariantRow += 1
                currentWrappedRows = 0
            }
            currentBufferRow += 1
        }
        return Position(col: position.col + currentWrappedRows * cols, row: currentWraparoundInvariantRow)
    }
    
    /// Calculates position in buffer with wrapped lines, based on a wraparound-invariant position in buffer — that is, position as if there was no wrapping, and every line had as many columns as it needed. Both positions are scroll-invariant, i.e. counting from the beginning of buffer, not from the first visible row.
    func getBufferPosition(forWraparoundInvariantPosition position: Position) -> Position? {
        var currentBufferRow = 0
        var currentWraparoundInvariantRow = 0
        while currentBufferRow < buffer.lines.count {
            if !buffer.lines[currentBufferRow].isWrapped && currentBufferRow != 0 {
                currentWraparoundInvariantRow += 1
            }
            // If we've reached the wraparound-invariant row we're looking for...
            if currentWraparoundInvariantRow == position.row {
                let additionalWrappedCols = position.col % cols
                let additionalWrappedRows = position.col / cols
                // Check if we're trying to get a position beyond available lines
                if currentBufferRow + additionalWrappedRows >= buffer.lines.count {
                    return nil
                }
                // If the line we land on isn't wrapped, but we have additional wrapped rows, it's invalid
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
