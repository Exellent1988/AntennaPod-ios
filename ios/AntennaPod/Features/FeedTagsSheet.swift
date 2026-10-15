import SwiftUI

/// Android TagSettingsDialog (ui/screen/feed/preferences/TagSettingsDialog.java), opened from the
/// Subscriptions long-press `edit_tags` (nav_feed_context.xml) for one podcast, or from the feed
/// multi-select Actions (FeedMultiSelectActionHandler edit_tags) for several. With several podcasts it
/// shows only the tags common to all of them (TagSettingsDialog.java:57-62, "multi_feed_common_tags_info");
/// unticking a common tag removes it from every selected podcast, ticking a tag or adding a new one adds it
/// to every selected podcast, other tags stay untouched (updatePreferencesTags, :151).
struct FeedTagsSheet: View {
    @EnvironmentObject private var store: PodcastStore
    @Environment(\.dismiss) private var dismiss
    let feedIds: [UUID]
    let title: String
    @State private var newTag = ""

    init(feedId: UUID, feedTitle: String) {
        feedIds = [feedId]
        title = feedTitle
    }

    init(feedIds: [UUID], title: String) {
        self.feedIds = feedIds
        self.title = title
    }

    /// Tags every podcast in `tagLists` has (case-insensitive, display casing of the first list).
    static func commonTags(_ tagLists: [[String]]) -> [String] {
        guard let first = tagLists.first else { return [] }
        return FeedTags.uniqueSorted(first.filter { tag in
            tagLists.dropFirst().allSatisfy { list in list.contains { FeedTags.equal($0, tag) } }
        })
    }

    private var common: [String] { Self.commonTags(feedIds.map { store.tags(for: $0) }) }

    private func hasTag(_ tag: String) -> Bool {
        common.contains { FeedTags.equal($0, tag) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("New tag", text: $newTag)
                            .textInputAutocapitalization(.never)
                            .onSubmit(addNewTag)
                        Button("Add", action: addNewTag)
                            .disabled(FeedTags.normalize(newTag) == nil)
                    }
                } footer: {
                    if feedIds.count > 1 {
                        Text("Only common tags from all selected subscriptions are shown. Other tags stay unaffected.")
                    }
                }
                if !store.allTags.isEmpty {
                    Section("Tags") {
                        ForEach(store.allTags, id: \.self) { tag in
                            Button {
                                if hasTag(tag) {
                                    feedIds.forEach { store.removeTag(tag, from: $0) }
                                } else {
                                    feedIds.forEach { store.addTag(tag, to: $0) }
                                }
                            } label: {
                                HStack {
                                    Text(tag)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if hasTag(tag) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                            .accessibilityAddTraits(hasTag(tag) ? .isSelected : [])
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func addNewTag() {
        guard FeedTags.normalize(newTag) != nil else { return }
        feedIds.forEach { store.addTag(newTag, to: $0) }
        newTag = ""
    }
}
