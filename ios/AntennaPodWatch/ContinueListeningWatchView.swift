import SwiftUI

/// Apple Watch Continue listening (beta lite): title/feed from phone snapshot; Play remotes the iPhone.
struct ContinueListeningWatchView: View {
    @ObservedObject var model: WatchContinueModel

    var body: some View {
        NavigationStack {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Label("Continue listening", systemImage: "play.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if let snap = model.snapshot {
                    Text(snap.episodeTitle)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    if !snap.feedTitle.isEmpty {
                        Text(snap.feedTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // Same Continue snapshot remaining as Homescreen Widget (may be stale).
                    if let remaining = WidgetRemainingTime.remainingLabel(for: snap) {
                        Text(remaining)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .accessibilityLabel(WidgetRemainingTime.remainingAccessibilityLabel(for: snap))
                    }
                    Button {
                        model.playOnPhone()
                    } label: {
                        Label("Play on iPhone", systemImage: "iphone")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                        Text("Open AntennaPod on iPhone to continue")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(String(localized: "Open AntennaPod on iPhone to continue"))
                    .accessibilityValue(
                        String(localized: "No Continue listening snapshot is saved yet. This is not live playback and not the queue. Play an episode in AntennaPod on iPhone to write the snapshot for Watch. Until then there is no episode title or remaining time.")
                    )
                    Button {
                        model.playOnPhone()
                    } label: {
                        Label("Open on iPhone", systemImage: "iphone")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
                    .accessibilityHint(
                        String(localized: "Opens AntennaPod on iPhone and sends play. Plays the loaded episode, or after a cold launch the previous run’s unplayed episode restored paused in the mini player. Does not invent any other continue episode. No independent Watch playback.")
                    )
                }

                if let status = model.statusMessage {
                    Text(status)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text("No independent Watch playback, downloads, or queue. Transport when already playing: system Now Playing on Watch.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
        .navigationTitle("AntennaPod")
        #if os(watchOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear { model.refreshFromLocalSources() }
        } // NavigationStack
    }
}

#if DEBUG
struct ContinueListeningWatchView_Previews: PreviewProvider {
    static var previews: some View {
        ContinueListeningWatchView(model: WatchContinueModel())
    }
}
#endif
