# Apple Notes slash commands

## Research and implementation choice

Reviewed on 7 October 2026. [ProNotes](https://www.pronotes.app/) advertises slash commands for native paragraph styles, lists, quotes, tables, and reusable templates. Its public page does not explain the implementation or supply an extension SDK; this project does not claim to reproduce its internal design.

[Apple's extension guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/) describes specific host/system extension points. No Notes inline-editor extension point is documented there. The installed Notes scripting dictionary (`/System/Applications/Notes.app/Contents/Resources/Notes.sdef`) exposes note-level HTML bodies and selected notes, but no cursor-level slash hook.

The practical approach here is an opt-in macOS companion. [Apple's Accessibility model](https://developer.apple.com/library/archive/documentation/Accessibility/Conceptual/AccessibilityMacOSX/OSXAXmodel.html) supports querying focused controls and invoking menu actions. [Quartz event taps](https://developer.apple.com/documentation/coregraphics/cgevent) let the companion intercept navigation keys while its palette is visible. [Apple documents the Notes formatting shortcuts](https://support.apple.com/en-euro/guide/notes/apd46c25187e/mac), which identify the native menu actions.

## Data flow

1. Ancrate starts only after the user enables the feature and grants Accessibility permission. A menu-bar item keeps its controls available while editing Notes.
2. A 120 ms timer checks the frontmost application. Only a focused, enabled Notes text area with a writable selected range is eligible. The callback reads a bounded window around a collapsed caret, rather than the complete note or a stream of typed characters.
3. A pure parser recognizes an optionally indented slash token at the start of a logical line. URLs, inline slashes, selections, unknown commands, and a caret in the middle of a word do not produce an actionable command menu.
4. A nonactivating panel is anchored using `AXBoundsForRange`. Notes retains keyboard focus. Arrow keys select; Return/Tab accept; Escape dismisses. Mouse clicks, scrolls, and application changes dismiss the panel.
5. Acceptance re-reads focus and the token, finds an enabled native menu action by its key equivalent, and revalidates the editor after menu discovery. Ancrate selects only the token and posts Delete to the Notes PID. Once the caret confirms removal, it invokes `AXPress` on the menu action. Synthetic events carry a marker to avoid handling them again.

The macOS target uses `Ancrate-macOS.entitlements` without App Sandbox because it needs cross-application Accessibility control. [Apple explicitly lists assistive Accessibility APIs as incompatible with App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox). Hardened runtime remains enabled. Apple Events entitlements, the Automation permission check, and the AppleScript editing service have been removed. This feature does not require Full Disk Access, and does not start in MCP mode or a unit-test host.

## Review of the existing changes

MCP is now read-only, exposing only `list_notes`, `search_notes`, `get_note`, and `get_checklists`. The separate note editor and AppleScript create/update/append path were removed, eliminating their whole-body replacement risk. Native slash commands remain a separate, user-triggered Accessibility feature.

The subsequent whole-app review fixed the older-note lookup with a parameterized primary-key query and removed note titles/content from database diagnostics. Library and MCP search reads now cover the complete library before applying result limits. See [design review](design-review.md).

MCP clients cannot access the slash controller. Unsupported tool calls, including the removed write tools, return an error.

## Validation

Automated tests cover token boundaries, indentation, CRLF, invalid cursor offsets, UTF-16 offsets, truncated text windows, aliases, unknown commands, and the command catalog. Compile and run with the macOS Ancrate scheme.

The MCP regression test connects an SDK client to the actual Ancrate server through an in-memory transport. It verifies the four-tool read-only catalog and rejects create/update/append/delete requests without accessing the Notes database.

Validation on 7 October 2026: all 18 macOS unit tests passed, including the MCP integration test. The signed Debug app and embedded widget built successfully and the clean bundle passed strict signature verification. Plist validation and `git diff --check` passed. Live slash execution in Apple Notes has not been exercised; Accessibility readiness alone does not prove native formatting compatibility.

Live Notes compatibility requires the built, signed Ancrate app to have Accessibility permission. Do not infer successful integration from a build or parser tests alone. Use a disposable note for these manual checks:

- Enable the feature, grant permission, and verify Check Again starts monitoring. Disable it and verify normal Notes keyboard handling resumes. Relaunch and verify the saved preference.
- Type `/`, filter `/h1`, `/h2`, `/h3`, `/code`, `/checklist`, and each list/quote/table command. Verify the popup follows the caret and the native formatting applies.
- Verify arrow navigation, Return, Tab, mouse selection, Escape, and native Undo. Test fast typing followed immediately by Return, including an unknown command and ordinary `/code text`.
- Try the main Notes window and a separately opened note on another display and in full screen. Verify the popup is clamped to the visible display and doesn't steal focus.
- Check a locked note, a read-only shared note, Notes search, and another application. They must not receive command edits. Switch notes/apps between typing and accepting.
- Add a checklist/table/attachment elsewhere in the disposable note. Apply a slash command on a separate line and verify the other content remains intact.
- Launch `--mcp-stdio` and verify no palette, keyboard monitor, or menu-bar item starts.

## Current limits

This initial implementation covers formatting commands only. Templates, backlinks, AI actions, Markdown autoformatting, launch-at-login, and an iOS keyboard extension are separate features. It does not inject code into Notes or install a system extension.

Menu lookup relies on standard Notes key equivalents; custom remappings may make an action unavailable. Accessibility support varies across Notes versions and account types. If lookup/selection fails, the token stays intact. If focus or menu availability changes after Delete, formatting is cancelled and the user may need Undo to restore the token. Delete and formatting are separate native actions rather than an atomic transaction.
