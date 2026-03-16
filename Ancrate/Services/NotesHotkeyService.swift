import Foundation
import AppKit

final class NotesHotkeyService: NSObject, ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var lastStatus = "Hotkeys are disabled."

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private weak var slashMenu: NSMenu?

    func start() {
        guard globalMonitor == nil, localMonitor == nil else { return }

        guard AppleNotesCompanionBridge.isAccessibilityTrusted() else {
            isEnabled = false
            lastStatus = "Hotkeys need Accessibility permission to work globally."
            return
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event: event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event: event)
            return event
        }

        isEnabled = true
        lastStatus = "Hotkeys enabled: Cmd+Opt+Return (Run All), Cmd+Opt+/ (Slash)."
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }

        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }

        isEnabled = false
        lastStatus = "Hotkeys are disabled."
    }

    func toggle() {
        isEnabled ? stop() : start()
    }

    deinit {
        stop()
    }

    private func handle(event: NSEvent) {
        if isPlainSlashTrigger(event), AppleNotesCompanionBridge.isNotesFrontmost() {
            DispatchQueue.main.async { [weak self] in
                self?.showSlashSuggestionMenu()
            }
            return
        }

        guard hasRequiredModifiers(event.modifierFlags) else { return }

        if isReturn(event) {
            runAction(name: "Run All") { text in
                ProNotesExtensionEngine.runAllTransforms(on: text)
            }
            return
        }

        if isSlash(event) {
            runAction(name: "Slash") { text in
                ProNotesExtensionEngine.applySlashCommands(to: text)
            }
        }
    }

    private func hasRequiredModifiers(_ flags: NSEvent.ModifierFlags) -> Bool {
        let filtered = flags.intersection(.deviceIndependentFlagsMask)
        return filtered.contains([.command, .option])
    }

    private func isPlainSlashTrigger(_ event: NSEvent) -> Bool {
        let filtered = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let disallowed: NSEvent.ModifierFlags = [.command, .option, .control, .function]
        guard filtered.intersection(disallowed).isEmpty else { return false }
        return event.charactersIgnoringModifiers == "/"
    }

    private func isReturn(_ event: NSEvent) -> Bool {
        event.keyCode == 36 || event.charactersIgnoringModifiers == "\r"
    }

    private func isSlash(_ event: NSEvent) -> Bool {
        event.charactersIgnoringModifiers == "/"
    }

    private func runAction(name: String, transform: @escaping (String) -> String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                _ = try AppleNotesCompanionBridge.transformSelectedTextInNotes(using: transform)
                DispatchQueue.main.async {
                    self?.lastStatus = "\(name) succeeded in Apple Notes."
                }
            } catch {
                DispatchQueue.main.async {
                    self?.lastStatus = "\(name) failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func showSlashSuggestionMenu() {
        if let slashMenu {
            slashMenu.cancelTracking()
        }

        // A menu cannot reliably open when this app is fully inactive.
        NSApp.activate(ignoringOtherApps: true)

        let menu = NSMenu(title: "Slash Suggestions")

        addMenuItem(menu: menu, title: "/title", snippet: "# ")
        addMenuItem(menu: menu, title: "/heading", snippet: "## ")
        addMenuItem(menu: menu, title: "/subheading", snippet: "### ")
        menu.addItem(.separator())
        addMenuItem(menu: menu, title: "/checklist", snippet: "- [ ] ")
        addMenuItem(menu: menu, title: "/bulletedlist", snippet: "* ")
        addMenuItem(menu: menu, title: "/dashedlist", snippet: "- ")
        addMenuItem(menu: menu, title: "/numberedlist", snippet: "1. ")
        menu.addItem(.separator())
        addMenuItem(menu: menu, title: "/quote", snippet: "> ")
        addMenuItem(menu: menu, title: "/code", snippet: "```\n\n```")
        addMenuItem(menu: menu, title: "/table", snippet: "| Column 1 | Column 2 |\n| --- | --- |\n| Value | Value |")

        slashMenu = menu
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        lastStatus = "Slash suggestions shown. Pick an item to insert into Notes."
    }

    private func addMenuItem(menu: NSMenu, title: String, snippet: String) {
        let item = NSMenuItem(title: title, action: #selector(insertSlashSuggestion(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = snippet
        menu.addItem(item)
    }

    @objc private func insertSlashSuggestion(_ sender: NSMenuItem) {
        guard let snippet = sender.representedObject as? String else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try AppleNotesCompanionBridge.insertTextInNotesAtCursor(snippet, replacingTypedSlash: true)
                DispatchQueue.main.async {
                    self?.lastStatus = "Inserted \(sender.title) in Apple Notes."
                }
            } catch {
                DispatchQueue.main.async {
                    self?.lastStatus = "Insert failed: \(error.localizedDescription)"
                }
            }
        }
    }
}
