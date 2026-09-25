import Foundation
import SwiftUI
import ThubanCanvasCore
import UIKit

/// Offline visual smoke run. `THUBAN_CANVAS_SMOKE_SCENE=<scene>` (passed as SIMCTL_CHILD_… by scripts/ios_smoke.sh)
/// starts the app on the demo account (fake transport, throwaway home, nothing persisted, no network), seeds the
/// local settings the designs show, navigates to the scene and then writes `Library/Caches/smoke-ready` so the script
/// can take the screenshot. `THUBAN_CANVAS_SMOKE_APPEARANCE=dark|light` and `THUBAN_CANVAS_SMOKE_SCHEME=<preset>`
/// vary the theme.
@MainActor
enum SmokeHarness {
    static let environment = ProcessInfo.processInfo.environment
    static var scene: String? { environment["THUBAN_CANVAS_SMOKE_SCENE"] }
    static var isActive: Bool { scene != nil }
    static var showsConnect: Bool { scene == "connect" }
    static var opensFirstSwipe: Bool { scene == "home-swipe" }

    /// Seeds settings before the first load.
    static func prepare(app: AppModel) {
        guard isActive else { return }
        var settings = AppSettings()
        settings.letterScale = .plain
        settings.coursePreferences = [
            101: CoursePreferences(credits: 3), 102: CoursePreferences(credits: 4), 103: CoursePreferences(credits: 3),
            104: CoursePreferences(credits: 3), 105: CoursePreferences(credits: 3),
        ]
        settings.pastSemesters = [
            PastSemester(name: "Fall 2024", gpa: 3.30, credits: 12),
            PastSemester(name: "Spring 2025", gpa: 3.42, credits: 11),
            PastSemester(name: "Fall 2025", gpa: 3.51, credits: 11),
            PastSemester(name: "Spring 2026", gpa: 3.58, credits: 11),
        ]
        settings.notifications = NotificationPreferences(enabled: true, leadHours: [24, 1])
        switch environment["THUBAN_CANVAS_SMOKE_APPEARANCE"] {
        case "dark": settings.theme.mode = .dark
        case "light": settings.theme.mode = .light
        default: settings.theme.mode = .light
        }
        if let scheme = environment["THUBAN_CANVAS_SMOKE_SCHEME"], SchemePresets.scheme(id: scheme) != nil { settings.theme.schemeId = scheme }
        if scene == "settings-large" { settings.textSize = .large }
        app.settings = settings
    }

    /// Navigates to the scene once data is loaded, then signals the script.
    static func run(app: AppModel) async {
        guard let scene else { return }
        app.applyInterfaceStyle()
        switch scene {
        case "home", "home-swipe", "connect": app.selectedTab = .home
        case "home-scrolled": app.selectedTab = .home
        case "courses": app.selectedTab = .courses
        case "calendar": app.selectedTab = .calendar
        case "calendar-month": app.selectedTab = .calendar; app.calendarMonthMode = true
        case "inbox": app.selectedTab = .inbox
        case "conversation": app.selectedTab = .inbox; app.inboxPath = [.conversation(501)]
        case "course": app.selectedTab = .courses; app.coursesPath = [.course(101)]
        case "modules": app.selectedTab = .courses; app.coursesPath = [.course(101), .modules(101)]
        case "assignment": app.selectedTab = .courses; app.coursesPath = [.course(101), .modules(101), .assignment(course: 101, id: 10115)]
        case "assignments": app.selectedTab = .courses; app.coursesPath = [.course(101), .assignments(101)]
        case "grades":
            app.selectedTab = .courses
            app.coursesPath = [.course(101), .grades(101)]
            app.settings.whatIf[101] = WhatIf(scores: [10132: .score(90), 10115: .score(18)])
        case "announcement": app.selectedTab = .courses; app.coursesPath = [.course(101), .announcements(101), .announcement(course: 101, id: 70101)]
        case "syllabus": app.selectedTab = .courses; app.coursesPath = [.course(101), .syllabus(101)]
        case "people": app.selectedTab = .courses; app.coursesPath = [.course(101), .people(101)]
        case "past-semesters": app.selectedTab = .home; app.homePath = [.pastSemesters]
        case "settings", "settings-large": app.selectedTab = .home; app.showingSettings = true
        case "file":
            app.selectedTab = .courses
            app.coursesPath = [.course(101), .modules(101)]
            try? await Task.sleep(nanoseconds: 800_000_000)
            await app.openFile(course: 101, id: 9002)
        case "ipad":
            app.sidebar = .course(101)
            app.ipadSections[101] = .assignments
            app.ipadAssignment[101] = 10115
        case "ipad-home": app.sidebar = .home
        case "ipad-grades":
            app.sidebar = .course(101)
            app.ipadSections[101] = .grades
        default: break
        }
        // Let lists, web views and Quick Look settle before the screenshot.
        try? await Task.sleep(nanoseconds: scene == "file" ? 2_500_000_000 : 2_000_000_000)
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        try? "\(scene) blockedWrites=\(DemoTransport.blockedWrites)".write(to: caches.appendingPathComponent("smoke-ready"), atomically: true, encoding: .utf8)
    }
}
