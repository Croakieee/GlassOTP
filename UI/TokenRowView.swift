import SwiftUI
import AppKit

struct TokenRowView: View, Equatable {
    let title: String
    let code: String
    let remaining: Int
    let period: Int
    let onCopy: () -> Void

    @State private var copied = false
    @State private var pulse = false

    // Цвет таймера
    private var timerColor: Color {
        if remaining <= 5 { return .red }
        if remaining <= 10 { return .orange }
        return .accentColor
    }

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

                // Красивый таймер
                ZStack {

                    Circle()
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 4)
                        .frame(width: 26, height: 26)

                    Circle()
                        .trim(from: 0, to: CGFloat(max(0.0, Double(remaining) / Double(period))))
                        .rotation(.degrees(-90))
                        .stroke(
                            timerColor,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 26, height: 26)
                        .scaleEffect(pulse && remaining <= 5 ? 1.12 : 1.0)
                        .shadow(color: timerColor.opacity(remaining <= 5 ? 0.8 : 0),
                                radius: remaining <= 5 ? 4 : 0)
                        .animation(.linear(duration: 1.0), value: remaining)

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

        // Пульсация только в последние секунды
        .onAppear {
            startPulse()
        }
        .onChange(of: remaining) { _ in
            startPulse()
        }
    }

    private func startPulse() {
        guard remaining <= 5 else {
            pulse = false
            return
        }

        withAnimation(
            .easeInOut(duration: 0.6)
            .repeatForever(autoreverses: true)
        ) {
            pulse = true
        }
    }

    private func copyAction() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(code, forType: .string)

        onCopy()
        copied = true

        NSSound(named: NSSound.Name("Pop"))?.play()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                copied = false
            }
        }
    }
    
    static func == (lhs: TokenRowView, rhs: TokenRowView) -> Bool {
        lhs.code == rhs.code &&
        lhs.remaining == rhs.remaining
    }
}
