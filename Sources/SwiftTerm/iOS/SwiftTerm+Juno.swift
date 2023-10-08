//
//  Created by Alex Staravoitau on 08/10/2023.
//

import Foundation

public extension TerminalView {
    func dispatchTerminalUpdates(_ handler: (Terminal) -> Void) {
        feedPrepare()
        handler(getTerminal())
        feedFinish()
    }

    func resetToInitialState() {
        resetCmd(nil)
        updateScroller()
    }
}

public extension Terminal {
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
        // Trim trailing empty cells
        while let last = data.last, last.code == 0 {
            data.removeLast()
        }
        return data
    }

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

    func getScrollInvariantCursorPosition() -> Position {
        Position(col: buffer.x, row: buffer.yDisp + buffer.y)
    }

    func setScrollInvariantCursorPosition(_ position: Position) {
        setCursor(col: position.col, row: position.row - buffer.yDisp)
    }

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
}
