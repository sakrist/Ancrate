#if os(macOS)
import AppKit
import ApplicationServices

struct NotesEditorContext {
    let pid: pid_t
    let element: AXUIElement
    let selection: CFRange
    let token: NotesSlashToken?
    let caretBounds: CGRect?
}

enum NotesAccessibility {
    static func isFocused(_ editor: AXUIElement, pid: pid_t) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return false }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.15)
        guard let focused = element(attribute(application, kAXFocusedUIElementAttribute)) else { return false }
        return CFEqual(focused, editor)
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    static func element(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func selectedRange(_ element: AXUIElement) -> CFRange? {
        guard let value = attribute(element, kAXSelectedTextRangeAttribute),
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        var range = CFRange()
        guard AXValueGetType(axValue) == .cfRange,
              AXValueGetValue(axValue, .cfRange, &range) else { return nil }
        return range
    }

    static func parameter(_ element: AXUIElement, _ name: String, range: CFRange) -> CFTypeRef? {
        var range = range
        guard let rangeValue = AXValueCreate(.cfRange, &range) else { return nil }
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, name as CFString, rangeValue, &result) == .success else { return nil }
        return result
    }

    static func focusedEditor() -> NotesEditorContext? {
        guard AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier == "com.apple.Notes" else { return nil }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.15)
        guard let editor = element(attribute(application, kAXFocusedUIElementAttribute)),
              attribute(editor, kAXRoleAttribute) as? String == kAXTextAreaRole,
              attribute(editor, kAXEnabledAttribute) as? Bool != false,
              let selection = selectedRange(editor), selection.length == 0,
              let count = attribute(editor, kAXNumberOfCharactersAttribute) as? Int,
              selection.location >= 0, selection.location <= count else { return nil }
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(editor, kAXSelectedTextRangeAttribute as CFString, &settable) == .success,
              settable.boolValue else { return nil }

        // Read only a bounded window. No database, clipboard, or note body log.
        let origin = max(0, selection.location - 128)
        let end = min(count, selection.location + 1)
        guard let text = parameter(editor, kAXStringForRangeParameterizedAttribute,
                                   range: CFRange(location: origin, length: end - origin)) as? String else { return nil }
        let token = NotesSlashToken.parse(text: text, caret: selection.location - origin, origin: origin)
        var rect = CGRect.zero
        var bounds: CGRect?
        if let value = parameter(editor, kAXBoundsForRangeParameterizedAttribute, range: selection),
           CFGetTypeID(value) == AXValueGetTypeID(),
           AXValueGetType(value as! AXValue) == .cgRect,
           AXValueGetValue(value as! AXValue, .cgRect, &rect), rect.height > 0 {
            bounds = rect
        }
        return .init(pid: app.processIdentifier, element: editor, selection: selection, token: token, caretBounds: bounds)
    }

    /// Match menu key equivalents rather than localized menu titles. If a menu
    /// action isn't exposed/enabled, leave the user's slash text untouched.
    static func menuItem(for command: NotesSlashCommand, pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        guard let menu = element(attribute(app, kAXMenuBarAttribute)) else { return nil }
        var remaining = 400
        func find(_ item: AXUIElement, depth: Int) -> AXUIElement? {
            guard depth < 7, remaining > 0 else { return nil }
            remaining -= 1
            if attribute(item, kAXRoleAttribute) as? String == kAXMenuItemRole,
               (attribute(item, kAXMenuItemCmdCharAttribute) as? String)?.lowercased() == command.menuCharacter,
               attribute(item, kAXMenuItemCmdModifiersAttribute) as? Int == command.menuModifiers,
               attribute(item, kAXEnabledAttribute) as? Bool == true {
                return item
            }
            for child in attribute(item, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
                if let match = find(child, depth: depth + 1) { return match }
            }
            return nil
        }
        return find(menu, depth: 0)
    }
}
#endif
