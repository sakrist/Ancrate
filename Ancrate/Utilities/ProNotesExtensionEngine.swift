import Foundation
import AppKit
import ApplicationServices

enum AppleNotesExtensionError: LocalizedError {
    case notesNotFrontmost
    case notesNotRunning
    case accessibilityPermissionDenied
    case focusedElementUnavailable
    case selectedTextUnavailable
    case selectedTextWriteFailed
    case appleEventsFallbackFailed
    case insertionFailed

    var errorDescription: String? {
        switch self {
        case .notesNotFrontmost:
            return "Could not activate Apple Notes. Please open Notes and try again."
        case .notesNotRunning:
            return "Apple Notes is not running. Please open Notes and try again."
        case .accessibilityPermissionDenied:
            return "Accessibility permission is required to edit text in Apple Notes."
        case .focusedElementUnavailable:
            return "Could not access the focused text element in Apple Notes."
        case .selectedTextUnavailable:
            return "No selected text found in Apple Notes. Select some text in the note body and try again."
        case .selectedTextWriteFailed:
            return "Failed to replace selected text in Apple Notes."
        case .appleEventsFallbackFailed:
            return "Could not complete Apple Events fallback. Ensure Automation access to Notes is allowed."
        case .insertionFailed:
            return "Could not insert text in Apple Notes. Ensure Automation access is allowed."
        }
    }
}

struct AppleNotesCompanionBridge {
    static let notesBundleIdentifier = "com.apple.Notes"

