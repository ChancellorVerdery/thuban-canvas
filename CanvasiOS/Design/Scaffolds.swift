import SwiftUI
import ThubanCanvasCore
import UIKit

/// A tab's root screen: a pinned 44 pt toolbar row, then a large serif title (34) with an eyebrow that scroll with
/// the content. Once the title scrolls away its name appears inline in the bar over a hairline.
struct RootScreen<Leading: View, Trailing: View, Content: View>: View {
    @Environment(\.thubanTheme) private var theme
    var title: String
    var eyebrow: String?
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content
    @State private var collapsed = false

    init(_ title: String, eyebrow: String? = nil, @ViewBuilder leading: () -> Leading = { EmptyView() },
         @ViewBuilder trailing: () -> Trailing = { EmptyView() }, @ViewBuilder content: () -> Content) {
        self.title = title
        self.eyebrow = eyebrow
        self.leading = leading()
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).tFont(.display(34)).foregroundStyle(theme.inkColor).accessibilityAddTraits(.isHeader)
                    if let eyebrow { Eyebrow(eyebrow) }
                }
                .padding(.horizontal, IOSMetrics.gutter)
                .padding(.top, 2)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > 40
        } action: { _, value in
            collapsed = value
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            ZStack {
                if collapsed {
                    Text(title).tFont(.bodyStrong).foregroundStyle(theme.inkColor).lineLimit(1).transition(.opacity)
                        .accessibilityHidden(true)
                }
                HStack(spacing: 2) {
                    leading
                    Spacer(minLength: 0)
                    trailing
                }
                .padding(.leading, IOSMetrics.gutter)
                .padding(.trailing, 6)
            }
            .frame(height: IOSMetrics.barHeight)
            .frame(maxWidth: .infinity)
            .background(theme.bgColor)
            .overlay(alignment: .bottom) { Rectangle().fill(collapsed ? theme.lineColor : .clear).frame(height: 1) }
        }
        .background(theme.bgColor.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// A pushed screen: back chevron + previous title, centred 17 pt title, optional trailing item, pinned. The body
/// scrolls unless `scrolls` is false (screens that manage their own scrolling).
struct PushedScreen<Trailing: View, Content: View, Bottom: View>: View {
    @Environment(\.thubanTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    var title: String
    var backTitle: String
    var scrolls = true
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content
    @ViewBuilder var bottom: Bottom

    init(_ title: String, back backTitle: String, scrolls: Bool = true, @ViewBuilder trailing: () -> Trailing = { EmptyView() },
         @ViewBuilder content: () -> Content, @ViewBuilder bottom: () -> Bottom = { EmptyView() }) {
        self.title = title
        self.backTitle = backTitle
        self.scrolls = scrolls
        self.trailing = trailing()
        self.content = content()
        self.bottom = bottom()
    }

    var body: some View {
        framed
            .background(theme.bgColor.ignoresSafeArea())
            .background(SwipeBackEnabler().frame(width: 0, height: 0))
            .toolbar(.hidden, for: .navigationBar)
    }

    /// An empty bottom inset combined with the tab bar's inset leaves the scroll content unrendered on iOS 26, so
    /// the bottom inset is only attached when there is a bottom bar.
    @ViewBuilder
    private var framed: some View {
        if Bottom.self == EmptyView.self {
            scrollBody.safeAreaInset(edge: .top, spacing: 0) { bar }
        } else {
            scrollBody
                .safeAreaInset(edge: .top, spacing: 0) { bar }
                .safeAreaInset(edge: .bottom, spacing: 0) { bottom }
        }
    }

    @ViewBuilder
    private var scrollBody: some View {
        if scrolls {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) { content }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        } else {
            content
        }
    }

    private var bar: some View {
        ZStack {
            Text(title).tFont(.bodyStrong).foregroundStyle(theme.inkColor).lineLimit(1)
                .padding(.horizontal, 118)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 0) {
                Button { dismiss() } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left").font(.system(size: 19, weight: .semibold))
                        Text(backTitle).tFont(.body).lineLimit(1)
                    }
                    .foregroundStyle(theme.brassInkColor)
                    .padding(.leading, 6)
                    .padding(.trailing, 8)
                    .frame(minHeight: IOSMetrics.hitTarget)
                    .frame(maxWidth: 116, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to \(backTitle)")
                Spacer(minLength: 0)
                trailing
            }
            .padding(.trailing, 6)
        }
        .frame(height: IOSMetrics.barHeight)
        .background(theme.bgColor)
    }
}

/// The iPhone tab bar: panel fill, top hairline, 24 pt icons + 11 pt labels; brass (light) / accent (dark) when
/// selected, faint ink otherwise. Inbox carries the unread badge.
struct ThubanTabBar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                let selected = app.selectedTab == tab
                Button {
                    if app.selectedTab == tab { popToRoot(tab) } else { app.selectedTab = tab }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 21, weight: .regular))
                            .frame(height: 26)
                            .overlay(alignment: .topTrailing) {
                                if tab == .inbox, app.unreadInbox > 0 {
                                    Text("\(app.unreadInbox)")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(theme.onAccentColor)
                                        .padding(.horizontal, 5)
                                        .frame(minWidth: 18, minHeight: 18)
                                        .background(theme.accentColor, in: Capsule())
                                        .offset(x: 12, y: -4)
                                }
                            }
                        Text(tab.title).font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(selected ? theme.brassInkColor : theme.inkFaintColor)
                    .frame(maxWidth: .infinity, minHeight: 49)
                    .padding(.top, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab == .inbox && app.unreadInbox > 0 ? "Inbox, \(app.unreadInbox) unread" : tab.title)
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.horizontal, 8)
        .background(theme.panelColor.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(theme.lineColor).frame(height: 1) }
    }

    private func popToRoot(_ tab: MainTab) {
        switch tab {
        case .home: app.homePath = []
        case .courses: app.coursesPath = []
        case .calendar: app.calendarPath = []
        case .inbox: app.inboxPath = []
        }
    }
}

/// Keeps the edge-swipe back gesture working while the system navigation bar is hidden: finds the hosting
/// navigation controller and gives its pop recognizer a delegate that allows the swipe whenever something is pushed.
struct SwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            enable()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            enable()
        }

        private func enable() {
            guard let navigation = navigationController, let recognizer = navigation.interactivePopGestureRecognizer else { return }
            PopGestureDelegate.shared.navigation = navigation
            recognizer.delegate = PopGestureDelegate.shared
            recognizer.isEnabled = true
        }
    }
}

final class PopGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    static let shared = PopGestureDelegate()
    weak var navigation: UINavigationController?

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        (navigation?.viewControllers.count ?? 0) > 1
    }
}
