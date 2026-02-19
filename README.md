# NotesToDo

A lightweight SwiftUI app using SwiftData to manage notes and simple to-dos. The app stores items locally using Apple's modern SwiftData persistence and presents them with a SwiftUI interface.

## Features
- Create and manage note/to-do items
- Local persistence with SwiftData (no external backend)
- SwiftUI-first architecture

## Architecture Overview
- `NotesToDoApp` (`AncrateApp.swift`): App entry point. Sets up a shared `ModelContainer` with a `Schema` containing the `Item` model, and injects it via `.modelContainer(...)`. Also owns a `NotesDatabase` `@StateObject` for higher-level data coordination.
- `ContentView`: Root view for displaying and editing items. Receives `notesDatabase` as a dependency.
- `Item` (SwiftData model): Represents a persisted note/to-do item.
- `NotesDatabase`: A simple observable abstraction around data operations and state for the UI.

> Note: File names and types listed above reflect the current code and common conventions inferred from the project. If your structure differs, update this section accordingly.

## Requirements
- Xcode 15+ (Xcode 26.2 recommended as per current environment)
- iOS 17+ (SwiftData requires iOS 17 or later)
- Swift 5.9+

## Getting Started
1. Open the project in Xcode.
2. Build and run the `NotesToDo` target on iOS Simulator or a device running iOS 17+.
3. The app initializes a local `ModelContainer` for SwiftData storage. No additional configuration is required.

## SwiftData Configuration
The `ModelContainer` is created with a schema containing `Item` and `isStoredInMemoryOnly` set to `false`, which means data persists on device storage. If you would like ephemeral data during development/testing, you can switch this to `true`.

```swift
let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
