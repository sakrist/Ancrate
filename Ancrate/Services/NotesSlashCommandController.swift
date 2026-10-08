#if os(macOS)
import AppKit
import ApplicationServices
import SwiftUI

/// An opt-in companion to the original Notes editor. It never runs in MCP mode.
@MainActor
final class NotesSlashCommandController: ObservableObject {
    @Published private(set) var isEnabled = UserDefaults.standard.bool(forKey: "notesSlashCommandsEnabled")
    @Published private(set) var isRunning = false
    @Published private(set) var status = "Slash commands are off."
    @Published private(set) var commands: [NotesSlashCommand] = []
    @Published private(set) var selectedIndex = 0

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: Timer?
    private var workspaceObserver: NSObjectProtocol?
    private var clickMonitor: Any?
    private var panel: SlashCommandPanel?
    private var context: NotesEditorContext?
    private var dismissedToken: NotesSlashToken?
    private var swallowedKeys: Set<Int64> = []
    private var isExecuting = false
    private var generation = 0
    private static let eventMarker: Int64 = 0x414E4352415445

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "notesSlashCommandsEnabled")
        if enabled {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            startIfEnabled()
        } else {
            stop()
            status = "Slash commands are off."
        }
    }

    func startIfEnabled() {
        guard isEnabled, !AncrateMCPServer.isMCPMode, !isRunning,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        guard AXIsProcessTrusted() else {
            status = "Allow Ancrate in Accessibility, then click Check Again."
            return
        }
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, pointer in
                guard let pointer else { return Unmanaged.passUnretained(event) }
                return MainActor.assumeIsolated {
                    let controller = Unmanaged<NotesSlashCommandController>.fromOpaque(pointer).takeUnretainedValue()
                    return controller.handle(type: type, event: event)
                }
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            status = "macOS couldn't start keyboard access. Check Accessibility and restart Ancrate."
            return
        }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
        status = "Ready — type / at the start of a line in Apple Notes."
        timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.cancelPendingFormatting()
                self?.dismissedToken = nil
                self?.hide()
            }
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .scrollWheel]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.cancelPendingFormatting()
                self?.dismissedToken = self?.context?.token
                self?.hide()
            }
        }
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    private func stop() {
        generation += 1
        timer?.invalidate()
        timer = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
        workspaceObserver = nil
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        isRunning = false
        isExecuting = false
        swallowedKeys.removeAll()
        dismissedToken = nil
        hide()
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap, isRunning { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard event.getIntegerValueField(.eventSourceUserData) != Self.eventMarker else {
            return Unmanaged.passUnretained(event)
        }
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyUp, swallowedKeys.remove(key) != nil { return nil }
        if type == .keyDown, isExecuting {
            cancelPendingFormatting()
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown, !isExecuting,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.Notes",
              panel?.isVisible == true, !commands.isEmpty,
              event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty else {
            return Unmanaged.passUnretained(event)
        }
        // Keep the tap callback fast: all cross-process AX reads happen outside
        // it. Acceptance re-reads the editor before making any change.
        switch key {
        case 125: selectedIndex = (selectedIndex + 1) % commands.count
        case 126: selectedIndex = (selectedIndex + commands.count - 1) % commands.count
        case 53:
            dismissedToken = context?.token
            hide()
        case 36, 76, 48:
            let chosen = commands[selectedIndex]
            let oldToken = context?.token
            Task { @MainActor [weak self] in self?.accept(chosen, expectedToken: oldToken, fallbackKey: CGKeyCode(key)) }
        default: return Unmanaged.passUnretained(event)
        }
        swallowedKeys.insert(key)
        return nil
    }

    private func refresh() {
        guard isRunning, !isExecuting else { return }
        guard AXIsProcessTrusted() else {
            stop()
            status = "Accessibility access was removed. Grant access and click Check Again."
            return
        }
        guard let current = NotesAccessibility.focusedEditor(), let token = current.token else {
            dismissedToken = nil
            hide()
            return
        }
        guard token != dismissedToken else { hide(); return }
        let matches = NotesSlashCommand.matching(token.query)
        guard !matches.isEmpty, let bounds = current.caretBounds else { hide(); return }
        if context?.token != token || context.map({ !CFEqual($0.element, current.element) }) == true {
            selectedIndex = 0
        }
        context = current
        commands = matches
        selectedIndex = min(selectedIndex, matches.count - 1)
        show(at: bounds)
    }

    func choose(_ command: NotesSlashCommand) {
        accept(command, expectedToken: context?.token, fallbackKey: nil)
    }

    private func accept(_ chosen: NotesSlashCommand, expectedToken: NotesSlashToken?, fallbackKey: CGKeyCode?) {
        guard !isExecuting, let previous = context,
              let current = NotesAccessibility.focusedEditor(),
              current.pid == previous.pid, CFEqual(current.element, previous.element) else { hide(); return }
        guard let token = current.token else {
            hide()
            if let fallbackKey { postKey(fallbackKey, pid: current.pid) }
            return
        }
        let matches = NotesSlashCommand.matching(token.query)
        guard let command = token == expectedToken ? matches.first(where: { $0.id == chosen.id }) : matches.first else {
            // A rapidly typed unknown command must still receive its Return/Tab.
            hide()
            if let fallbackKey { postKey(fallbackKey, pid: current.pid) }
            return
        }
        guard let menu = NotesAccessibility.menuItem(for: command, pid: current.pid) else {
            fail("\(command.title) isn't available in this Notes editor. The command text was kept.")
            return
        }
        // Menu discovery can take time; reject a switched note or changed token.
        guard let verified = NotesAccessibility.focusedEditor(), verified.pid == current.pid,
              CFEqual(verified.element, current.element), verified.token == token else { hide(); return }
        guard let down = makeKey(51, down: true), let up = makeKey(51, down: false) else {
            fail("Couldn't prepare the Notes edit. The command text was kept.")
            return
        }
        var range = CFRange(location: token.range.location, length: token.range.length)
        guard let value = AXValueCreate(.cfRange, &range),
              AXUIElementSetAttributeValue(current.element, kAXSelectedTextRangeAttribute as CFString, value) == .success,
              let selected = NotesAccessibility.selectedRange(current.element),
              selected.location == range.location, selected.length == range.length,
              NotesAccessibility.isFocused(current.element, pid: current.pid) else {
            fail("Notes didn't allow selecting the command. The command text was kept.")
            return
        }
        isExecuting = true
        let executionGeneration = generation
        hide()
        // A native Delete participates in Notes' undo stack. Target the Notes
        // PID directly so an app switch cannot deliver it to another app.
        down.postToPid(current.pid)
        up.postToPid(current.pid)
        finish(command: command, menu: menu, original: current, location: range.location,
               generation: executionGeneration, attempts: 10)
    }

    private func finish(command: NotesSlashCommand, menu: AXUIElement, original: NotesEditorContext,
                        location: Int, generation: Int, attempts: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            guard let self, self.generation == generation, self.isRunning else { return }
            guard let current = NotesAccessibility.focusedEditor(), current.pid == original.pid,
                  CFEqual(current.element, original.element) else {
                self.isExecuting = false
                self.fail("Notes focus changed. Formatting was cancelled; use Undo if the command was removed.")
                return
            }
            if current.selection.location != location {
                if attempts > 1 {
                    self.finish(command: command, menu: menu, original: original, location: location,
                                generation: generation, attempts: attempts - 1)
                } else {
                    self.isExecuting = false
                    self.fail("Notes didn't confirm command removal. Formatting was cancelled.")
                }
                return
            }
            self.isExecuting = false
            guard NotesAccessibility.attribute(menu, kAXEnabledAttribute) as? Bool == true,
                  AXUIElementPerformAction(menu, kAXPressAction as CFString) == .success else {
                self.fail("Notes couldn't apply \(command.title). Use Undo to restore the command text.")
                return
            }
            self.status = "Applied \(command.title) in Apple Notes."
        }
    }

    private func makeKey(_ code: CGKeyCode, down: Bool) -> CGEvent? {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else { return nil }
        event.flags = []
        event.setIntegerValueField(.eventSourceUserData, value: Self.eventMarker)
        return event
    }

    private func cancelPendingFormatting() {
        guard isExecuting else { return }
        generation += 1
        isExecuting = false
        status = "Input changed while applying the command. Formatting was cancelled; use Undo if needed."
    }

    private func postKey(_ key: CGKeyCode, pid: pid_t) {
        makeKey(key, down: true)?.postToPid(pid)
        makeKey(key, down: false)?.postToPid(pid)
    }

    private func fail(_ message: String) {
        dismissedToken = context?.token
        hide()
        status = message
        NSSound.beep()
    }

    private func hide() {
        panel?.orderOut(nil)
        context = nil
        commands = []
    }

    private func show(at bounds: CGRect) {
        if panel == nil {
            let panel = SlashCommandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView: NotesSlashPalette(controller: self))
            self.panel = panel
        }
        guard let panel, let primary = NSScreen.screens.first else { return }
        let caret = CGRect(x: bounds.minX, y: primary.frame.maxY - bounds.maxY, width: bounds.width, height: bounds.height)
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(caret) }) ?? primary
        let visible = screen.visibleFrame
        let height = CGFloat(commands.count * 34 + 48)
        let width: CGFloat = 290
        let x = min(max(caret.minX, visible.minX + 8), visible.maxX - width - 8)
        let below = caret.minY - height - 6
        let y = below >= visible.minY + 8 ? below : min(caret.maxY + 6, visible.maxY - height - 8)
        panel.setFrame(CGRect(x: x, y: y, width: width, height: height), display: true)
        panel.orderFrontRegardless()
    }
}

private final class SlashCommandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
#endif
