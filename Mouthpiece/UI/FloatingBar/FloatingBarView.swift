import SwiftUI

struct FloatingBarView: View {
    @Bindable var state: FloatingBarState

    var body: some View {
        Group {
            switch state.kind {
            case .idle:
                EmptyView()
            case .recording(let elapsed, let levels, let partial):
                recordingPill(elapsed: elapsed, levels: levels, partial: partial)
            case .processing(let partial):
                processingPill(partial: partial)
            case .done(let n):
                donePill(chars: n)
            case .error(let msg):
                errorPill(message: msg)
            }
        }
        .animation(.snappy(duration: 0.2), value: state.kind)
    }

    private func recordingPill(elapsed: TimeInterval, levels: [Float], partial: String) -> some View {
        pill {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
            if partial.isEmpty {
                Text("听着呢")
            } else {
                Text(partial)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: 360, alignment: .trailing)
            }
            waveform(levels: levels)
            timer(elapsed: elapsed)
        }
    }

    private func processingPill(partial: String) -> some View {
        pill {
            ProgressView().controlSize(.small).tint(.white)
            if partial.isEmpty {
                Text("润色中…")
            } else {
                Text(partial)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: 360, alignment: .trailing)
            }
        }
    }

    private func donePill(chars: Int) -> some View {
        pill {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("已粘贴 \(chars) 字")
        }
    }

    private func errorPill(message: String) -> some View {
        pill {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
        }
    }

    private func waveform(levels: [Float]) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(levels.suffix(12).enumerated()), id: \.offset) { _, v in
                Capsule()
                    .fill(.white)
                    .frame(width: 2, height: max(4, CGFloat(v) * 16))
            }
        }
        .frame(width: 36, height: 16)
    }

    private func timer(elapsed: TimeInterval) -> some View {
        let mm = Int(elapsed) / 60
        let ss = Int(elapsed) % 60
        return Text(String(format: "%d:%02d", mm, ss))
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(0.7))
    }

    @ViewBuilder
    private func pill<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) {
            content()
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(.black.opacity(0.85))
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.1), lineWidth: 0.5)
                }
        }
        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
    }
}

#Preview("recording") {
    let s = FloatingBarState()
    s.kind = .recording(elapsed: 3, levels: [0.2, 0.4, 0.6, 0.8, 0.5, 0.3], partial: "今天天气真好")
    return FloatingBarView(state: s).padding(40).background(.gray.opacity(0.2))
}

#Preview("processing") {
    let s = FloatingBarState()
    s.kind = .processing(partial: "今天天气真好")
    return FloatingBarView(state: s).padding(40).background(.gray.opacity(0.2))
}

#Preview("done") {
    let s = FloatingBarState()
    s.kind = .done(chars: 42)
    return FloatingBarView(state: s).padding(40).background(.gray.opacity(0.2))
}

#Preview("error") {
    let s = FloatingBarState()
    s.kind = .error("麦克风丢失")
    return FloatingBarView(state: s).padding(40).background(.gray.opacity(0.2))
}
