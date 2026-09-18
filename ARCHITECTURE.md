# Thuban Canvas — architecture contract

Native macOS app (SwiftUI, macOS 15+, Xcode 26, Swift 5 language mode). A better, calmer Canvas: every starred
course gets a tab with the SAME set of sections regardless of how the instructor organised it; Home shows grades,
GPA, upcoming and overdue across courses; files and pages open in the app. Sibling of Thuban Study — it reuses
Thuban's theme engine (Atlas color schemes, Brass default), typography and component vocabulary.

## Layout

```
project.yml / ThubanCanvas.xcodeproj      XcodeGen (sources are directory globs → run scripts/regen.sh after adding files)
Packages/ThubanCanvasCore/                SwiftPM library (tests: swift test)
  Canvas/    CanvasModels (Codable payloads), CanvasClient (actor: GET/paginate/writes/downloads),
             CanvasEndpoints (typed calls), CanvasHTML (sanitize, plain text, link classification), WorkItems
  Grades/    GradingScheme (letters, plus/minus, custom cutoffs), GradeCalculator (Canvas arithmetic + what-if), GPA
  Storage/   AppPaths, JSONFile, CredentialStore (0600 file, NOT Keychain), DiskCache, AppSettings/SettingsStore
  Theme/     Copied from Thuban Study — ColorScheme, ThemeResolver, ResolvedTheme …
ThubanCanvas/
  App/       AppModel (root @Observable), CourseSession (per course), Resource<T> (cache-first loader),
             Routes (AppTab, CourseSection, CourseRoute), SmokeHarness, NotificationScheduler, AppIconRenderer
  Views/Shell        ShellView (title bar: mark, Home + course tabs, Inbox/Calendar/Refresh/Settings), ConnectView
  Views/Course       CourseView (section bar + detail router) and one file per section / detail
  Views/Home, Views/Calendar, Views/Inbox, Views/Settings, Views/Components, Views/Theme
  Web/       CanvasHTMLView (WKWebView with theme CSS), CanvasSchemeHandler (thubancanvas:// → authenticated fetch)
  MenuBar/   MenuBarController (NSStatusItem)
scripts/   build.sh (DERIVED=… for a private DerivedData), test.sh, regen.sh, smoke.sh, install.sh
```

## Data flow

- `AppModel` owns `client: CanvasClient?`, `settings: AppSettings` (auto-persisted to settings.json), `cache`,
  the starred `courses` and one `CourseSession` per course (`sessions[id]`, `orderedSessions`), cross-course
  resources (`todo`, `missing`, `planner`, `announcements`, `conversations`, `stream`, `unreadInbox`), `gpa`,
  `allWorkItems`, and navigation (`selectedTab`, `panel`, `open(course:section:route:)`, `openLink(url)`).
- `CourseSession` owns `course`, `section`, `path: [CourseRoute]` and the resources `groups`, `modules`, `files`,
  `folders`, `pages`, `announcements`, `discussions`, `quizzes`, `people`, `gradingStandards`, each with a
  `load…(force:)` helper. Derived: `assignments`, `workItems`, `whatIf` (persisted per course), `gradingScheme`,
  `computedGrade`, `displayScore`, `displayLetter`, `availableSections`, `displayName`, `shortCode`.
- `Resource<T>`: `value` (cached or fresh), `isLoading`, `error`, `unavailable` (403/404 → section hidden),
  `fromCache`, `hasAttempted`. Load with `resource.load(app:force:) { client in try await client.… }`.
  Wrap in `ResourceStateView(resource:retry:) { value in … }` for loading / error / empty / offline states.
- One-off fetches (a page body, a file's metadata, a discussion thread): call `app.client` directly from a
  `.task` in the view, or add a `Resource` on the session if it is reused.
- HTML from Canvas (page bodies, descriptions, syllabus, announcements, messages) renders in `CanvasHTMLView(html:title:)`
  — never `Text`. Give it a flexible frame; it scrolls. Links inside it route through `app.openLink`.
- Files: `client.courseFile(course:id:)` / `client.file(id)` → `CanvasFile.url` → `client.download(url, to:)` or
  `client.data(for:)`. PDFs render with PDFKit, images natively, everything else via Quick Look (`QLPreviewView`) or
  "Open" / "Save to Downloads". Cache downloads under `AppPaths.downloadsDirectory/<fileId>-<name>`.

## Writes to Canvas

`CanvasEndpoints` has submit (text / URL / files), conversation reply / create, discussion entry / reply, planner
mark-done, todo ignore, favorite. Rules: (1) a `ConfirmWriteSheet` ALWAYS precedes the call; (2) `app.settings.writesEnabled`
gates the buttons; (3) NEVER invoke a write endpoint during development, smoke tests or tests — the account is real.
Write paths are shipped untested against the live server; keep them simple and follow the documented API.

## Design rules (from Thuban's brief)

Quiet, academic, precise. Colors ONLY from `theme` (`@Environment(\.thubanTheme)`): `bg`, `panel`, `panel2`, `line`,
`line2`, `ink`, `inkDim`, `inkFaint`, `accent` (fills), `brassInkColor` (accent as text/icon), `accentTint`,
`pos/neg/signal` + `…Text` + `…Soft`. Never a literal hex in a view. Fonts: `ThubanFont.display` (serif: titles,
big numbers), `ThubanFont.body`, `.small`, `.micro` (uppercase eyebrows), `.mono`. Radii: cards 10, controls 8,
chips 6. 1 px hairlines, no shadows, no gradients, no emoji; SF Symbols for icons (`Image(systemName:)`) at 13–15 pt
semibold, `Glyph` for chevrons/close/search. Components: `PrimaryButtonStyle` (.thubanPrimary), `.thubanSecondary`,
`GhostButtonStyle`, `IconButton`, `Chip` (+ `.status(item)`, `.letter(letter)`), `SegmentedPicker`, `ToggleChip`,
`EmptyState`, `LoadingView`, `SectionHeader`, `PageTitle`, `AvatarView`, `CourseDot`, `ScoreText`, `ListRowCard`,
`SearchField`, `SettingsGroup`/`SettingsRow`/`SettingsNote`/`ThubanToggle`, `LabeledField`, `.thubanPanel()`,
`.thubanHairline(edge,color:)`, `.thubanField()`. Text size: multiply body sizes by `@Environment(\.thubanTextScale)`
where lists are dense. Every control has an accessibility label; lists are keyboard-navigable.

Accessibility goals (from the Canvas complaints research): consistent structure across courses; deadlines visible
everywhere (relative "Tomorrow · 11:59 PM" + countdown); nothing hidden behind hover; large hit targets; dark mode;
dyslexia-friendly font option; reduced motion option; no clutter — one primary action per screen.

## Build / test / smoke

- `DERIVED=.build/DerivedData-<name> scripts/build.sh` — use a private DerivedData when others may be building.
- `scripts/test.sh` — core tests.
- `DERIVED=… SKIP_BUILD=1 CANVAS_TOKEN_FILE=<path> scripts/smoke.sh <out-dir>` — launches the app against the real
  account (READ-ONLY), walks Home, three courses' sections, Calendar, Inbox, Settings, writes PNGs. Register extra
  screens with `SmokeHarness.extraScenes.append((name, prepare))` from your feature (e.g. in a static initializer
  called from your view's `init` is too late — call it from `AppModel.load` via an extension hook only if needed;
  otherwise just make sure your section renders in the standard walk). Look at the PNGs (Read tool) and fix what
  looks wrong before returning.
