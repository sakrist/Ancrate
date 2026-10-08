# Ancrate design and app review

Reviewed 7 October 2026. Scope: the macOS app, Notes reader/model, Markdown export, MCP, native slash companion, permissions, assets, and a new WidgetKit extension. Existing changes were retained; no commit, publication, or notarization was performed.

## Interface

The two-tab interface has become a native sidebar with All notes, All to-dos, Past month, Past 3 months, and Settings. The current design uses semantic macOS window/text backgrounds, the system accent color, standard system typography, native inset lists, and a grouped Settings form. The earlier custom ivory/green palette, serif headings, large cards, and widget gradient were removed at the user’s request. Controls retain native keyboard and accessibility behavior. No decorative animation was added.

The to-do board opens with unfinished work, summarizes open/completed/source counts in a compact row, and groups native list rows under their source notes. Notes and to-do search use the native toolbar search control. Search, completion filters, copying, and Markdown export are available within each date range. Completion circles display Apple Notes' state; selecting a row selects it for copying. The notes browser has a searchable list and a separate text reader with folder/date context and Markdown copying.

Settings brings the date basis, desktop widget, permission controls, and optional slash commands together. Onboarding can show fictional sample notes without granting access. Sample mode does not replace or write Apple Notes, does not serve fictional data through MCP, and does not publish it to the desktop widget.

Ancrate is a menu-bar app by default, with `LSUIElement` preventing an initial Dock icon. Settings → Application → Show in Dock switches the activation policy immediately and persists the choice. Open Ancrate in the menu-bar menu restores an existing window or opens the library when none is available. MCP mode retains its prohibited activation policy.

Settings → MCP setup now displays selectable JSON generated from the running app's actual executable location, with a Copy configuration button and copy confirmation. It explains merging the entry into an existing client configuration, recopying after moving the app, and the independent read-only stdio process. The normal app still does not start an MCP server automatically.

The generated icon stays in the asset catalog; its brand color does not override interface colors. The app has no forced color scheme or custom global accent, so system appearance and accent choices drive the UI. The desktop widget uses semantic background/primary/secondary styles.

## Review fixes

- Removed the UI's 100-note ceiling and the 500-note search ceiling. MCP result sizes remain bounded to 1–100.
- Fixed older-note retrieval with a bound SQLite primary-key query, preserving read-only connections.
- Removed the fallback query that assigned invented current dates to notes, which would make recent ranges misleading.
- Closed database and prepared-statement resources on failures and now report SQLite iteration errors.
- Removed note titles, content previews, and raw byte dumps from database diagnostics.
- Cached parsed checklists in each note snapshot, used UTF-16 ranges for Apple's attributes, validated malformed lengths, and namespaced row IDs by note.
- Fixed Unicode Markdown export and preserved trailing text without formatting attributes. Malformed ranges fall back to readable plain text instead of dropping content.
- Removed the unused SwiftData container initialization from app startup.
- Isolated test-host startup from live Notes reads, permission checking, and widget publication.
- Kept MCP read-only and separate from native, opt-in slash formatting. Removed the standalone note editor and AppleScript Automation path.

## Recent ranges and widgets

Past month and Past 3 months are inclusive rolling calendar-month windows. Last edited is the default; creation date is selectable. Both are note dates: the parsed store has no reliable individual checklist timestamps. Editing an old note can bring every checklist in that note into a recent list.

A real macOS WidgetKit extension supports small, medium, and large desktop widgets. An App Intent selects a time range; clicking opens the matching Ancrate board using an `ancrate://tasks/…` URL. The widget runs sandboxed and reads an atomically saved App Group snapshot of checklist text, state, source metadata, and dates. It never reads the Notes database and exposes no completion/edit action. Disabling sharing writes an empty disabled snapshot, including while exploring sample notes.

Ancrate refreshes/publishes while running. WidgetKit schedules actual rendering. Closing Ancrate leaves the last snapshot available; the widget timeline can update date boundaries but cannot obtain new Notes changes. App Group provisioning/signing is required. Implementation follows Apple's [widget extension](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension), [timeline provider](https://developer.apple.com/documentation/widgetkit/timelineprovider), and [App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups) guidance.

## Validation