    static func isNotesFrontmost() -> Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == notesBundleIdentifier
    }

    static func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityPermission() {
        let options: CFDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func requestAutomationPermission() -> (granted: Bool, details: String) {
        let notesProbe = "tell application \"Notes\" to get name"
        let systemEventsProbe = "tell application \"System Events\" to get name of first process"

        let notesResult = runAppleScriptDetailed(notesProbe)
        let systemEventsResult = runAppleScriptDetailed(systemEventsProbe)

        let granted = notesResult.success && systemEventsResult.success
        if granted {
            return (true, "Automation is enabled for Notes and System Events.")
        }

        let notesMessage = notesResult.errorMessage ?? "unknown"
        let systemEventsMessage = systemEventsResult.errorMessage ?? "unknown"
        let details = "Notes: \(notesMessage) | System Events: \(systemEventsMessage)"
        return (false, details)
    }

    static func transformSelectedTextInNotes(using transform: (String) -> String) throws -> String {
        activateNotesIfNeeded()

        guard isAccessibilityTrusted() else {
            throw AppleNotesExtensionError.accessibilityPermissionDenied
        }

        guard let notesApp = NSRunningApplication.runningApplications(withBundleIdentifier: notesBundleIdentifier).first else {
            throw AppleNotesExtensionError.notesNotRunning
        }

        do {
            let notesAXElement = AXUIElementCreateApplication(notesApp.processIdentifier)
            guard let focused = resolveEditableElement(in: notesAXElement) else {
                throw AppleNotesExtensionError.focusedElementUnavailable
            }

            guard let selectedText = readSelectedTextWithRetry(from: focused), !selectedText.isEmpty else {
                throw AppleNotesExtensionError.selectedTextUnavailable
            }

            let transformed = transform(selectedText)

            guard replaceSelectedTextWithFallback(on: focused, replacement: transformed) else {
                throw AppleNotesExtensionError.selectedTextWriteFailed
            }

            return transformed
        } catch {
            if let transformed = transformUsingAppleEventsFallback(transform) {
                return transformed
            }
            throw AppleNotesExtensionError.appleEventsFallbackFailed
        }
    }

    static func insertTextInNotesAtCursor(_ text: String, replacingTypedSlash: Bool = false) throws {
        activateNotesIfNeeded()

        let pasteboard = NSPasteboard.general
        let originalClipboard = pasteboard.string(forType: .string)
        setClipboard(text)

        let script: String
        if replacingTypedSlash {
            script = """
            tell application "Notes" to activate
            delay 0.02
            tell application "System Events"
                key code 51
                keystroke "v" using command down
            end tell
            """
        } else {
            script = """
            tell application "Notes" to activate
            delay 0.02
            tell application "System Events"
                keystroke "v" using command down
            end tell
            """
        }

        let success = runAppleScript(script)
        restoreClipboard(originalClipboard)

        guard success else {
            throw AppleNotesExtensionError.insertionFailed
        }
    }

    private static func transformUsingAppleEventsFallback(_ transform: (String) -> String) -> String? {
        let pasteboard = NSPasteboard.general
        let marker = "ANCRATE_COPY_MARKER_\(UUID().uuidString)"
        let originalClipboard = pasteboard.string(forType: .string)

        setClipboard(marker)

        let copyScript = """
        tell application \"Notes\" to activate
        delay 0.05
        tell application \"System Events\"
            keystroke \"c\" using command down
        end tell
        """

        guard runAppleScript(copyScript) else {
            restoreClipboard(originalClipboard)
            return nil
        }

        Thread.sleep(forTimeInterval: 0.1)

        guard let selected = pasteboard.string(forType: .string), !selected.isEmpty, selected != marker else {
            restoreClipboard(originalClipboard)
            return nil
        }

        let transformed = transform(selected)
        setClipboard(transformed)

        let pasteScript = """
        tell application \"Notes\" to activate
        delay 0.02
        tell application \"System Events\"
            keystroke \"v\" using command down
        end tell
        """

        guard runAppleScript(pasteScript) else {
            restoreClipboard(originalClipboard)
            return nil
        }

        Thread.sleep(forTimeInterval: 0.08)
        restoreClipboard(originalClipboard)

        return transformed
    }

    private static func runAppleScript(_ source: String) -> Bool {
        guard let script = NSAppleScript(source: source) else {
            return false
        }

        var error: NSDictionary?
        _ = script.executeAndReturnError(&error)
        return error == nil
    }

    private static func runAppleScriptDetailed(_ source: String) -> (success: Bool, errorMessage: String?) {
        guard let script = NSAppleScript(source: source) else {
            return (false, "Cannot initialize NSAppleScript")
        }

        var error: NSDictionary?
        _ = script.executeAndReturnError(&error)

        guard let error else {
            return (true, nil)
        }

        let number = error[NSAppleScript.errorNumber] as? Int ?? 0
        let message = (error[NSAppleScript.errorMessage] as? String) ?? "Unknown AppleScript error"
        return (false, "\(number) \(message)")
    }

    private static func setClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private static func restoreClipboard(_ original: String?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let original {
            pasteboard.setString(original, forType: .string)
        }
    }

    private static func readSelectedTextWithRetry(from element: AXUIElement) -> String? {
        for _ in 0..<5 {
            if let selected = readSelectedText(from: element), !selected.isEmpty {
                return selected
            }
            Thread.sleep(forTimeInterval: 0.06)
        }
        return nil
    }

    private static func readSelectedText(from element: AXUIElement) -> String? {
        var selectedTextRef: CFTypeRef?
        let selectedTextResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedTextRef)
        if selectedTextResult == .success, let selectedText = selectedTextRef as? String, !selectedText.isEmpty {
            return selectedText
        }

        guard let selectedRange = copyRangeAttribute(element, attribute: kAXSelectedTextRangeAttribute),
              selectedRange.length > 0,
              let fullValue = copyStringAttribute(element, attribute: kAXValueAttribute),
              let selectedSlice = substring(fullValue, in: selectedRange),
              !selectedSlice.isEmpty else {
            return nil
        }

        return selectedSlice
    }

    private static func replaceSelectedTextWithFallback(on element: AXUIElement, replacement: String) -> Bool {
        let directSetResult = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, replacement as CFTypeRef)
        if directSetResult == .success {
            return true
        }

        guard let selectedRange = copyRangeAttribute(element, attribute: kAXSelectedTextRangeAttribute),
              selectedRange.length > 0,
              let fullValue = copyStringAttribute(element, attribute: kAXValueAttribute),
              let updated = replacingSubstring(in: fullValue, range: selectedRange, with: replacement) else {
            return false
        }

        let valueSetResult = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, updated as CFTypeRef)
        guard valueSetResult == .success else {
            return false
        }

        let newRange = CFRange(location: selectedRange.location + replacement.utf16.count, length: 0)
        var mutableRange = newRange
        if let rangeAXValue = AXValueCreate(.cfRange, &mutableRange) {
            _ = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, rangeAXValue)
        }

        return true
    }

    private static func substring(_ source: String, in range: CFRange) -> String? {
        let utf16 = source.utf16
        guard range.location >= 0,
              range.length >= 0,
              range.location + range.length <= utf16.count else {
            return nil
        }

        let start = String.Index(utf16Offset: range.location, in: source)
        let end = String.Index(utf16Offset: range.location + range.length, in: source)
        return String(source[start..<end])
    }

    private static func replacingSubstring(in source: String, range: CFRange, with replacement: String) -> String? {
        let utf16 = source.utf16
        guard range.location >= 0,
              range.length >= 0,
              range.location + range.length <= utf16.count else {
            return nil
        }

        let start = String.Index(utf16Offset: range.location, in: source)
        let end = String.Index(utf16Offset: range.location + range.length, in: source)

        var updated = source
        updated.replaceSubrange(start..<end, with: replacement)
        return updated
    }

    private static func resolveEditableElement(in notesAXElement: AXUIElement) -> AXUIElement? {
        if let focusedElement = copyElementAttribute(notesAXElement, attribute: kAXFocusedUIElementAttribute),
           let editable = findEditableElement(startingAt: focusedElement, depth: 0) {
            return editable
        }

        if let focusedWindow = copyElementAttribute(notesAXElement, attribute: kAXFocusedWindowAttribute),
           let editable = findEditableElement(startingAt: focusedWindow, depth: 0) {
            return editable
        }

        if let windows = copyElementArrayAttribute(notesAXElement, attribute: kAXWindowsAttribute) {
            for window in windows {
                if let editable = findEditableElement(startingAt: window, depth: 0) {
                    return editable
                }
            }
        }

        return nil
    }

    private static func findEditableElement(startingAt element: AXUIElement, depth: Int) -> AXUIElement? {
        if isEditableTextElement(element) {
            return element
        }

        guard depth < 6 else { return nil }
        guard let children = copyElementArrayAttribute(element, attribute: kAXChildrenAttribute), !children.isEmpty else {
            return nil
        }

        for child in children {
            if let editable = findEditableElement(startingAt: child, depth: depth + 1) {
                return editable
            }
        }

        return nil
    }

    private static func isEditableTextElement(_ element: AXUIElement) -> Bool {
        if let role = copyStringAttribute(element, attribute: kAXRoleAttribute),
           role == (kAXTextAreaRole as String) || role == (kAXTextFieldRole as String) {
            return true
        }

        var isSettable: DarwinBoolean = false
        let settableResult = AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &isSettable)
        return settableResult == .success && isSettable.boolValue
    }

    private static func copyElementAttribute(_ element: AXUIElement, attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let value else {
            return nil
        }

        guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }

        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private static func copyElementArrayAttribute(_ element: AXUIElement, attribute: String) -> [AXUIElement]? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let rawArray = value as? [Any] else {
            return nil
        }

        return rawArray.compactMap { item in
            let cfItem = item as CFTypeRef
            guard CFGetTypeID(cfItem) == AXUIElementGetTypeID() else {
                return nil
            }
            return unsafeBitCast(cfItem, to: AXUIElement.self)
        }
    }

    private static func copyStringAttribute(_ element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else {
            return nil
        }
        return value as? String
    }

    private static func copyRangeAttribute(_ element: AXUIElement, attribute: String) -> CFRange? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let value else {
            return nil
        }

        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else {
            return nil
        }

        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(axValue, .cfRange, &range) else {
            return nil
        }

        return range
    }

    private static func activateNotesIfNeeded() {
        if isNotesFrontmost() {
            return
        }

        if let notesApp = NSRunningApplication.runningApplications(withBundleIdentifier: notesBundleIdentifier).first {
            notesApp.activate(options: [])
        } else {
            NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: "/System/Applications/Notes.app"),
                configuration: NSWorkspace.OpenConfiguration()
            )
        }

        for _ in 0..<10 {
            if isNotesFrontmost() {
                return
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
    }
}

