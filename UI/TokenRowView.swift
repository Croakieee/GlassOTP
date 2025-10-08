import SwiftUI
import AppKit

struct TokenRowView: View {
    let title: String
    let code: String
    let remaining: Int
    let period: Int
    let onCopy: () -> Void

    @State private var copied = false

    var body: some View {
        Button(action: copyAction) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)

                    HStack(spacing: 8) {
                        Text(code)
                            .font(.system(size: 20, weight: .medium, design: .monospaced))
                            .foregroundColor(.primary)
                            .opacity(copied ? 0.35 : 1.0)

                        if copied {
                            Label("Скопировано", systemImage: "checkmark.circle.fill")
                                .labelStyle(.titleAndIcon)
                                .foregroundColor(.green)
                                .font(.system(size: 12, weight: .semibold))
                                .transition(.opacity.combined(with: .scale))
                        }
                    }
                }

                Spacer()

                // Примитивный таймер-кольцо
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 4)
                        .frame(width: 26, height: 26)
                    Circle()
                        .trim(from: 0, to: CGFloat(max(0.0, Double(remaining) / Double(period))))
                        .rotation(Angle(degrees: -90))
                        .stroke(Color.accentColor.opacity(0.9), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 26, height: 26)
                    Text("\(remaining)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
        }
        .buttonStyle(PlainButtonStyle())
        .animation(.easeInOut(duration: 0.2), value: copied)
    }

    private func copyAction() {
        // Копируем в буфер
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(code, forType: .string)

        // Обратная связь: анимация + системный звук (по желанию)
        onCopy()
        copied = true
        NSSound(named: NSSound.Name("Pop"))?.play()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation { copied = false }
        }
    }
}
