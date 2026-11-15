# Apple shared application API

All Apple source files compile the core and session source files directly into each target. Do not unconditionally `import CourtCore` or `CourtSession` in Apple files.

`@MainActor final class MatchStore: ObservableObject` exposes `static let shared`.

Published state:
- `activeDocument: MatchDocument?`, `snapshot: MatchSnapshot?`
- `documents: [MatchDocument]` (newest first), `history: [MatchDocument]` (same)
- `preferences: AppPreferences` (mutable; bindings supported)
- `isPaused: Bool`, `connectionStatus: String`, `lastError: String?`
- `activeReminder: MatchReminder?`

Methods:
```swift
func start(configuration: MatchConfiguration) throws
func score(_ side: Side)
func undo()
func chooseReceiver(_ court: ServiceCourt)
func changeLineup(_ lineup: SetLineup)
func togglePause()
func endMatch() // end early; preserves history, labels as ended early
func resume(_ document: MatchDocument)
func repeatScore()
func speakPreview(_ text: String)
func dismissReminder()
func clearError()
func exportData() throws -> Data
func importData(_ data: Data) throws
```

`AppPreferences` is Codable/Equatable and has mutable Bool fields:
`speechEnabled = true`, `voiceCommandsEnabled = false`,
`changeoverRemindersEnabled = true`, `hydrationRemindersEnabled = true`,
`serveRemindersEnabled = true`, `includeNamesInSpeech = true`.

`MatchReminder: Identifiable, Equatable` has `id: UUID`, `title: String`,
`message: String`, `restUntil: Date?`. Views can use `TimelineView` for countdown.

`MatchDocument: Codable, Identifiable, Equatable` has `id: UUID`,
`configuration: MatchConfiguration`, `createdAt: Date`, `updatedAt: Date`,
`snapshot: MatchSnapshot` (computed), `isAbandoned: Bool`, `isPaused: Bool`.

The store uses a persisted event log. Undo targets the last active point record,
and devices exchange unique records rather than overwriting each other's score.
Preferences are local to the device, including speech and Siri command opt-in.
The iPhone and Watch can both always score manually, subject only to match
pause/completion and No-Ad receiver selection. Import merges records by ID.

Siri commands are App Intents for home/away point, undo, repeat, and either
receiver-court selection. They are
disabled unless `voiceCommandsEnabled` is on. No continuous microphone capture
is implemented or claimed. TTS preview is explicitly triggered by the user.