struct ProNotesExtensionEngine {
    static let supportedSlashCommands: [String: String] = [
        "title": "# ",
        "h1": "# ",
        "heading": "## ",
        "h2": "## ",
        "subheading": "### ",
        "h3": "### ",
        "body": "",
        "checklist": "- [ ] ",
        "bulletedlist": "* ",
        "dashedlist": "- ",
        "numberedlist": "1. ",
        "quote": "> ",
        "blockquote": "> "
    ]

    static let templates: [String: String] = [
        "Meeting Notes": "## Meeting Notes\n\n- Date: \n- Attendees: \n- Agenda: \n\n### Decisions\n- \n\n### Action Items\n- [ ] ",
        "Daily Journal": "# Daily Journal\n\n## Wins\n- \n\n## Challenges\n- \n\n## Tomorrow\n- [ ] ",
        "Project Update": "# Project Update\n\n## Status\n\n## Risks\n\n## Next Steps\n- [ ] "
    ]

    static func applySlashCommands(to input: String) -> String {
        let lines = input.components(separatedBy: .newlines)

        let transformedLines = lines.map { line in
            transformSlashCommandLine(line)
        }

        return transformedLines.joined(separator: "\n")
    }

    static func normalizeMarkdownShortcuts(in input: String) -> String {
        let lines = input.components(separatedBy: .newlines)

        let normalized = lines.map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("[] ") {
                let content = String(trimmed.dropFirst(3))
                return "- [ ] \(content)"
            }

            if trimmed == "[]" {
                return "- [ ] "
            }

            return line
        }

