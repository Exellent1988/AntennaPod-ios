import SwiftUI

/// Shared **Queue** menu for Full player secondary + mini player ⋯ submenu.
///
/// Mirrors Full Player semantics exactly via existing `PodcastStore` APIs only:
/// - **Add to queue** → `enqueue` (immediate)
/// - **Remove from queue** → caller shows `confirmationDialog`, then `removeFromQueue`
/// - **Play Next** → `playNext` when not already next (hidden when already next)
/// - **Move playing to top** → `moveQueueItemToTop` when queued, not index 0, unlocked
/// - **Move playing to bottom** → `moveQueueItemToBottom` when queued, not last, unlocked
///
/// Nested `Menu` keeps the mini ⋯ root from overcrowding (same labels/symbols/a11y as Full).
@MainActor
enum EpisodeQueueActions {
    /// True when Play Next would leave queue order unchanged (already in the play-next slot).
    static func isAlreadyNextInQueue(
        _ episode: PodcastEpisode,
        store: PodcastStore,
        currentlyPlayingId: String?
    ) -> Bool {
        guard store.isInQueue(episode.id) else { return false }
        // Already the playing queued item: Play Next leaves that slot (does not jump to head).
        if episode.id == currentlyPlayingId { return true }
        var simulated = store.queue
        simulated.removeAll { $0.id == episode.id }
        let insertIndex: Int
        if let playingId = currentlyPlayingId,
           let index = simulated.firstIndex(where: { $0.id == playingId }) {
            insertIndex = index + 1
        } else {
            insertIndex = 0
        }
        simulated.insert(episode, at: min(insertIndex, simulated.count))
        return simulated.map(\.id) == store.queue.map(\.id)
    }

    /// True when **Move playing to top** can be offered: in queue, not already at
    /// index 0, and Queue lock is off (reorder-only). Does not seek/stop.
    static func canMovePlayingEpisodeToTop(
        _ episode: PodcastEpisode,
        store: PodcastStore,
        queueLocked: Bool
    ) -> Bool {
        guard !queueLocked,
              let index = store.queue.firstIndex(where: { $0.id == episode.id }) else {
            return false
        }
        return index > 0
    }

    /// True when **Move playing to bottom** can be offered: in queue, not already
    /// last, and Queue lock is off (reorder-only — same gate as Move to top).
    /// Does not seek/stop.
    static func canMovePlayingEpisodeToBottom(
        _ episode: PodcastEpisode,
        store: PodcastStore,
        queueLocked: Bool
    ) -> Bool {
        guard !queueLocked,
              let index = store.queue.firstIndex(where: { $0.id == episode.id }) else {
            return false
        }
        return index < store.queue.count - 1
    }

    /// Full Menu control (outer label Queue / In queue). Use as a secondary HStack
    /// button (Full) or nest inside another `Menu` for a mini ⋯ submenu.
    @ViewBuilder
    static func menu(
        episode: PodcastEpisode,
        store: PodcastStore,
        currentlyPlayingId: String?,
        queueLocked: Bool,
        onRequestRemoveFromQueue: @escaping (PodcastEpisode) -> Void
    ) -> some View {
        let inQueue = store.isInQueue(episode.id)
        let canMovePlayingToTop = canMovePlayingEpisodeToTop(
            episode,
            store: store,
            queueLocked: queueLocked
        )
        let canMovePlayingToBottom = canMovePlayingEpisodeToBottom(
            episode,
            store: store,
            queueLocked: queueLocked
        )
        Menu {
            Button {
                if inQueue {
                    // Same path as Queue tab swipe Remove — confirm first.
                    onRequestRemoveFromQueue(episode)
                } else {
                    store.enqueue(episode)
                }
            } label: {
                Label(
                    inQueue ? String(localized: "Remove from queue") : String(localized: "Add to queue"),
                    systemImage: inQueue ? "minus.circle" : "text.append"
                )
            }
            .accessibilityLabel(
                inQueue
                    ? String(localized: "Remove from queue")
                    : String(localized: "Add to queue")
            )
            .accessibilityHint(
                inQueue
                    ? String(localized: "Asks for confirmation, then removes this episode from the queue only. Does not delete the download, mark played, or stop playback.")
                    : String(localized: "Adds this episode to the end of the queue. No confirmation. Queue lock does not block enqueue. Does not start download or mark played.")
            )

            if !isAlreadyNextInQueue(
                episode,
                store: store,
                currentlyPlayingId: currentlyPlayingId
            ) {
                Button {
                    store.playNext(episode, currentlyPlayingId: currentlyPlayingId)
                } label: {
                    Label("Play Next", systemImage: "text.insert")
                }
                .accessibilityLabel(String(localized: "Play Next"))
                .accessibilityHint(String(localized: "Places this episode immediately after the currently playing queue item, or at the head if nothing is playing or current is not queued. Moves it if already queued — no duplicate. No confirmation. Queue lock does not block Play Next. Does not start playback, download, or mark played."))
            }

            // Hidden when not queued / already first / locked — same reorder-only gate as EpisodeRow.
            if canMovePlayingToTop {
                Button {
                    store.moveQueueItemToTop(episode)
                } label: {
                    Label("Move playing to top", systemImage: "arrow.up.to.line")
                }
                .accessibilityLabel(String(localized: "Move playing to top"))
                .accessibilityHint(
                    String(localized: "Moves the currently playing episode to the start of the queue. Does not seek or stop playback, change progress, mark played, or delete downloads. No confirmation.")
                )
            }

            // Hidden when not queued / already last / locked — mirror of Move playing to top.
            if canMovePlayingToBottom {
                Button {
                    store.moveQueueItemToBottom(episode)
                } label: {
                    Label("Move playing to bottom", systemImage: "arrow.down.to.line")
                }
                .accessibilityLabel(String(localized: "Move playing to bottom"))
                .accessibilityHint(
                    String(localized: "Moves the currently playing episode to the end of the queue. Does not seek or stop playback, change progress, mark played, or delete downloads. No confirmation.")
                )
            }
        } label: {
            Label(
                inQueue ? String(localized: "In queue") : String(localized: "Queue"),
                systemImage: inQueue ? "text.badge.checkmark" : "text.append"
            )
        }
        .accessibilityLabel(String(localized: "Queue actions"))
        .accessibilityValue(
            inQueue
                ? String(localized: "In queue")
                : String(localized: "Not in queue")
        )
        .accessibilityHint(String(localized: "Opens add, remove, Play Next, Move playing to top, and Move playing to bottom queue actions"))
    }
}
