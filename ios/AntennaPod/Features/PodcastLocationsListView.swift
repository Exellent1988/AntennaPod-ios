import SwiftUI
import UIKit

/// Simple feed-provided `podcast:location` list: name + optional geo/rel/osm; Copy / Share the same text,
/// distinct Copy / Share for displayed name, relation, OSM, and geo when present, and Open in Maps when geo lat,lon parses.
/// Caps at `PodcastLocationDisplay.displayCap` with an honesty footnote when truncated.
/// **Never geocodes** names — name/geo caption/Copy/Share use the exact feed strings; Maps only when geo parses to lat,lon.
struct PodcastLocationsListView: View {
    @Environment(\.openURL) private var openURL

    @State private var showCopiedAlert = false
    @State private var copiedMessage = String(localized: "Location copied to the pasteboard.")
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
                Text(copiedMessage)
            }
            .sensoryFeedback(.success, trigger: copyFeedbackTick)
        }
    }

    @ViewBuilder
    private func locationRow(_ location: PodcastLocation) -> some View {
        let displayedName = location.displayName
        let name = displayedName ?? location.name
        let rel = location.displayRel
        let osm = location.displayOsm
        let osmCaption: String? = osm.map { String(localized: "OSM \($0)") }
        let geo = location.displayGeo
        let mapsURL = location.appleMapsURL
        let copyText = PodcastLocationDisplay.copyText(location)

        let a11yLabel: String = {
            var parts = [name]
            if let rel { parts.append(String(localized: "Relation \(rel)")) }
            if let osm { parts.append(String(localized: "OpenStreetMap \(osm)")) }
            if let geo { parts.append(String(localized: "Geo \(geo)")) }
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

            if let geo {
                Text(geo)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel(String(localized: "Geo \(geo)"))
            }

            if let osm, let osmCaption {
                Text(osmCaption)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel(String(localized: "OpenStreetMap \(osm)"))
            }

            if let displayedName {
                HStack(spacing: 12) {
                    Button {
                        copyToPasteboard(
                            displayedName,
                            confirmation: String(localized: "Location name copied to the pasteboard.")
                        )
                    } label: {
                        Label("Copy location name", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Copy location name"))
                    .accessibilityHint(
                        String(
                            localized: "Copies the exact displayed feed-provided location name to the pasteboard; does not geocode or invent a name"
                        )
                    )

                    ShareLink(item: displayedName) {
                        Label("Share location name", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Share location name"))
                    .accessibilityHint(
                        String(
                            localized: "Shares the exact displayed feed-provided location name as plain text; does not geocode or invent a name"
                        )
                    )
                }
            }

            if !copyText.isEmpty {
                HStack(spacing: 12) {
                    Button {
                        copyToPasteboard(
                            copyText,
                            confirmation: String(localized: "Location copied to the pasteboard.")
                        )
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

            if let rel {
                HStack(spacing: 12) {
                    Button {
                        copyToPasteboard(
                            rel,
                            confirmation: String(localized: "Location relation copied to the pasteboard.")
                        )
                    } label: {
                        Label("Copy location relation", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Copy location relation"))
                    .accessibilityHint(
                        String(localized: "Copies the exact displayed feed-provided location relation to the pasteboard")
                    )

                    ShareLink(item: rel) {
                        Label("Share location relation", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Share location relation"))
                    .accessibilityHint(
                        String(localized: "Shares the exact displayed feed-provided location relation as plain text")
                    )
                }
            }

            if let osmCaption {
                HStack(spacing: 12) {
                    Button {
                        copyToPasteboard(
                            osmCaption,
                            confirmation: String(localized: "Location OSM copied to the pasteboard.")
                        )
                    } label: {
                        Label("Copy location OSM", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Copy location OSM"))
                    .accessibilityHint(
                        String(localized: "Copies the exact displayed feed-provided location OSM caption to the pasteboard")
                    )

                    ShareLink(item: osmCaption) {
                        Label("Share location OSM", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Share location OSM"))
                    .accessibilityHint(
                        String(localized: "Shares the exact displayed feed-provided location OSM caption as plain text")
                    )
                }
            }

            if let geo {
                HStack(spacing: 12) {
                    Button {
                        copyToPasteboard(
                            geo,
                            confirmation: String(localized: "Location geo copied to the pasteboard.")
                        )
                    } label: {
                        Label("Copy location geo", systemImage: "doc.on.doc")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Copy location geo"))
                    .accessibilityHint(
                        String(
                            localized: "Copies the exact displayed feed-provided location geo string to the pasteboard; does not geocode or invent coordinates"
                        )
                    )

                    ShareLink(item: geo) {
                        Label("Share location geo", systemImage: "square.and.arrow.up")
                            .font(.subheadline)
                    }
                    .accessibilityLabel(String(localized: "Share location geo"))
                    .accessibilityHint(
                        String(
                            localized: "Shares the exact displayed feed-provided location geo string as plain text; does not geocode or invent coordinates"
                        )
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

    private func copyToPasteboard(_ string: String, confirmation: String) {
        UIPasteboard.general.string = string
        copiedMessage = confirmation
        copyFeedbackTick &+= 1
        showCopiedAlert = true
    }
}
