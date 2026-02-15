import SwiftUI

/// Vocabulary management view — add, edit, and remove custom terms.
struct VocabularyView: View {
    @ObservedObject var vocabulary: Vocabulary
    @State private var newTerm = ""
    @State private var newAliases = ""
    @State private var editingEntry: VocabEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            Text("Vocabulary")
                .font(.subheadline)
                .fontWeight(.semibold)

            Text("Add custom words to improve transcription accuracy. Aliases are common misheard variants.")
                .font(.caption)
                .foregroundColor(.secondary)

            // Add new entry
            addEntryRow

            Divider()

            // Entry list
            if vocabulary.entries.isEmpty {
                Text("No vocabulary entries yet.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(vocabulary.entries) { entry in
                            entryRow(entry)
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
    }

    // MARK: - Add Entry Row

    private var addEntryRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                TextField("Term (e.g. GigaIO)", text: $newTerm)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)

                Button {
                    addEntry()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            TextField("Aliases: giga io, gigayo (comma-separated)", text: $newAliases)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
        }
    }

    // MARK: - Entry Row

    private func entryRow(_ entry: VocabEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.term)
                    .font(.callout)
                    .fontWeight(.medium)

                if !entry.aliases.isEmpty {
                    Text(entry.aliases.joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button {
                if let idx = vocabulary.entries.firstIndex(where: { $0.id == entry.id }) {
                    vocabulary.remove(at: IndexSet(integer: idx))
                }
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(6)
    }

    // MARK: - Actions

    private func addEntry() {
        let term = newTerm.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return }

        let aliases = newAliases
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        vocabulary.add(term: term, aliases: aliases)
        newTerm = ""
        newAliases = ""
    }
}
