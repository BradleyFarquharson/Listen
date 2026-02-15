import Foundation

/// Tracks usage statistics — words per minute, total words, time saved.
/// Backed by UserDefaults for lightweight persistence. Weekly auto-reset.
final class UsageStats: ObservableObject {
    private let defaults = UserDefaults.standard

    // MARK: - Keys
    private enum Key {
        static let totalWords = "stats.totalWords"
        static let totalRecordingSeconds = "stats.totalRecordingSeconds"
        static let totalSessions = "stats.totalSessions"
        static let weekStart = "stats.weekStart"
    }

    // MARK: - Assumed typing speed for "time saved" calculation
    /// Average typing speed in words per minute (used as baseline).
    private let typingWPM: Double = 40

    init() {
        resetWeekIfNeeded()
    }

    // MARK: - Record a transcription (called from AppState after each successful transcription)

    /// Record stats for a completed transcription.
    /// - Parameters:
    ///   - wordCount: Number of words in the transcribed text.
    ///   - durationSeconds: Audio duration in seconds (samples / 16000).
    func recordTranscription(wordCount: Int, durationSeconds: Double) {
        resetWeekIfNeeded()
        defaults.set(totalWords + wordCount, forKey: Key.totalWords)
        defaults.set(totalRecordingSeconds + durationSeconds, forKey: Key.totalRecordingSeconds)
        defaults.set(totalSessions + 1, forKey: Key.totalSessions)
        objectWillChange.send()
    }

    // MARK: - Computed Stats

    /// Total words transcribed this week.
    var wordsThisWeek: Int {
        defaults.integer(forKey: Key.totalWords)
    }

    /// Average words per minute across all sessions this week.
    var averageWPM: Int {
        let seconds = totalRecordingSeconds
        guard seconds > 0 else { return 0 }
        return Int(round(Double(totalWords) / seconds * 60))
    }

    /// Estimated minutes saved this week (speech vs typing at 40 WPM).
    var timeSavedMinutes: Int {
        let words = Double(totalWords)
        guard words > 0 else { return 0 }
        let typingMinutes = words / typingWPM
        let speakingMinutes = totalRecordingSeconds / 60.0
        let saved = typingMinutes - speakingMinutes
        return max(0, Int(round(saved)))
    }

    /// Number of transcription sessions this week.
    var sessionsThisWeek: Int {
        defaults.integer(forKey: Key.totalSessions)
    }

    // MARK: - Internal

    private var totalWords: Int {
        defaults.integer(forKey: Key.totalWords)
    }

    private var totalRecordingSeconds: Double {
        defaults.double(forKey: Key.totalRecordingSeconds)
    }

    private var totalSessions: Int {
        defaults.integer(forKey: Key.totalSessions)
    }

    // MARK: - Weekly Reset

    /// Reset counters if the current week has rolled over (Monday-based).
    private func resetWeekIfNeeded() {
        let calendar = Calendar.current
        let now = Date()
        let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now

        if let stored = defaults.string(forKey: Key.weekStart),
           let storedDate = ISO8601DateFormatter().date(from: stored) {
            // Same week — no reset needed
            if calendar.isDate(storedDate, equalTo: currentWeekStart, toGranularity: .weekOfYear) {
                return
            }
        }

        // New week or first launch — reset
        defaults.set(ISO8601DateFormatter().string(from: currentWeekStart), forKey: Key.weekStart)
        defaults.set(0, forKey: Key.totalWords)
        defaults.set(0.0, forKey: Key.totalRecordingSeconds)
        defaults.set(0, forKey: Key.totalSessions)
    }
}
