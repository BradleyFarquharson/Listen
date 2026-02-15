import Foundation

/// A single vocabulary entry: the correct term plus optional aliases (common misheard variants).
struct VocabEntry: Codable, Identifiable, Equatable {
    let id: UUID
    var term: String          // The correct form, e.g. "GigaIO"
    var aliases: [String]     // Misheard variants, e.g. ["giga io", "gigayo"]

    init(term: String, aliases: [String] = []) {
        self.id = UUID()
        self.term = term
        self.aliases = aliases
    }
}

/// Custom vocabulary store with post-transcription correction.
/// Persisted as JSON in UserDefaults. Correction runs as a simple string replacement
/// loop — O(n) where n = total aliases, microseconds for typical lists.
final class Vocabulary: ObservableObject {
    @Published var entries: [VocabEntry] = [] {
        didSet { save() }
    }

    private let defaults = UserDefaults.standard
    private let key = "vocabulary.entries"

    init() {
        load()
    }

    // MARK: - Correction (called on every transcription result)

    /// Apply vocabulary corrections to transcribed text.
    /// Replaces aliases with their correct term (case-insensitive),
    /// and enforces correct casing of the term itself.
    func correct(_ text: String) -> String {
        guard !entries.isEmpty else { return text }

        var result = text
        for entry in entries {
            // Replace each alias with the correct term (case-insensitive, whole word boundaries)
            for alias in entry.aliases where !alias.isEmpty {
                result = result.replacingOccurrences(
                    of: "\\b\(NSRegularExpression.escapedPattern(for: alias))\\b",
                    with: entry.term,
                    options: [.regularExpression, .caseInsensitive]
                )
            }
            // Also enforce correct casing of the term itself
            // e.g. "gigaio" → "GigaIO" even if not listed as an alias
            result = result.replacingOccurrences(
                of: "\\b\(NSRegularExpression.escapedPattern(for: entry.term))\\b",
                with: entry.term,
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return result
    }

    // MARK: - CRUD

    func add(term: String, aliases: [String] = []) {
        entries.append(VocabEntry(term: term, aliases: aliases))
    }

    func remove(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
    }

    func update(_ entry: VocabEntry) {
        if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[idx] = entry
        }
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([VocabEntry].self, from: data) else {
            return
        }
        entries = decoded
    }
}
