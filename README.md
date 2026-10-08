# Ancrate

A lightweight macOS SwiftUI companion for Apple Notes. Ancrate reads the local Apple Notes store for fast search and checklist extraction, and exposes read-only access through a local MCP server.

## Features
- Read Apple Notes locally, including checklist extraction and Markdown export
- Run as a read-only local MCP server for desktop LLM clients
- Native sidebar, searchable notes reader, and grouped read-only to-do boards
- All to-dos, Past month, and Past 3 months views with Open / All / Completed filters
- Small, medium, and large desktop widgets with configurable time ranges
- System colors, standard typography, native lists and grouped settings, plus a custom macOS icon
- Opt-in slash command palette inside the original Apple Notes editor on macOS
- Menu-bar access with the Dock icon hidden by default and an optional Show in Dock setting

## Architecture Overview
- `AncrateApp.swift`: Starts the normal SwiftUI UI, or the MCP stdio server when launched with `--mcp-stdio`.
- `NotesDatabase`: Reads Apple’s local Notes store and provides fresh note snapshots to the UI and MCP layer.
- `AncrateMCPServer`: Exposes four read-only tools and dispatches calls to an isolated `NotesMCPService` actor.
- `NotesSlashCommandController`: Keeps a nonactivating palette beside the Notes cursor, handles menu navigation, and invokes native Notes formatting through Accessibility.

## Requirements
- macOS 14+
- Xcode 16+
- Full Disk Access for Ancrate, so it can read the Apple Notes store
- Accessibility permission for slash commands (independent of Full Disk Access)

## Slash commands in the original Apple Notes app

1. Run Ancrate and open **Settings → Slash commands in Apple Notes**, or use the Ancrate menu-bar icon.
2. Enable slash commands and allow Ancrate in System Settings → Privacy & Security → Accessibility.
3. Return to Ancrate and click **Check Again** if the monitor hasn't started.
4. Keep Ancrate running. In Apple Notes, type `/` at the beginning of a line, then type to filter commands.
5. Choose with ↑/↓ and apply with Return or Tab, or click a command. Escape dismisses the menu and keeps the typed text.

Supported commands: `/title` (`/h1`), `/heading` (`/h2`), `/subheading` (`/h3`), `/body`, `/monostyled` (`/code`), `/checklist`, `/bulletedlist`, `/dashedlist`, `/numberedlist`, `/quote` (`/blockquote`), and `/table`.

This is a macOS companion app using public Accessibility and Quartz APIs. Apple's published extension points do not provide a Notes inline-editor plugin. The macOS target therefore uses separate, **unsandboxed** entitlements and retains hardened runtime; its intended distribution is a signed/notarized desktop app. Other platform entitlements are unchanged.

Slash commands read at most 129 UTF-16 units around the cursor, select only the slash token, remove it with a native Delete, and press an enabled Notes menu action. They do not read or write the private Notes database, replace the whole note, or use the clipboard. They are disabled by default and never start in `--mcp-stdio` mode.

Compatibility depends on Notes exposing its editor and menu actions through Accessibility. Menu actions are located by their standard key equivalents, avoiding localized menu titles. Remapped shortcuts, unsupported accounts, locked/read-only notes, or OS changes can prevent a command from applying. Native Delete and formatting may require separate Undo actions. See [implementation and manual checks](docs/apple-notes-slash-commands.md).

## Getting Started
1. Open the project in Xcode.
2. Build and run the `Ancrate` macOS target.
3. Grant Ancrate Full Disk Access in System Settings → Privacy & Security → Full Disk Access.
4. Browse notes and extract or export checklists. Enable slash commands separately if you want formatting shortcuts inside Apple Notes.

Ancrate starts without a Dock icon. Use its menu-bar icon → **Open Ancrate** to bring back the window. Enable **Settings → Application → Show in Dock** to show the Dock icon; the choice applies immediately and is saved for future launches. Closing the window keeps the menu-bar app running; choose **Quit Ancrate** to stop it.

## MCP setup

Ancrate’s executable includes a local stdio MCP server. Add the following server entry to an MCP host that supports local stdio servers, adjusting the application path if needed:

