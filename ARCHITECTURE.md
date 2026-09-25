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

`CanvasEndpoints` has submit (text / URL / files), conversation reply / create / batch (read, unread, star, archive,
delete), discussion entry / reply, planner mark-done, todo ignore, favorite. Rules: (1) irreversible writes (submit,
post, send, archive, delete) ALWAYS go through a `ConfirmWriteSheet`; reversible inbox state (read/unread, star) and
mark-read-on-open run immediately, as the web inbox does; (2) `app.settings.writesEnabled` gates every write;
(3) NEVER invoke a write endpoint during development, smoke tests or tests — the account is real.
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

## iOS app (target `CanvasiOS`, iPhone + iPad, iOS 18+)

Same `project.yml`, second application target: product "Thuban Canvas", bundle id `org.thuban.canvas.ios`, sources in
`CanvasiOS/`, unsigned simulator builds (`CODE_SIGNING_ALLOWED[sdk=iphonesimulator*] = NO`). Design source of truth:
the approved iOS design canvas (Home, Courses, Calendar, Inbox, Course hub, Modules, Assignment, Grades what-if,
dark Home, Settings sheet, Connect, iPad split view).

**READ-ONLY toward Canvas.** The iOS client's URLSession runs every request through `ReadOnlyGuard` (core), which
fails any non-GET/HEAD locally, and no screen offers a write: "Submit in Canvas" / "Take quiz in Canvas" open the
assignment in `SFSafariViewController`; the inbox has no compose/reply/star/archive; threads load with
`auto_mark_as_read=false`. Local-only state (overdue dismissals, what-if scores, nicknames, hidden courses, course
order, credits, past semesters) lives in `settings.json` on the device.

Shared with the Mac target (listed file by file in `project.yml`; keep them platform-neutral, fence AppKit/UIKit with
`#if os(macOS)` / `#if os(iOS)`): `App/Resource.swift`, `App/CourseSession.swift`, `App/Routes.swift`,
`Views/Theme/ThemeEnvironment.swift` (tokens, `Color(hex:)`, `ChipKind`; `NSColor(hex:)` is macOS-only),
`Views/Components/AppArt.swift` + `AppArtSource.swift` (mark drawn via `Color.resolve(in:)`),
`Views/Calendar/CalendarModel.swift`, `Web/CanvasSchemeHandler.swift`, `Web/CanvasHTMLDocument.swift` (the themed HTML
document both platforms render Canvas HTML in). The iOS `AppModel` is its own class but exposes the members those
files use (`settings`, `cache`, `client`, `courses`, `noteUnauthorized()`).

```
CanvasiOS/
  App/      ThubanCanvasApp (@main, RootView: theme/font environment, Connect vs iPhone tabs vs iPad split, Settings
            sheet, Safari sheet, Quick Look), AppModel, Navigation (MainTab, Route, HubSection, SidebarItem),
            InboxStore (+ Reminders: local notifications only), CourseSession+iOS (hub/grades facts), SmokeHarness
  Design/   Typography (tFont: Dynamic Type × in-app text size, serif display, dyslexia option), Components (Card,
            Eyebrow, ChipView/LetterChip, IconButton 44 pt, PrimaryButton 50 pt, SearchBar, FilterChips, Segmented,
            ThubanSwitch …), Scaffolds (RootScreen: pinned toolbar + 34 pt serif title; PushedScreen: back + inline
            title; ThubanTabBar; SwipeBackEnabler)
  Screens/  Home, Courses, Course (hub, Modules, Assignment, Grades, sections), Calendar, Inbox, Settings (sheet,
            pages, custom scheme, past semesters), Connect, IPad (NavigationSplitView sidebar + course view)
  Web/      HTMLContentView (self-sizing WKWebView, page JS off), SafariView
  Resources/Assets.xcassets (AppIcon 1024 from scripts/make_ios_icon.sh, LaunchBackground, AccentColor), Info.plist
```

- Navigation: iPhone = custom tab bar (brass/accent selected) over one `NavigationStack` per tab (paths on
  `AppModel`); system navigation bars are hidden and every screen draws the house header. `app.push(route)` pushes on
  the visible stack (iPad: the detail stack). iPad (regular width) = `NavigationSplitView` with the sidebar; a course
  shows a section bar and, for Assignments, list + detail side by side (list only below 700 pt).
- `PushedScreen` attaches a bottom safe-area inset only when it has a bottom bar: an empty inset stacked on the tab
  bar's inset left the scroll content unrendered on iOS 26.
- Storage: no Keychain. `credentials.json` in Application Support inside the container, 0600 +
  `NSFileProtectionComplete` (`JSONFile.write(protected:)`); cache and downloaded files (`files/<id>/<name>`,
  opened in Quick Look) beside it. Notifications are local due-date reminders; no widgets, Live Activities or push.
- Theme: the 8 Atlas presets + custom (system colour picker) × Automatic/Light/Dark, same `ResolvedTheme` tokens as
  the Mac; Light/Dark are applied as a window `overrideUserInterfaceStyle`.

Demo account / tests: core `DemoCanvas` + `DemoTransport` serve a complete fake UNC Charlotte account (five courses,
modules, grades, inbox, events, PDFs) with dates relative to now; writes get 405 and are counted
(`DemoTransport.blockedWrites`). `THUBAN_CANVAS_DEMO=1` launches the app on it; unit tests in
`IOSSupportTests.swift` use it too. Never point tests or smoke runs at the real account.

Scripts:
- `scripts/ios_build.sh` — simulator build into `.build/DerivedData-iOS` (`CONFIG=Release` for Release).
- `scripts/ios_smoke.sh [out]` — boots its own "Thuban Canvas Smoke" iPhone 17 (and "Thuban Canvas Smoke iPad",
  iPad Pro 13"), launches once per scene with `SIMCTL_CHILD_THUBAN_CANVAS_SMOKE_SCENE=<scene>` (+ `…_APPEARANCE=dark`,
  `…_SCHEME=<preset>`), waits for `Library/Caches/smoke-ready`, saves PNGs to `.build/ios-smoke` (light + dark + iPad).
  Offline: demo account, throwaway home. Fails if any write was attempted. `SCENES="home grades"`, `SKIP_BUILD=1`,
  `IPAD=0`, `KEEP_BOOTED=1`. iPadOS 26 windowed mode refuses programmatic rotation, so iPad shots are portrait.
- `scripts/ios_install.sh` — Release build into the "Thuban iPhone" simulator; with a paired iPhone
  (`xcrun devicectl list devices`) and `DEVELOPMENT_TEAM=<team>` also a signed device build + install.
- `scripts/make_ios_icon.sh` — regenerates the iOS AppIcon from `AppArt` (Brass dark plate).
