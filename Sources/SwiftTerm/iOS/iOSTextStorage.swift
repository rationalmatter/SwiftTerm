import Foundation
#if canImport(UIKit)
import UIKit

/*
    Convenience classes for the text input system.
    These are not part of the public API, but are used internally.
*/
class TextPosition: UITextPosition {
  let offset: Int
  
  init(offset: Int) {
    self.offset = offset
  }
}

extension TextPosition {
  override var description: String {
    return "\(offset)"
  }
}

class TextRange: UITextRange {
  let startPosition: TextPosition
  let endPosition: TextPosition
  
  init(from: TextPosition, to: TextPosition) {
    let start, end: TextPosition
    if from.offset < to.offset {
      start = from
      end = to
    } else {
      start = to
      end = from
    }
    self.startPosition = start
    self.endPosition = end
  }
  
  init(from: TextPosition, maxOffset: Int, in baseString: String) {
    if maxOffset >= 0 {
      self.startPosition = from
      let end = min(baseString.count, from.offset + maxOffset)
      self.endPosition = TextPosition(offset: end)
    } else {
      self.endPosition = from
      let begin = max(0, from.offset + maxOffset)
      self.startPosition = TextPosition(offset: begin)
    }
  }
  
  override var start: UITextPosition {
    return startPosition
  }
  
  override var end: UITextPosition {
    return endPosition
  }
  
  override var isEmpty: Bool {
    return startPosition.offset >= endPosition.offset
  }
  
  /// Returns this range with both offsets brought inside `baseString`.
  ///
  /// Three producers can name an offset the string cannot hold. The text input
  /// system keeps positions across edits, so a range it hands back can outlive
  /// the text it was measured against; it measures the strings we return in
  /// UTF-16 units, while the storage is indexed by `Character`; and our own
  /// insertion arithmetic assumes an insert adds as many characters as it has,
  /// which is false when the inserted text fuses with the grapheme cluster in
  /// front of it - a keystroke of Arabic harakat leaves the character count
  /// unchanged. The first two are the text input system's model and can only be
  /// clamped; the third is fixed at the producer (see `replaceInputStorage`),
  /// and this remains its backstop. Clamp before an offset is turned into a
  /// `String.Index`.
  func clamped(to baseString: String) -> TextRange {
    let limit = baseString.count
    let start = min(max(0, startPosition.offset), limit)
    let end = min(max(start, endPosition.offset), limit)
    if start == startPosition.offset && end == endPosition.offset {
      return self
    }
    return TextRange(from: TextPosition(offset: start), to: TextPosition(offset: end))
  }

  func fullRange(in baseString: String) -> Range<String.Index> {
    let inBounds = clamped(to: baseString)
    let beginIndex = baseString.index(baseString.startIndex, offsetBy: inBounds.startPosition.offset)
    let endIndex = baseString.index(beginIndex, offsetBy: inBounds.length)
    return beginIndex..<endIndex
  }

  var length: Int {
    return endPosition.offset - startPosition.offset
  }
}

extension TextRange {
  override var description: String {
    return "[\(startPosition.offset)..<\(endPosition.offset)]"
  }
}

class TextSelectionRect: UITextSelectionRect {
  let _rect: CGRect
  let _containsStart: Bool
  let _containsEnd: Bool
  
  override var writingDirection: NSWritingDirection {
    return .leftToRight
  }
  
  override var isVertical: Bool {
    return false
  }
  
  override var rect: CGRect {
    return _rect
  }
  
  override var containsStart: Bool {
    return _containsStart
  }
  
  override var containsEnd: Bool {
    return _containsEnd
  }

  init(rect: CGRect, range: TextRange, string: String) {
    _rect = rect
    _containsStart = range.startPosition.offset == 0
    _containsEnd = range.endPosition.offset == string.count
  }
}
#endif