        return normalized.joined(separator: "\n")
    }

    static func runAllTransforms(on input: String) -> String {
        let slash = applySlashCommands(to: input)
        return normalizeMarkdownShortcuts(in: slash)
    }

    static func backlinks(for target: ANote, in notes: [ANote]) -> [ANote] {
        let escapedTitle = NSRegularExpression.escapedPattern(for: target.title)
        let pattern = "\\[\\[\\s*\(escapedTitle)\\s*\\]\\]"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        return notes.filter { note in
            guard note.id != target.id else { return false }
            let searchText = note.content as NSString
            let range = NSRange(location: 0, length: searchText.length)
            return regex.firstMatch(in: note.content, options: [], range: range) != nil
        }
    }

    private static func transformSlashCommandLine(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("/") else { return line }

        let commandAndRest = trimmed.dropFirst().split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let commandPart = commandAndRest.first else { return line }

        let command = String(commandPart).lowercased()
        let remainder = commandAndRest.count > 1 ? String(commandAndRest[1]) : ""

        if command == "code" || command == "monostyled" {
            if remainder.isEmpty {
                return "```\n\n```"
            }
            return "```\n\(remainder)\n```"
        }

        if command == "table" {
            return "| Column 1 | Column 2 |\n| --- | --- |\n| Value | Value |"
        }

        if command == "template" {
            return templateFromCommand(remainder) ?? line
        }

        guard let prefix = supportedSlashCommands[command] else { return line }
        return "\(prefix)\(remainder)"
    }

    private static func templateFromCommand(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        switch normalized {
        case "meeting", "meeting notes":
            return templates["Meeting Notes"]
        case "daily", "journal", "daily journal":
            return templates["Daily Journal"]
        case "project", "project update":
            return templates["Project Update"]
        default:
            return nil
        }
    }
}
