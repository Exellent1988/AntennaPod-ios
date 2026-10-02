import SwiftUI
import WidgetKit

/// Homescreen widget: Continue listening from an App Group snapshot (beta lite).
struct AntennaPodContinueWidget: Widget {
    let kind = AntennaPodAppGroup.continueWidgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ContinueListeningProvider()) { entry in
            ContinueListeningWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(.systemBackground)
                }
        }
        .configurationDisplayName("Continue listening")
        .description("Shows the episode you were last listening to. Tap to open AntennaPod.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ContinueListeningEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetContinueSnapshot?
}

struct ContinueListeningProvider: TimelineProvider {
    func placeholder(in context: Context) -> ContinueListeningEntry {
        ContinueListeningEntry(
            date: Date(),
            snapshot: WidgetContinueSnapshot(
                episodeId: "placeholder",
                episodeTitle: String(localized: "Episode title"),
                feedTitle: String(localized: "Podcast name"),
                updatedAtEpochMs: 0,
                positionSeconds: 600,
                durationSeconds: 3600
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ContinueListeningEntry) -> Void) {
        completion(ContinueListeningEntry(date: Date(), snapshot: WidgetContinueSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ContinueListeningEntry>) -> Void) {
        let entry = ContinueListeningEntry(date: Date(), snapshot: WidgetContinueSnapshot.load())
        // Snapshot-driven; main app reloads timelines on write. Soft refresh hourly.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct ContinueListeningWidgetView: View {
    var entry: ContinueListeningEntry

    var body: some View {
        Group {
            if let snap = entry.snapshot {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Continue listening", systemImage: "play.circle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(snap.episodeTitle)
                        .font(.headline)
                        .lineLimit(3)
                        .minimumScaleFactor(0.85)
                    if !snap.feedTitle.isEmpty {
                        Text(snap.feedTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    // Single Continue episode remaining (same snapshot as title/feed; may be stale).
                    // Known duration → wall-clock max(0, duration − position); unknown → "~"; hide only when no episode.
                    if let remaining = WidgetRemainingTime.remainingLabel(for: snap) {
                        Text(remaining)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .accessibilityLabel(WidgetRemainingTime.remainingAccessibilityLabel(for: snap))
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Open AntennaPod to continue")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "Open AntennaPod to continue"))
                .accessibilityValue(
                    String(localized: "No Continue listening snapshot is saved yet. This is not live playback and not the queue. Play an episode in AntennaPod to write the App Group snapshot. Until then there is no episode title or remaining time.")
                )
                .accessibilityHint(
                    String(localized: "Opens AntennaPod and sends play. Playback starts only if an episode is already loaded. Does not create a continue episode.")
                )
            }
        }
        .widgetURL(WidgetContinueSnapshot.playURL)
    }
}

#if DEBUG
struct ContinueListeningWidgetView_Previews: PreviewProvider {
    static var previews: some View {
        ContinueListeningWidgetView(
            entry: ContinueListeningEntry(
                date: Date(),
                snapshot: WidgetContinueSnapshot(
                    episodeId: "1",
                    episodeTitle: "Sample episode about widgets",
                    feedTitle: "AntennaPod Talk",
                    updatedAtEpochMs: 0,
                    positionSeconds: 900,
                    durationSeconds: 3600
                )
            )
        )
        .previewContext(WidgetPreviewContext(family: .systemSmall))

        ContinueListeningWidgetView(entry: ContinueListeningEntry(date: Date(), snapshot: nil))
            .previewContext(WidgetPreviewContext(family: .systemMedium))
    }
}
#endif
