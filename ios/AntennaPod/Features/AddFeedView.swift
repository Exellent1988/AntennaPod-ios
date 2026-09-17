import SwiftUI

struct AddFeedView: View {
    @EnvironmentObject private var store: PodcastStore
    @Environment(\.dismiss) private var dismiss
    @State private var urlText = "https://"
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Feed URL") {
                    TextField("https://example.com/feed.xml", text: $urlText)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .focused($focused)
                }
                if let error = store.lastError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add podcast")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Subscribe") {
                        Task {
                            await store.subscribe(feedUrl: urlText.trimmingCharacters(in: .whitespacesAndNewlines))
                            if store.lastError == nil {
                                dismiss()
                            }
                        }
                    }
                    .disabled(store.isLoading || urlText.trimmingCharacters(in: .whitespacesAndNewlines).count < 8)
                }
            }
            .onAppear { focused = true }
        }
    }
}