**Settings → MCP setup → Copy configuration** generates this JSON using the running app's actual executable location. Paste it into your client's MCP configuration; if an `mcpServers` object already exists, merge the `ancrate` entry into it. Copy it again after moving Ancrate. Each client starts a separate read-only server process, so the normal app does not need to stay open and does not automatically start MCP.

```json
{
  "mcpServers": {
    "ancrate": {
      "command": "/Applications/Ancrate.app/Contents/MacOS/Ancrate",
      "args": ["--mcp-stdio"]
    }
  }
}
```

The available tools are `list_notes`, `search_notes`, `get_note`, and `get_checklists`. All four are advertised as read-only. MCP clients cannot create, edit, append to, or delete notes; requests for unsupported tools are rejected.

MCP stdio mode is intended for local hosts such as desktop assistants and coding tools. ChatGPT web cannot connect directly to a process on your Mac; it requires a remote MCP endpoint or a supported secure tunnel. The embedded server is transport-compatible at the protocol level, but this app does not publish your notes to the internet.

## Permissions and safety

Ancrate's search and MCP features read Apple’s private Notes SQLite store and therefore require Full Disk Access. Database connections use `SQLITE_OPEN_READONLY`. Ancrate has no separate note editor or AppleScript write path and does not request Automation permission.

Optional slash commands are user-triggered formatting actions inside the original Notes editor, using Accessibility. They never run in MCP mode and cannot be invoked by MCP clients.

## Recent to-dos

**Past month** and **Past 3 months** use rolling calendar-month cutoffs and include all checklist items from notes within that range. The default is the note's last-edited date; switch to creation date in Settings. Apple Notes does not expose a date for each individual checklist item in the parsed data, so editing an old note can bring its existing items into a recent view.

Search and status filters apply within the selected range. Click a row to select it for copying; completion is always changed in Apple Notes. The sidebar counts open items. The app refreshes its read-only library every minute while running, or with ⌘R.

## Choose to-do sources

Right-click a note in **All notes**, a source-note heading, or any to-do row, then choose **Exclude from to-dos**. The note stays in the library with an exclusion label. Restore it using **Include in to-dos** or **Settings → To-do sources → Excluded notes**.

In **Settings → To-do sources**, choose **All folders** (the default) or **Selected folders**, then check the folders you want. With no folders selected, no to-dos appear. Note exclusions take precedence over folder selection. Folder selection uses local folder IDs, so renaming a folder preserves the selection and same-named folders remain separate. Folder rows show a sample note to help identify duplicates.

These preferences affect every to-do range, counts, copying/exporting from the boards, and the shared widget snapshot. Changes are saved locally and request a widget refresh immediately; WidgetKit controls when the widget redraws. Apple Notes and read-only MCP results are unchanged. Sample-mode choices are kept separately in memory and do not alter your saved library preferences.

## Desktop widget

Build and run the **Ancrate** macOS scheme with signing enabled. It embeds the **AncrateWidgets** extension; both targets share the `group.com.sakrist.Ancrate` App Group. Xcode must provision this group for the configured development team.

1. Open Ancrate and connect its Notes library.
2. Right-click the desktop → **Edit Widgets** → **Ancrate**.
3. Add a small, medium, or large **Ancrate To-dos** widget.
4. Edit the widget to choose Past month, Past 3 months, or All to-dos.

The sandboxed widget reads a local checklist snapshot, rather than opening Apple's Notes database. Ancrate publishes fresh snapshots every minute while running and requests a widget reload. WidgetKit decides the actual display schedule; the widget's 15-minute timeline request re-evaluates date boundaries and cannot fetch new Notes content while Ancrate is closed. Clicking the widget opens the corresponding Ancrate list.

Turn off **Show my to-dos in the Ancrate widget** in Settings to replace the stored snapshot with an empty disabled snapshot. Sample notes are for visual exploration and are never published to widgets or MCP clients.

## Development and validation

Use **Explore with sample notes** in onboarding or Settings to review the interface with fictional data. `--demo` also starts directly in sample mode without reading the Notes store or publishing widget data. Reconnect from Settings to return to your library.

The macOS tests cover slash parsing, actual MCP read-only tool dispatch, calendar ranges, widget snapshots, Unicode checklists and Markdown export, and a synthetic SQLite library larger than the old fetch cap. See [design and app review](docs/design-review.md) for validation details and [slash integration checks](docs/apple-notes-slash-commands.md) for native Notes compatibility.
