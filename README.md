# Switched

A personal calendar + tasks + AI assistant for iOS. SwiftUI, iOS 17+.

The big idea: a task with a time is an event; an event without an end is a
task. The AI assistant lives in its own tab — type or speak; it creates,
edits, and deletes events and tasks via Claude tool-use.

---

## Stack

- **iOS app** — SwiftUI (iOS 17+), `@Observable` state, Xcode 16 file-system
  synchronised groups.
- **AI backend** — a small Cloudflare Worker that proxies the Anthropic
  Messages API. Keeps the API key off-device and rate-limits per device.
  See `worker/` if you have that folder, or the deploy notes below.
- **Storage** — `UserDefaults` JSON for events, tasks, and chat history.
  No server-side database.

---

## Run it locally

### 1. Open the project

```bash
open switched.xcodeproj
```

Requires Xcode 16+ and an iOS 17+ simulator or device.

### 2. Set the signing team

In Xcode → `switched` target → **Signing & Capabilities**:

- Pick **your Apple ID** as the Team (Personal Team is fine for local dev).
- The bundle identifier likely needs to change to something unique — e.g.
  `com.YOURNAME.switched` — because `com.alexey.switched` is already taken.

### 3. Build & run

`⌘+R`. Pick an iPhone simulator (iPhone 15 / 16 Pro works well).

### 4. Wire up the AI backend (optional but recommended)

The AI assistant calls a Cloudflare Worker, not Anthropic directly. The
Worker URL is hardcoded in `switched/AI/AIChatService.swift`:

```swift
static let backendURL = URL(string: "https://switched-ai.alexey-656.workers.dev/chat")!
```

You have two options:

**Option A — Use your own Worker (recommended for new devs).**

1. Install Wrangler: `npm install -g wrangler`
2. `wrangler login`
3. From the worker folder (if you have it, otherwise see the worker source
   below):
   ```bash
   wrangler kv namespace create RATE_LIMIT
   # paste the returned id into wrangler.toml
   wrangler secret put ANTHROPIC_KEY
   # paste your sk-ant-... key
   wrangler deploy
   ```
4. Wrangler prints a URL like `https://switched-ai.YOURNAME.workers.dev`.
   Update `backendURL` in `AIChatService.swift` to match.

**Option B — Skip AI for now.**

Comment out the AI calls or ignore the Inbox tab. Day/Week views work
without a backend.

---

## Architecture overview

```
switched/
├── SwitchedApp.swift          App entry point
├── ContentView.swift          Theme tokens + shell
├── AI/
│   ├── AIChatService.swift    Claude tool-use orchestration
│   ├── AssistantSheet.swift   Full-screen AI chat sheet
│   └── ChatMessage.swift      Codable chat model (proposed-action pattern)
├── Components/
│   └── InlineAIPill.swift     Floating inline "ask AI" pill used on Timeline / Tasks
├── Timeline/
│   ├── TimelineView.swift     Day view: events as duration-proportional blocks,
│   │                          dead hours collapse into a "free" pill, now-line
│   └── EventEditorSheet.swift Event create / edit form
├── Tasks/
│   ├── TasksView.swift        Compact week strip + group-by-day list + Unscheduled
│   └── TaskEditorSheet.swift  Task create / edit form
├── Models/
│   ├── Event.swift            Event model + colour presets
│   └── TaskItem.swift         Task model + priorities + legacy scope
├── Services/
│   ├── AIParser.swift         Legacy regex fallback parser
│   └── VoiceService.swift     SFSpeechRecognizer wrapper
└── Store/
    └── AppStore.swift         Single source of truth, UserDefaults persistence
```

### How AI actions work

1. User sends a message in the Inbox tab.
2. `AIChatService.send(...)` POSTs the conversation + a snapshot of the
   user's schedule to the Worker. The Worker forwards to Anthropic with
   the secret API key, retrying transient overload errors.
3. Claude responds with one or more **tool calls** (`create_event`,
   `update_task`, etc.) and/or natural-language text.
4. The service applies each tool call to `AppStore`, capturing
   before-snapshots so the user can **Undo** any change from the chat
   thread.
5. The assistant message + action cards persist to `UserDefaults` so the
   thread survives app restarts.

### Screens

| Surface         | What it shows                                                  |
| --------------- | -------------------------------------------------------------- |
| Timeline        | One day's events as duration-proportional blocks. Dead hours   |
|                 | collapse into a tap-to-expand "free" pill. Section labels      |
|                 | divide MORNING / AFTERNOON / EVENING. A red now-line floats    |
|                 | on top. Inline AI pill at the bottom.                          |
| Tasks           | Compact week strip with per-day counts, group-by-day list,     |
|                 | empty days collapsed onto one line, Unscheduled pinned below.  |
| Assistant sheet | Full-screen chat. AI **proposes** actions as preview cards     |
|                 | with Add / Edit / Discard buttons; nothing mutates until the   |
|                 | user approves.                                                 |

---

## Worker (Cloudflare) source

If you don't have the `worker/` folder, here's the worker code in two
files. Drop them in any folder and follow Option A above.

### `worker/wrangler.toml`

```toml
name = "switched-ai"
main = "src/index.js"
compatibility_date = "2024-11-01"

[[kv_namespaces]]
binding = "RATE_LIMIT"
id = "REPLACE_WITH_KV_ID"

[vars]
DAILY_LIMIT = "50"
ALLOWED_MODELS = "claude-haiku-4-5,claude-sonnet-4-5"
```

### `worker/src/index.js`

See `worker/src/index.js` in this repo. ~100 lines, well commented.
The Worker:

- Rate-limits per device (`x-device-id` header) at the daily limit set
  in `wrangler.toml`.
- Locks down which Claude models the client can ask for.
- Caps `max_tokens` server-side so a malicious client can't run up costs.
- Retries Anthropic 502/503/504/529 transient errors up to 3 times with
  exponential backoff.

---

## Known gaps before App Store submission

- App icon (1024×1024) not yet produced.
- Launch screen still default.
- Privacy policy URL — required by Apple, not yet hosted.
- Reduce-motion accessibility pass.
- Dynamic Type sizing.

Personal Team signed builds expire after 7 days. Paid Apple Developer
Program ($99/yr) needed for TestFlight / App Store distribution.

---

## License

Private. Not for redistribution.
