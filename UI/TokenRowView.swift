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

struct CopiedCode: Equatable {
    let id: UUID
    let code: String
}

struct TokenRowView: View {
    static let nextCodeThreshold = 5
    static let copiedFeedbackDuration: TimeInterval = 2.0
    private static let steamTint = Color(red: 0.4, green: 0.75, blue: 0.96)
    private static let codeChangeAnimation = Animation.spring(response: 0.35, dampingFraction: 0.8)

    let title: String
    let code: String?
    let nextCode: String?
    let digits: Int
    let remaining: Int
    let period: Int
    let playsSound: Bool
    let isSelected: Bool
    let externallyCopiedCode: String?
    let isLocked: Bool
    var kind: OTPKind = .totp
    var counter: UInt64? = nil
    var onAdvance: () -> Void = {}
    let onUnlock: () -> Void
    let onCopy: () -> Void

    @State private var copiedCode: String?
    @State private var hoveringRow = false
    @State private var hoveringNext = false
    @State private var hoveringCounter = false
    @State private var pulse = false

    // Цвет таймера
    private var timerColor: Color {
        if remaining <= 5 { return .red }
        if remaining <= 10 { return .orange }
        return .accentColor
    }

    private var showsCopied: Bool {
        copiedCode != nil || externallyCopiedCode != nil
    }

    private var shownCode: String? {
        externallyCopiedCode ?? copiedCode ?? code
    }

    private var targetsCurrentCode: Bool {
        hoveringRow && !hoveringNext && !hoveringCounter && (code != nil || isLocked)
    }

    private var currentCodeOpacity: Double {
        if showsCopied { return 0.35 }
        if hoveringNext { return 0.45 }
        return 1.0
    }

    private var rowFillOpacity: Double {
        if isSelected { return 0.12 }
        if targetsCurrentCode { return 0.10 }
        return 0.06
    }

    private var rowStrokeColor: Color {
        if isSelected { return Color.accentColor.opacity(0.8) }
        if targetsCurrentCode { return Color.white.opacity(0.16) }
        return Color.clear
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {

                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(title)

                    switch kind {
                    case .hotp:
                        KindTag(text: "HOTP", tint: .purple, hint: "Counter-based code: changes when you use it or press ↻")
                    case .steam:
                        KindTag(text: "STEAM", tint: Self.steamTint, hint: "Steam Guard code")
                    case .totp:
                        EmptyView()
                    }
                }

                HStack(spacing: 8) {

                    if isLocked {
                        lockedCode
                    } else {
                        ZStack(alignment: .leading) {
                            Text(Self.grouped(shownCode ?? String(repeating: "-", count: digits)))
                                .font(.system(size: 20, weight: .medium, design: .monospaced))
                                .foregroundColor(shownCode == nil ? .secondary : .primary)
                                .opacity(currentCodeOpacity)
                                .id(shownCode)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }
                        .transition(.opacity)
                    }

                    if showsCopied {
                        Label("Copied", systemImage: "checkmark.circle.fill")
                            .labelStyle(.titleAndIcon)
                            .foregroundColor(.green)
                            .font(.system(size: 12, weight: .semibold))
                            .transition(.opacity.combined(with: .scale))
                    } else if let nextCode, !isLocked {
                        NextCodeChip(
                            code: nextCode,
                            playsSound: playsSound,
                            hovering: $hoveringNext,
                            onCopy: onCopy
                        )
                        .id(nextCode)
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .opacity
                        ))
                    }
                }
                .animation(Self.codeChangeAnimation, value: shownCode)
                .animation(Self.codeChangeAnimation, value: nextCode)
                .animation(.easeInOut(duration: 0.2), value: isLocked)
                .animation(.easeInOut(duration: 0.15), value: hoveringNext)
            }

            Spacer()

            if let counter {
                counterBadge(counter)
            } else {
                timerRing
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(rowFillOpacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(rowStrokeColor, lineWidth: isSelected ? 1.5 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hoveringRow = $0 }
        .onTapGesture(perform: copyCurrent)
        .accessibilityAddTraits(.isButton)
        .animation(.easeInOut(duration: 0.2), value: showsCopied)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .animation(.easeInOut(duration: 0.15), value: targetsCurrentCode)

        // Пульсация только в последние секунды
        .onAppear {
            startPulse()
        }
        .onChange(of: remaining) { _ in
            startPulse()
        }
        .onChange(of: nextCode) { next in
            if next == nil { hoveringNext = false }
        }
    }

    private var timerRing: some View {
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

    @ViewBuilder
    private func counterBadge(_ value: UInt64) -> some View {
        let badge = VStack(spacing: 1) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 10, weight: .bold))
            Text("#\(value)")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .foregroundColor(hoveringCounter ? .primary : .secondary)
        .frame(width: 34, height: 34)
        .background(
            Circle().fill(hoveringCounter ? Color.accentColor.opacity(0.28) : Color.white.opacity(0.08))
        )
        .overlay(
            Circle().strokeBorder(hoveringCounter ? Color.accentColor.opacity(0.8) : Color.clear, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.15), value: hoveringCounter)

        if isLocked {
            badge
        } else {
            badge
                .contentShape(Circle())
                .onHover { hoveringCounter = $0 }
                .onTapGesture(perform: onAdvance)
                .accessibilityAddTraits(.isButton)
                .help("Show the next code (counter \(value))")
        }
    }

    private var lockedCode: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 12, weight: .semibold))
            Text(Self.grouped(String(repeating: "•", count: digits)))
                .font(.system(size: 20, weight: .medium, design: .monospaced))
        }
        .foregroundColor(targetsCurrentCode ? .primary : .secondary)
        .help("Use Touch ID to show and copy the code")
        .transition(.opacity)
    }

    private func startPulse() {
        guard counter == nil, remaining <= 5 else {
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
        if isLocked {
            onUnlock()
            return
        }
        guard let code else { return }
        CodeClipboard.copy(code, playSound: playsSound)
        copiedCode = code
        onCopy()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.copiedFeedbackDuration) {
            withAnimation {
                if copiedCode == code { copiedCode = nil }
            }
        }
    }

    static func grouped(_ code: String) -> String {
        guard code.count >= 6, code.count % 2 == 0 else { return code }
        let middle = code.index(code.startIndex, offsetBy: code.count / 2)
        return String(code[..<middle]) + " " + String(code[middle...])
    }
}

