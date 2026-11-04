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
        // No anchor row (it added a visible gap): scroll the list's own UIScrollView. Empty lists and
        // empty states just stay put; grid mode in Subscriptions is the same List.
        content
            .onAppear { center.setRootVisible(tab, true) }
            .onDisappear { center.setRootVisible(tab, false) }
            .background(ScrollToTopProbe(signal: center.scrollSignal[tab, default: 0]))
    }
}

/// Invisible view behind a root List; on a new signal it finds the List's vertical scroll view and
/// scrolls it to the top (like UITabBarController's re-tap).
private struct ScrollToTopProbe: UIViewRepresentable {
    let signal: Int

    final class Coordinator { var lastSignal: Int; init(_ s: Int) { lastSignal = s } }
    func makeCoordinator() -> Coordinator { Coordinator(signal) }

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.isUserInteractionEnabled = false
        v.isHidden = true
        return v
    }

    func updateUIView(_ view: UIView, context: Context) {
        guard signal != context.coordinator.lastSignal else { return }
        context.coordinator.lastSignal = signal
        DispatchQueue.main.async {
            guard let scroll = Self.listScrollView(near: view) else { return }
            let top = CGPoint(x: scroll.contentOffset.x, y: -scroll.adjustedContentInset.top)
            scroll.setContentOffset(top, animated: true)
        }
    }

    /// Nearest ancestor's first visible, vertically scrolling collection/table view (breadth-first).
    private static func listScrollView(near view: UIView) -> UIScrollView? {
        var ancestor = view.superview
        while let a = ancestor {
            var queue: [UIView] = [a]
            while !queue.isEmpty {
                let v = queue.removeFirst()
                if let s = v as? UIScrollView, s is UICollectionView || s is UITableView,
                   s.window != nil, !s.isHidden {
                    return s
                }
                queue.append(contentsOf: v.subviews)
            }
            ancestor = a.superview
        }
        return nil
    }
}

extension View {
    /// Marks the root list of a tab for re-tap pop / scroll-to-top.
    func tabRootList(_ tab: RootTab) -> some View {
        modifier(TabRootListModifier(tab: tab))
    }
}
