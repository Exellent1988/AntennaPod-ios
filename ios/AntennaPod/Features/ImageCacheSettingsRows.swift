import PodcastCore
import SwiftUI

/// Settings → Storage: Android "Image cache size" (prefImageCacheSize) + clear the cover cache.
struct ImageCacheSettingsRows: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var usage: Int64 = 0

    var body: some View {
        Picker(String(localized: "Image cache size"), selection: $settings.imageCacheSizeMB) {
            ForEach(CoverCachePolicy.sizeOptionsMB, id: \.self) { mb in
                Text("\(mb) MB").tag(mb)
            }
        }
        .onChange(of: settings.imageCacheSizeMB) { _, _ in usage = CoverDiskCache.shared.usageBytes }
        Button(role: .destructive) {
            CoverDiskCache.shared.clear()
            usage = CoverDiskCache.shared.usageBytes
        } label: {
            LabeledContent(String(localized: "Clear image cache"),
                           value: ByteCountFormatter.string(fromByteCount: usage, countStyle: .file))
        }
        .onAppear { usage = CoverDiskCache.shared.usageBytes }
        Text("Cover images are kept on this device up to this size. With Images Wi‑Fi only, mobile data shows cached covers only.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
