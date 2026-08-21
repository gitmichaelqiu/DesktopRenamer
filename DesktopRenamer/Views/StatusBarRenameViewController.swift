import AppKit

// View controller for the space renaming popover.
class RenameViewController: NSViewController {
    private var spaceManager: SpaceManager
    private var completion: () -> Void
    private var textField: NSTextField!

    init(spaceManager: SpaceManager, completion: @escaping () -> Void) {
        self.spaceManager = spaceManager
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 80))
        textField = NSTextField(frame: NSRect(x: 20, y: 40, width: 200, height: 24))
        textField.stringValue = spaceManager.getSpaceName(spaceManager.currentSpaceUUID)
        textField.placeholderString = NSLocalizedString("Rename.Placeholder", comment: "")
        textField.delegate = self
        view.addSubview(textField)

        let labelString = String(format: NSLocalizedString("Rename.Label", comment: ""), spaceManager.getSpaceNum(spaceManager.currentSpaceUUID))
        let label = NSTextField(labelWithString: labelString)
        label.frame = NSRect(x: 20, y: 15, width: 200, height: 17)
        label.textColor = .secondaryLabelColor
        view.addSubview(label)

        self.view = view
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(textField)
    }
}

extension RenameViewController: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            handleRename()
            return true
        } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            dismiss(nil)
            return true
        }
        return false
    }

    private func handleRename() {
        let newName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "~", with: "")
        if !newName.isEmpty {
            spaceManager.renameSpace(spaceManager.currentSpaceUUID, to: newName)
        }
        dismiss(nil)
        completion()
    }
}