- 18 macOS unit tests passed: calendar boundaries/date basis, snapshot round-trip and clearing, Unicode checklist order and stable IDs, malformed ranges, Unicode Markdown export/trailing content, a synthetic 600-note database and older-ID lookup, slash parsing, and actual MCP tool dispatch/rejection of writes. Five source-selection regressions additionally cover exclusions across ranges and widget snapshots, combined folder/note filters, folder identity and renaming, persisted preferences/restoration, and disabled snapshots.
- Signed macOS Debug app plus embedded widget built with the project's existing development team. A clean product bundle passed `codesign --verify --deep --strict`.
- Plists validated and `git diff --check` passed. The subsequent native-appearance update also passed the signed app/widget build and strict signature verification; no new appearance-only unit tests were added.
- Native UI inspected using fictional notes: month versus three-month lists, completed filter, notes list/reader, and Settings. A wrapping filter label was corrected after inspection. Source controls were also exercised with sample data: right-click exclusion, updated sidebar/board counts, the excluded-note library label, context-menu restoration, empty folder selection, and selecting a single folder.
- The current native appearance was inspected with sample data: standard-color list and grouped Settings screenshots, toolbar search filtering, row selection for copying, and folder controls. A redundant Form separator was removed. System dark mode/custom accent preferences were not changed for validation.
- The Dock update passed a signed app/widget build and strict signature verification. Native Settings showed Show in Dock off on launch and successfully toggled on and off. Direct Dock inspection timed out, so Dock visibility and reopening through the menu-bar item still need a manual visual check.
- On 8 October, the MCP setup update passed the full macOS unit suite, including three executable-path cases with spaces, Unicode, quotes, and backslashes. The signed app/widget build and strict signature verification passed. Native Settings displayed the actual executable path without truncation, and Copy configuration returned a successful clipboard-write confirmation. No external MCP client configuration was changed.
- Desktop widget placement/live refresh, deep-link activation from an installed widget, and native slash formatting still require a manual end-to-end check. No Notes content was edited for validation. iOS/visionOS builds and notarized distribution were not validated.

## Remaining limitations

The reader depends on Apple's private SQLite/protobuf format; future Notes versions can change it. Locked notes and rich attachments/tables may not be fully readable or faithfully exported. The notes reader displays extracted text; rich rendering remains future work. Slash commands rely on the Notes accessibility tree and standard menu shortcuts; see the separate integration checklist.

`Item.swift` and `ProtobufDebugView.swift` remain unused developer scaffolding and are not part of the main interface. The app's Notes reader is inherently macOS-specific; the existing multi-platform target declarations should not be taken as complete iOS support.

## To-do source controls

Added after the initial design review: context menus on notes, source headings, and to-do rows exclude the entire source note. All notes remains a complete library, with visible exclusion labels and a restore action. Settings has All folders / Selected folders, explicit empty-selection behavior, per-folder checkboxes, and restoration for excluded notes. A Sources action on each to-do board leads to these settings.

The same `ToDoScope` predicate filters board input, counts, and the actual widget snapshot factory. Exclusions win over selected folders, and changes trigger immediate snapshot publication/reload requests. Preferences persist in app-local UserDefaults using note/folder IDs; sample exploration uses a separate in-memory scope. The Notes query now returns folder primary keys, preserving selections through renames and separating folders with matching names. No Apple Notes writes or MCP behavior changes were introduced.

## Icon asset

Generated with the built-in image-generation tool. The original generated image was preserved; deterministic macOS size variants were produced for the asset catalog.

- Runtime mark: `Ancrate/Assets.xcassets/AncrateIcon.imageset/ancrate.png`
- Icon set: `Ancrate/Assets.xcassets/AppIcon.appiconset/ancrate-{16,32,64,128,256,512,1024}.png`
- Original: `/Users/sakrist/.codex/generated_images/01a115bf-63f4-7281-8188-d4e5bf8d618f/exec-398af03c-0178-42fe-a8a2-542507a08118.png`

Prompt:

> Use case: logo-brand. Asset type: final macOS application icon for Ancrate, a calm Apple Notes companion that surfaces checklists. Create a single polished square 1024x1024 macOS app icon on a truly transparent canvas: a softly rounded square tile occupying about 86% of the canvas, warm ivory paper face, subtle tactile thickness and restrained soft shadow. Center a distinctive deep forest green abstract A formed by a folded paper ribbon that subtly becomes a checkmark, with two short muted green checklist lines beneath it. The silhouette should be simple, bold, immediately recognizable at 32 pixels, modern and crafted. Clean front view, soft studio light, extremely restrained dimensionality, crisp geometric edges, generous interior whitespace. No lettering, no wordmark, no watermark, no extra symbols, no background outside the rounded tile, no device mockup. This is the actual app-icon asset, not a presentation of icons.
