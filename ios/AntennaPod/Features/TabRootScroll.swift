import SwiftUI

/// Re-tap on the active tab: pop to root when something is pushed, otherwise scroll the root list to the top.
/// Android: the bottom navigation has no reselect handler; its lists scroll to the top with
/// `recyclerView.smoothScrollToPosition(0)` on a toolbar long-press (EpisodesListFragment, QueueFragment,
/// FeedItemlistFragment, SubscriptionFragment, CompletedDownloadsFragment) and the keyboard "T" shortcut.
/// iOS users expect the system tab-bar convention (UITabBarController: pop, then scroll to top), so we do that.
@MainActor
final class TabReselectCenter: ObservableObject {
    @Published private(set) var scrollSignal: [RootTab: Int] = [:]
    /// Tabs whose root list is on screen (nothing pushed on top of it).
    private(set) var rootVisible: Set<RootTab> = []

    func setRootVisible(_ tab: RootTab, _ visible: Bool) {
        if visible { rootVisible.insert(tab) } else { rootVisible.remove(tab) }
    }

    func requestScrollToTop(_ tab: RootTab) {
        scrollSignal[tab, default: 0] += 1
    }
}

enum TabRootScroll {
    static let topID = "tabRoot.top"
}

/// Zero-height first row of a root list; `scrollTo(TabRootScroll.topID)` targets it.
struct TabRootTopAnchor: View {
    var body: some View {
        Color.clear
            .frame(height: 0)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .accessibilityHidden(true)
            .id(TabRootScroll.topID)
    }
}

private struct TabReselectCenterKey: EnvironmentKey {
    static let defaultValue: TabReselectCenter? = nil
}

extension EnvironmentValues {
    /// Set by RootTabView only; views reused elsewhere (sheets, previews) simply get no re-tap scrolling.
    var tabReselectCenter: TabReselectCenter? {
        get { self[TabReselectCenterKey.self] }
        set { self[TabReselectCenterKey.self] = newValue }
    }
}

private struct TabRootListModifier: ViewModifier {
    @Environment(\.tabReselectCenter) private var center
    let tab: RootTab

    func body(content: Content) -> some View {
        if let center {
            TabRootListObserver(center: center, tab: tab, content: content)
        } else {
            content
        }
    }
}

private struct TabRootListObserver<Content: View>: View {
    @ObservedObject var center: TabReselectCenter
    let tab: RootTab
    let content: Content

    var body: some View {
        ScrollViewReader { proxy in
            content
                .onAppear { center.setRootVisible(tab, true) }
                .onDisappear { center.setRootVisible(tab, false) }
                .onChange(of: center.scrollSignal[tab, default: 0]) { _, _ in
                    withAnimation { proxy.scrollTo(TabRootScroll.topID, anchor: .top) }
                }
        }
    }
}

extension View {
    /// Marks the root list of a tab (put `TabRootTopAnchor()` first inside it).
    func tabRootList(_ tab: RootTab) -> some View {
        modifier(TabRootListModifier(tab: tab))
    }
}
