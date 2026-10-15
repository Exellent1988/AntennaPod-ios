import SwiftUI

/// Android TagSettingsDialog (ui/screen/feed/preferences/TagSettingsDialog.java), opened from the
/// Subscriptions long-press `edit_tags` (nav_feed_context.xml): this podcast's tags plus the existing
/// vocabulary to toggle, and a field to add a new tag. Uses the same store calls as podcast settings.
struct FeedTagsSheet: View {
    @EnvironmentObject private var store: PodcastStore
    @Environment(\.dismiss) private var dismiss
    let feedId: UUID
    let feedTitle: String
    @State private var newTag = ""

    private var currentTags: [String] { store.tags(for: feedId) }

    private func hasTag(_ tag: String) -> Bool {
        currentTags.contains { FeedTags.equal($0, tag) }
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
                }
                if !store.allTags.isEmpty {
                    Section("Tags") {
                        ForEach(store.allTags, id: \.self) { tag in
                            Button {
                                if hasTag(tag) {
                                    store.removeTag(tag, from: feedId)
                                } else {
                                    store.addTag(tag, to: feedId)
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
            .navigationTitle(feedTitle)
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
        store.addTag(newTag, to: feedId)
        newTag = ""
    }
}
