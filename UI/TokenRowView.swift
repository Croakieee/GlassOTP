import SwiftUI
import AppKit

enum CodeClipboard {
    static func copy(_ code: String, playSound: Bool) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(code, forType: .string)
        pb.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))

        if playSound {
            NSSound(named: NSSound.Name("Pop"))?.play()
        }
    }
}

struct TokenRowView: View {
    static let nextCodeThreshold = 5
    private static let copiedFeedbackDuration: TimeInterval = 2.0
    private static let codeChangeAnimation = Animation.spring(response: 0.35, dampingFraction: 0.8)

    let title: String
    let code: String?
    let nextCode: String?
    let digits: Int
    let remaining: Int
    let period: Int
    let playsSound: Bool
    let isSelected: Bool
    let copiedExternally: Bool
    let onCopy: () -> Void

    @State private var copied = false
    @State private var copiedNext = false
    @State private var hoveringNext = false
    @State private var pulse = false

    // Цвет таймера
    private var timerColor: Color {
        if remaining <= 5 { return .red }
        if remaining <= 10 { return .orange }
        return .accentColor
    }

    private var showsCopied: Bool {
        copied || copiedExternally
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(title)

                HStack(spacing: 8) {

                    ZStack(alignment: .leading) {
                        Text(Self.grouped(code ?? String(repeating: "-", count: digits)))
                            .font(.system(size: 20, weight: .medium, design: .monospaced))
                            .foregroundColor(code == nil ? .secondary : .primary)
                            .opacity(showsCopied ? 0.35 : 1.0)
                            .id(code)
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }

                    if showsCopied {
                        Label("Copied", systemImage: "checkmark.circle.fill")
                            .labelStyle(.titleAndIcon)
                            .foregroundColor(.green)
                            .font(.system(size: 12, weight: .semibold))
                            .transition(.opacity.combined(with: .scale))
                    } else if let nextCode {
                        nextCodeChip(nextCode)
                    }
                }
                .animation(Self.codeChangeAnimation, value: code)
                .animation(Self.codeChangeAnimation, value: nextCode)
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
                .fill(Color.white.opacity(isSelected ? 0.12 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.accentColor.opacity(isSelected ? 0.8 : 0), lineWidth: 1.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture(perform: copyCurrent)
        .accessibilityAddTraits(.isButton)
        .animation(.easeInOut(duration: 0.2), value: showsCopied)
        .animation(.easeInOut(duration: 0.15), value: isSelected)

        // Пульсация только в последние секунды
        .onAppear {
            startPulse()
        }
        .onChange(of: remaining) { _ in
            startPulse()
        }
    }

    private func nextCodeChip(_ next: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: copiedNext ? "checkmark" : "arrow.right")
                .font(.system(size: 9, weight: .bold))
            Text(copiedNext ? "Copied" : Self.grouped(next))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
        }
        .foregroundColor(copiedNext ? .green : (hoveringNext ? .primary : .secondary))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(Color.white.opacity(hoveringNext ? 0.16 : 0.08))
        )
        .contentShape(Capsule())
        .onHover { hoveringNext = $0 }
        .onTapGesture { copyNext(next) }
        .accessibilityAddTraits(.isButton)
        .help("Next code — copy it to use right away")
        .animation(.easeInOut(duration: 0.15), value: hoveringNext)
        .animation(.easeInOut(duration: 0.2), value: copiedNext)
        .transition(.asymmetric(
            insertion: .move(edge: .leading).combined(with: .opacity),
            removal: .opacity
        ))
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

    private func copyCurrent() {
        guard let code else { return }
        CodeClipboard.copy(code, playSound: playsSound)
        onCopy()
        flash($copied)
    }

    private func copyNext(_ next: String) {
        CodeClipboard.copy(next, playSound: playsSound)
        onCopy()
        flash($copiedNext)
    }

    private func flash(_ flag: Binding<Bool>) {
        flag.wrappedValue = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.copiedFeedbackDuration) {
            withAnimation {
                flag.wrappedValue = false
            }
        }
    }

    private static func grouped(_ code: String) -> String {
        guard code.count >= 6, code.count % 2 == 0 else { return code }
        let middle = code.index(code.startIndex, offsetBy: code.count / 2)
        return String(code[..<middle]) + " " + String(code[middle...])
    }
}
