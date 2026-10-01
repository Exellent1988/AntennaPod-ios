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
                    Button {
                        model.playOnPhone()
                    } label: {
                        Label("Play on iPhone", systemImage: "iphone")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
                } else {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                    Text("Open AntennaPod on iPhone to continue")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                    Button {
                        model.playOnPhone()
                    } label: {
                        Label("Open on iPhone", systemImage: "iphone")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
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
