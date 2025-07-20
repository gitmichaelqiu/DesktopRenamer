import SwiftUI
import Combine

class StatusBarController {
    private var statusItem: NSStatusItem
    private var popover: NSPopover
    @ObservedObject private var spaceManager: DesktopSpaceManager
    
    init(spaceManager: DesktopSpaceManager) {
        self.spaceManager = spaceManager
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        
        setupMenuBar()
    }
    
    private func setupMenuBar() {
        if let button = statusItem.button {
            button.title = spaceManager.getSpaceName(spaceManager.currentSpaceId)
        }
        
        spaceManager.$currentSpaceId.sink { [weak self] newId in
            if let button = self?.statusItem.button {
                button.title = self?.spaceManager.getSpaceName(newId) ?? "Desktop \(newId)"
            }
        }.store(in: &cancellables)
        
        setupMenu()
    }
    
    private func setupMenu() {
        let menu = NSMenu()
        
        // Add rename option for current space
        let renameItem = NSMenuItem(title: "Rename Current Space", action: #selector(renameCurrentSpace), keyEquivalent: "r")
        renameItem.target = self
        menu.addItem(renameItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Add quit option
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    @objc private func renameCurrentSpace() {
        let alert = NSAlert()
        alert.messageText = "Rename Space"
        alert.informativeText = "Enter a new name for Desktop \(spaceManager.currentSpaceId):"
        
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        input.stringValue = spaceManager.getSpaceName(spaceManager.currentSpaceId)
        alert.accessoryView = input
        
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        
        input.becomeFirstResponder()
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let newName = input.stringValue
            spaceManager.renameSpace(spaceManager.currentSpaceId, to: newName)
        }
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    private var cancellables = Set<AnyCancellable>()
}

struct StatusBarView: View {
    @StateObject private var spaceManager = DesktopSpaceManager()
    @State private var statusBarController: StatusBarController?
    
    var body: some View {
        EmptyView()
            .onAppear {
                statusBarController = StatusBarController(spaceManager: spaceManager)
            }
    }
} 
