import AppKit
import SwiftUI
import ThubanCanvasCore

/// The syllabus body (already fetched with the course) in the themed web view; when the instructor left it
/// empty, a quiet note with a link to Canvas's syllabus page, which also lists the assignment schedule.
struct SyllabusView: View {
    @Bindable var session: CourseSession

    private var syllabus: String { (session.course.syllabusBody ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        if syllabus.isEmpty {
            EmptyState(title: "No syllabus posted", message: "Your instructor has not written a syllabus here. Canvas's syllabus page may still list the schedule.") {
                if let url = session.canvasURL("assignments/syllabus") {
                    Button("Open in Canvas") { NSWorkspace.shared.open(url) }
                        .buttonStyle(.thubanSecondary)
                        .accessibilityLabel("Open the syllabus page in Canvas")
                }
            }
        } else {
            CanvasHTMLView(html: syllabus, title: "Syllabus")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Syllabus")
        }
    }
}
