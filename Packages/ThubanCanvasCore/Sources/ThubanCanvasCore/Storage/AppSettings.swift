import Foundation

/// Per-course preferences the user sets in the app (Canvas has no place for them).
public struct CoursePreferences: Codable, Equatable, Sendable {
    public var nickname: String?
    public var credits: Double?
    /// "A 90, B 80 …" typed by the user; overrides the course scheme for letters and GPA.
    public var customCutoffs: String?
    public var tint: String?
    public var excludeFromGPA: Bool
    /// Hidden courses keep their star in Canvas but get no tab and are left out of Home, Calendar, reminders and the menu bar.
    public var hidden: Bool

    public init(nickname: String? = nil, credits: Double? = nil, customCutoffs: String? = nil, tint: String? = nil, excludeFromGPA: Bool = false, hidden: Bool = false) {
        self.nickname = nickname
        self.credits = credits
        self.customCutoffs = customCutoffs
        self.tint = tint
        self.excludeFromGPA = excludeFromGPA
        self.hidden = hidden
    }

    enum CodingKeys: String, CodingKey { case nickname, credits, customCutoffs, tint, excludeFromGPA, hidden }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nickname = try c.decodeIfPresent(String.self, forKey: .nickname)
        credits = try c.decodeIfPresent(Double.self, forKey: .credits)
        customCutoffs = try c.decodeIfPresent(String.self, forKey: .customCutoffs)
        tint = try c.decodeIfPresent(String.self, forKey: .tint)
        excludeFromGPA = try c.decodeIfPresent(Bool.self, forKey: .excludeFromGPA) ?? false
        hidden = try c.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
    }
}

public enum LetterScale: String, Codable, CaseIterable, Sendable {
    case plusMinus, plain
    public var label: String { self == .plusMinus ? "Plus / minus" : "Letters only" }
    public var scheme: GradingScheme { self == .plusMinus ? .plusMinus : .plain }
    /// The letters a transcript on this scale can show, best first.
    public var letters: [String] { scheme.cutoffs.map(\.letter) }
}

public struct NotificationPreferences: Codable, Equatable, Sendable {
    public var enabled: Bool
    /// Hours before a due date to remind.
    public var leadHours: [Int]
    public var announcements: Bool
    public var grades: Bool
    public var inbox: Bool

    public init(enabled: Bool = true, leadHours: [Int] = [24, 2], announcements: Bool = true, grades: Bool = true, inbox: Bool = true) {
        self.enabled = enabled
        self.leadHours = leadHours
        self.announcements = announcements
        self.grades = grades
        self.inbox = inbox
    }
}

public enum TextSize: String, Codable, CaseIterable, Sendable {
    case compact, regular, large, extraLarge
    public var label: String {
        switch self {
        case .compact: return "Compact"
        case .regular: return "Regular"
        case .large: return "Large"
        case .extraLarge: return "Extra large"
        }
    }
    /// Multiplier applied to body sizes.
    public var scale: Double {
        switch self {
        case .compact: return 0.92
        case .regular: return 1
        case .large: return 1.12
        case .extraLarge: return 1.25
        }
    }
}

/// Everything persisted in `settings.json`. Decoding tolerates missing keys (each has a default).
public struct AppSettings: Codable, Equatable, Sendable {
    public var theme: ThemeSelection = .default
    public var textSize: TextSize = .regular
    public var reduceMotion: Bool = false
    public var dyslexiaFont: Bool = false
    public var letterScale: LetterScale = .plusMinus
    public var defaultCredits: Double = 3
    public var coursePreferences: [CanvasID: CoursePreferences] = [:]
    public var pastSemesters: [PastSemester] = []
    /// "course:assignment" keys the user dismissed from the overdue list.
    public var dismissedOverdue: Set<String> = []
    public var notifications = NotificationPreferences()
    public var menuBarEnabled: Bool = true
    /// Minutes between background refreshes.
    public var refreshMinutes: Int = 15
    /// Write actions (submit, reply, message) are shown; each still confirms.
    public var writesEnabled: Bool = true
    public var courseOrder: [CanvasID] = []
    public var lastSelectedTab: String?
    public var whatIf: [CanvasID: WhatIf] = [:]
    /// Where "Save to Downloads" puts files. nil = ~/Downloads.
    public var downloadFolder: String?

    public init() {}

    enum CodingKeys: String, CodingKey {
        case theme, textSize, reduceMotion, dyslexiaFont, letterScale, defaultCredits, coursePreferences, pastSemesters,
             dismissedOverdue, notifications, menuBarEnabled, refreshMinutes, writesEnabled, courseOrder, lastSelectedTab, whatIf, downloadFolder
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        theme = try c.decodeIfPresent(ThemeSelection.self, forKey: .theme) ?? .default
        textSize = try c.decodeIfPresent(TextSize.self, forKey: .textSize) ?? .regular
        reduceMotion = try c.decodeIfPresent(Bool.self, forKey: .reduceMotion) ?? false
        dyslexiaFont = try c.decodeIfPresent(Bool.self, forKey: .dyslexiaFont) ?? false
        letterScale = try c.decodeIfPresent(LetterScale.self, forKey: .letterScale) ?? .plusMinus
        defaultCredits = try c.decodeIfPresent(Double.self, forKey: .defaultCredits) ?? 3
        coursePreferences = try c.decodeIfPresent([CanvasID: CoursePreferences].self, forKey: .coursePreferences) ?? [:]
        pastSemesters = try c.decodeIfPresent([PastSemester].self, forKey: .pastSemesters) ?? []
        dismissedOverdue = try c.decodeIfPresent(Set<String>.self, forKey: .dismissedOverdue) ?? []
        notifications = try c.decodeIfPresent(NotificationPreferences.self, forKey: .notifications) ?? NotificationPreferences()
        menuBarEnabled = try c.decodeIfPresent(Bool.self, forKey: .menuBarEnabled) ?? true
        refreshMinutes = try c.decodeIfPresent(Int.self, forKey: .refreshMinutes) ?? 15
        writesEnabled = try c.decodeIfPresent(Bool.self, forKey: .writesEnabled) ?? true
        courseOrder = try c.decodeIfPresent([CanvasID].self, forKey: .courseOrder) ?? []
        lastSelectedTab = try c.decodeIfPresent(String.self, forKey: .lastSelectedTab)
        whatIf = try c.decodeIfPresent([CanvasID: WhatIf].self, forKey: .whatIf) ?? [:]
        downloadFolder = try c.decodeIfPresent(String.self, forKey: .downloadFolder)
    }

    public func preferences(for course: CanvasID) -> CoursePreferences {
        coursePreferences[course] ?? CoursePreferences()
    }

    public func credits(for course: CanvasID) -> Double {
        coursePreferences[course]?.credits ?? defaultCredits
    }
}

public enum SettingsStore {
    public static func load() -> AppSettings {
        (try? JSONFile.read(AppSettings.self, from: AppPaths.settingsFile)) ?? AppSettings()
    }

    public static func save(_ settings: AppSettings) throws {
        try AppPaths.ensureDirectories()
        try JSONFile.write(settings, to: AppPaths.settingsFile)
    }
}
