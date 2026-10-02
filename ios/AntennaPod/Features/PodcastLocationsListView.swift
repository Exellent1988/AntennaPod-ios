import SwiftUI
import UIKit

/// Simple feed-provided `podcast:location` list: name + optional geo/rel/osm; Copy / Share the same text,
/// and Open in Maps when geo lat,lon is present.
/// Caps at `PodcastLocationDisplay.displayCap` with an honesty footnote when truncated.
/// **Never geocodes** names — Maps only when the feed supplied a parseable `geo` attribute.
struct PodcastLocationsListView: View {
    @Environment(\.openURL) private var openURL

    @State private var showCopiedAlert = false
    @State private var copyFeedbackTick = 0

    let locations: [PodcastLocation]
    /// Section title (localized by caller).
    var title: String = String(localized: "Locations")

    private var capped: (shown: [PodcastLocation], truncated: Bool) {
        PodcastLocationDisplay.capped(locations)
    }

    var body: some View {
        let result = capped
        if !result.shown.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)

                ForEach(Array(result.shown.enumerated()), id: \.offset) { _, location in
                    locationRow(location)
                }

                if result.truncated {
                    Text(String(localized: "Showing first 20 locations from the feed."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(String(localized: "Showing first 20 locations from the feed."))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .alert(String(localized: "Copied"), isPresented: $showCopiedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(String(localized: "Location copied to the pasteboard."))
            }
            .sensoryFeedback(.success, trigger: copyFeedbackTick)
        }
    }

    @ViewBuilder
    private func locationRow(_ location: PodcastLocation) -> some View {
        let name = location.displayName ?? location.name
        let rel = location.displayRel
        let osm = location.displayOsm
        let mapsURL = location.appleMapsURL
        let copyText = PodcastLocationDisplay.copyText(location)

        let a11yLabel: String = {
            var parts = [name]
            if let rel { parts.append(String(localized: "Relation \(rel)")) }
            if let osm { parts.append(String(localized: "OpenStreetMap \(osm)")) }
            if mapsURL != nil { parts.append(String(localized: "Has map coordinates from the feed")) }
            return parts.joined(separator: ", ")
        }()

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(name)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                if let rel {
                    Text(rel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(a11yLabel)

            if let osm {
                Text(String(localized: "OSM \(osm)"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel(String(localized: "OpenStreetMap \(osm)"))
            }

            if !copyText.isEmpty {
                HStack(spacing: 12) {
                    Button {
                        UIPasteboard.general.string = copyText
                        copyFeedbackTick += 1
                        showCopiedAlert = true
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Copy location"))
                    .accessibilityHint(
                        String(localized: "Copies the feed-provided location name and attributes to the pasteboard")
                    )

                    ShareLink(item: copyText) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Share location"))
                    .accessibilityHint(
                        String(localized: "Shares the same feed-provided location text as Copy; does not open Maps or geocode")
                    )
                }
            }

            if let url = mapsURL {
                Button {
                    openURL(url)
                } label: {
                    Label("Open in Maps", systemImage: "map")
                        .font(.subheadline)
                }
                .accessibilityLabel(String(localized: "Open in Maps"))
                .accessibilityHint(String(localized: "Opens this location in Apple Maps using coordinates from the feed"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}
