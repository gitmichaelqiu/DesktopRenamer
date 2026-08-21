import AppKit
import SwiftUI
class FocusTextField: NSTextField {
    var onCommandEnter: (() -> Void)?
    var onOptionEnter: (() -> Void)?
    var onCommandNumber: ((Int) -> Void)?
    var onCommandK: (() -> Void)?
    var onKeyEquivalent: ((NSEvent) -> Bool)?
    var isTypingDisabled: Bool = false
    var focusNotificationName = NSNotification.Name("FocusLauncherTextField")

    override var acceptsFirstResponder: Bool {
        return true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let handled = onKeyEquivalent?(event), handled {
            return true
        }
        
        if event.type == .keyDown {
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let hasCommand = modifiers.contains(.command)
            let hasOption = modifiers.contains(.option)
            let hasOtherModifiers = !modifiers.subtracting([.command, .option, .numericPad, .function]).isEmpty
            
            if !hasOtherModifiers {
                if (hasCommand || hasOption) && (event.keyCode == 36 || event.keyCode == 76) {
                    if hasCommand {
                        onCommandEnter?()
                    } else if hasOption {
                        onOptionEnter?()
                    }
                    return true
                }
                
                if hasCommand {
                    if let chars = event.charactersIgnoringModifiers,
                       chars.count == 1,
                       let char = chars.first,
                       let number = Int(String(char)),
                       number >= 1 && number <= 9 {
                        onCommandNumber?(number)
                        return true
                    }
                    
                    if event.charactersIgnoringModifiers?.lowercased() == "k" {
                        onCommandK?()
                        return true
                    }
                }
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            NotificationCenter.default.addObserver(self, selector: #selector(windowDidBecomeKey), name: NSWindow.didBecomeKeyNotification, object: window)
            NotificationCenter.default.addObserver(self, selector: #selector(forceFocus), name: focusNotificationName, object: nil)
            if window?.isKeyWindow == true {
                DispatchQueue.main.async { [weak self] in
                    self?.forceFocus()
                }
            }
        } else {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)
            NotificationCenter.default.removeObserver(self, name: focusNotificationName, object: nil)
        }
    }
    
    @objc private func windowDidBecomeKey() {
        DispatchQueue.main.async { [weak self] in
            self?.forceFocus()
        }
    }
    
    @objc private func forceFocus() {
        guard let window = self.window else { return }
        window.makeFirstResponder(self)
        self.currentEditor()?.selectAll(nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

class BlockTypingFormatter: Formatter {
    var isTypingDisabled: () -> Bool
    
    init(isTypingDisabled: @escaping () -> Bool) {
        self.isTypingDisabled = isTypingDisabled
        super.init()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func string(for obj: Any?) -> String? {
        return obj as? String
    }
    
    override func getObjectValue(_ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?, for string: String, errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        obj?.pointee = string as AnyObject
        return true
    }
    
    override func isPartialStringValid(_ partialString: String, newEditingString newString: AutoreleasingUnsafeMutablePointer<NSString?>?, errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        if isTypingDisabled() {
            return false
        }
        return true
    }
}

struct SearchTextField: NSViewRepresentable {
    @Binding var text: String
    var isDark: Bool
    var isTypingDisabled: Bool = false
    var onUpArrow: () -> Void
    var onDownArrow: () -> Void
    var onLeftArrow: (() -> Bool)? = nil
    var onRightArrow: (() -> Bool)? = nil
    var onEnter: () -> Void
    var onCommandEnter: (() -> Void)? = nil
    var onOptionEnter: (() -> Void)? = nil
    var onCommandNumber: ((Int) -> Void)? = nil
    var onTab: (() -> Void)? = nil
    var onEscape: () -> Void
    var onCommandK: (() -> Void)? = nil
    var onKeyEquivalent: ((NSEvent) -> Bool)? = nil
    var placeholder: String = "Type a command..."
    var textFieldFont: NSFont = NSFont.systemFont(ofSize: 16, weight: .regular)
    var textFieldColor: NSColor = .labelColor
    var placeholderColor: NSColor = .placeholderTextColor
    var focusNotificationName = NSNotification.Name("FocusLauncherTextField")
    
    class Coordinator: NSObject, NSTextFieldDelegate, NSTextViewDelegate {
        var parent: SearchTextField
        var lastPlaceholder: String? = nil
        var lastIsDark: Bool? = nil
        
        init(_ parent: SearchTextField) {
            self.parent = parent
        }
        
        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }
        
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            if parent.isTypingDisabled {
                return false
            }
            return true
        }
        
        func textView(_ textView: NSTextView, shouldChangeTextInRanges affectedRanges: [NSValue], replacementStrings: [String]?) -> Bool {
            if parent.isTypingDisabled {
                return false
            }
            return true
        }
        
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                parent.onUpArrow()
                return true
            } else if commandSelector == #selector(NSResponder.moveDown(_:)) {
                parent.onDownArrow()
                return true
            } else if commandSelector == #selector(NSResponder.moveLeft(_:)) {
                if parent.onLeftArrow?() == true {
                    return true
                }
            } else if commandSelector == #selector(NSResponder.moveRight(_:)) {
                if parent.onRightArrow?() == true {
                    return true
                }
            } else if commandSelector == #selector(NSResponder.insertTab(_:)) || commandSelector == #selector(NSResponder.insertBacktab(_:)) {
                parent.onTab?()
                return true
            } else if commandSelector == #selector(NSResponder.insertNewline(_:)) || commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) {
                let isCommandPressed = NSEvent.modifierFlags.contains(.command)
                let isOptionPressed = NSEvent.modifierFlags.contains(.option)
                if isCommandPressed, let onCommandEnter = parent.onCommandEnter {
                    onCommandEnter()
                } else if isOptionPressed, let onOptionEnter = parent.onOptionEnter {
                    onOptionEnter()
                } else {
                    parent.onEnter()
                }
                return true
            } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onEscape()
                return true
            }
            return false
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> NSTextField {
        let textField = FocusTextField()
        textField.delegate = context.coordinator
        textField.focusNotificationName = focusNotificationName
        
        let formatter = BlockTypingFormatter(isTypingDisabled: { [weak coordinator = context.coordinator] in
            coordinator?.parent.isTypingDisabled ?? false
        })
        textField.formatter = formatter
        
        // Route closures safely and dynamically through the coordinator
        textField.onCommandEnter = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onCommandEnter?()
        }
        textField.onOptionEnter = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onOptionEnter?()
        }
        textField.onCommandNumber = { [weak coordinator = context.coordinator] num in
            coordinator?.parent.onCommandNumber?(num)
        }
        textField.onCommandK = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onCommandK?()
        }
        textField.onKeyEquivalent = onKeyEquivalent
        textField.isTypingDisabled = isTypingDisabled
        
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.textColor = textFieldColor
        textField.font = textFieldFont
        
        context.coordinator.lastPlaceholder = placeholder
        context.coordinator.lastIsDark = isDark
        
        let placeholderAttr = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: placeholderColor,
                .font: textFieldFont
            ]
        )
        textField.placeholderAttributedString = placeholderAttr
        
        textField.stringValue = text
        return textField
    }
    
    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        
        if let focusField = nsView as? FocusTextField {
            focusField.isTypingDisabled = isTypingDisabled
            focusField.onKeyEquivalent = onKeyEquivalent
        }
        
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.font = textFieldFont
        nsView.textColor = textFieldColor
        
        // Cache placeholder creation to avoid recreating it on every render cycle
        if context.coordinator.lastPlaceholder != placeholder || context.coordinator.lastIsDark != isDark {
            context.coordinator.lastPlaceholder = placeholder
            context.coordinator.lastIsDark = isDark
            
            let placeholderAttr = NSAttributedString(
                string: placeholder,
                attributes: [
                    .foregroundColor: placeholderColor,
                    .font: textFieldFont
                ]
            )
            nsView.placeholderAttributedString = placeholderAttr
        }
    }
}


