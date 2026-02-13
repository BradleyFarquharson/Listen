import SwiftUI

/// Observable store for audio levels — fed from AudioCaptureService on main thread.
final class AudioLevelStore: ObservableObject {
    @Published var levels: [CGFloat] = Array(repeating: 0, count: 28)

    func push(_ rms: Float) {
        // Lower divisor so normal speech easily reaches upper range
        let normalized = CGFloat(min(rms / 0.06, 1.0))
        // Power curve: quiet stays tiny, loud gets big — more dramatic movement
        let curved = pow(normalized, 0.6)
        let final_ = max(curved, 0.04)

        levels.append(final_)
        if levels.count > 28 {
            levels.removeFirst(levels.count - 28)
        }
    }

    func reset() {
        levels = Array(repeating: 0, count: 28)
    }
}

/// The floating pill content — shows a dynamic waveform during recording.
struct RecordingPillView: View {
    @ObservedObject var levelStore: AudioLevelStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(Array(levelStore.levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(colorScheme == .dark ? Color.white : Color.black)
                    .frame(width: 2.5, height: barHeight(for: level))
                    .animation(.easeOut(duration: 0.08), value: level)
            }
        }
        .frame(height: 20)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
        )
    }

    private func barHeight(for level: CGFloat) -> CGFloat {
        let minH: CGFloat = 2
        let maxH: CGFloat = 18
        return minH + (maxH - minH) * level
    }
}