private struct KindTag: View {
    let text: String
    let tint: Color
    let hint: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .tracking(0.4)
            .foregroundColor(tint)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(tint.opacity(0.16)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.4), lineWidth: 0.5))
            .fixedSize()
            .help(hint)
    }
}

private struct NextCodeChip: View {
    let code: String
    let playsSound: Bool
    @Binding var hovering: Bool
    let onCopy: () -> Void

    @State private var copied = false
    @State private var glintPhase: CGFloat = 0

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: copied ? "checkmark" : "arrow.right")
                .font(.system(size: 9, weight: .bold))
            Text(copied ? "Copied next" : "Next")
                .font(.system(size: 9, weight: .bold))
                .textCase(.uppercase)
            if !copied {
                Text(TokenRowView.grouped(code))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
            }
        }
        .foregroundColor(copied ? .green : (hovering ? .primary : .secondary))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(hovering ? Color.accentColor.opacity(0.28) : Color.white.opacity(0.08))
        )
        .overlay(
            Capsule().strokeBorder(hovering ? Color.accentColor.opacity(0.8) : Color.clear, lineWidth: 1)
        )
        .overlay(glint)
        .contentShape(Capsule())
        .onHover { hovering = $0 }
        .onTapGesture(perform: copy)
        .accessibilityAddTraits(.isButton)
        .help("Copy the next code")
        .animation(.easeInOut(duration: 0.15), value: hovering)
        .animation(.easeInOut(duration: 0.2), value: copied)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).delay(0.35)) {
                glintPhase = 1
            }
        }
    }

    private var glint: some View {
        GeometryReader { geometry in
            LinearGradient(
                colors: [Color.white.opacity(0), Color.white.opacity(0.65), Color.white.opacity(0)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: geometry.size.width * 0.45)
            .offset(x: -geometry.size.width * 0.45 + glintPhase * geometry.size.width * 1.45)
        }
        .clipShape(Capsule())
        .allowsHitTesting(false)
    }

    private func copy() {
        CodeClipboard.copy(code, playSound: playsSound)
        onCopy()
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + TokenRowView.copiedFeedbackDuration) {
            withAnimation {
                copied = false
            }
        }
    }
}
