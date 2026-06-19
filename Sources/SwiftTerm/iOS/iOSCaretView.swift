//
//  iOSCaretView.swift
//
// Implements the caret in the iOS caret view
//
//  Created by Miguel de Icaza on 3/20/20.
//

#if os(iOS) || os(visionOS)
import Foundation
import UIKit
import CoreText
import CoreGraphics

// The CaretView is used to show the cursor
class CaretView: UIView {
    weak var terminal: TerminalView?
    var ctline: CTLine?
    var bgColor: CGColor
    var tracksFocus = true
    
    public init (frame: CGRect, cursorStyle: CursorStyle, terminal: TerminalView)
    {
        style = cursorStyle
        bgColor = caretColor.cgColor
        self.terminal = terminal
        super.init(frame: frame)
        layer.isOpaque = false
        isUserInteractionEnabled = false
        updateView()
    }
    
    @objc func foreground () {
        updateCursorStyle()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    var style: CursorStyle {
        didSet {
            updateCursorStyle ()
        }
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        if newWindow != nil {
            updateCursorStyle()
        }
    }
    
    override func didMoveToWindow() {
        if window != nil {
            NotificationCenter.default.addObserver(self, selector: #selector(foreground), name: NSNotification.Name(rawValue: UIApplication.willEnterForegroundNotification.rawValue), object: nil)
        } else {
            NotificationCenter.default.removeObserver(self,  name: NSNotification.Name(rawValue: UIApplication.willEnterForegroundNotification.rawValue), object: nil)
        }
        updateCursorStyle ();
    }
    
    func updateAnimation (to: Bool) {
        layer.removeAllAnimations()
        self.layer.opacity = 1
        if window == nil {
            return
        }
        if to {
            UIView.animate(withDuration: 0.7, delay: 0, options: [.autoreverse, .repeat, .curveEaseIn], animations: {
                self.layer.opacity = 0.0
            }, completion: { [weak self] done in
                // Attempt again, could be the window transitioning
                if done {
                    self?.updateAnimation(to: to)
                }
            })
        }
    }
    
    func setText (ch: CharData) {
        let character = terminal?.terminal.getCharacter(for: ch) ?? " "
        let res = NSAttributedString (
            string: String (character),
            attributes: terminal?.getAttributedValue(ch.attribute, usingFg: caretColor, andBg: caretTextColor ?? terminal?.nativeForegroundColor ?? TTColor.black))
        ctline = CTLineCreateWithAttributedString(res)
        setNeedsDisplay(bounds)
    }
    
    func updateCursorStyle () {
        let styleBlinks: Bool
        switch style {
        case .blinkUnderline, .blinkBlock, .blinkBar:
            styleBlinks = true
        case .steadyBar, .steadyBlock, .steadyUnderline:
            styleBlinks = false
        }
        // Only blink while focused. The draw path already shows a steady hollow
        // caret when unfocused (`hasFocus`); without gating the animation too,
        // routine `updateCursorStyle()` calls (entering the window, app
        // foregrounding, losing first-responder while still accepting input)
        // restart the blink regardless of focus — an unfocused blinking caret
        // reads as a false "active input here" cue. `tracksFocus == false` keeps
        // the previous always-blink behaviour for embedders that don't track focus.
        updateAnimation(to: styleBlinks && (tracksFocus ? hasFocus : true))
        updateView()
    }
    
    func disableAnimations() {
        layer.removeAllAnimations()
        layer.opacity = 1
    }
    
    public var defaultCaretColor = UIColor.gray
    
    public var caretColor: UIColor = UIColor.gray {
        didSet {
            bgColor = caretColor.cgColor
            updateView()
        }
    }

    public var defaultCaretTextColor: UIColor? = nil
    public var caretTextColor: UIColor? = nil {
        didSet {
            updateView()
        }
    }

    func updateView() {
        setNeedsDisplay()
    }

    var hasFocus: Bool {
        guard let terminalView = terminal else {
            return superview?.isFirstResponder ?? true
        }
        return terminalView.isInputEnabled && terminalView.isAcceptingInput && terminalView.isFirstResponder
    }

    override public func draw (_ dirtyRect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext () else {
            return
        }
        context.scaleBy (x: 1, y: -1)
        context.translateBy(x: 0, y: -frame.height)

        drawCursor(in: context, hasFocus: tracksFocus ? hasFocus : true)
    }

}
#endif
