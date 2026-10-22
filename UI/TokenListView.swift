import SwiftUI

private struct ScrollContentFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

struct TokenListView: View {
    @ObservedObject var store: OTPStore
    @ObservedObject var timer: TimeStepTimer
    @Binding var autoCloseOnCopy: Bool
    let playsCopySound: Bool
    let selectedID: UUID?
    let keyboardCopiedID: UUID?

    @State private var contentFrame: CGRect = .zero

    private let scrollSpace = "tokenScroll"

    let onPin: (UUID) -> Void
    let onRename: (UUID) -> Void
    let onEditSecret: (UUID) -> Void
    let onDelete: (UUID) -> Void
    let onShowQR: (UUID) -> Void

    var body: some View {
        let items = store.filteredTokens()

        if items.isEmpty {
            if store.tokens.isEmpty {
                emptyState(
                    icon: "qrcode",
                    title: "No tokens yet",
                    hint: "Tap “+” and add an otpauth:// link or import a QR code."
                )
            } else {
                emptyState(
                    icon: "magnifyingglass",
                    title: "No matches",
                    hint: "No account matches “\(store.query.trimmingCharacters(in: .whitespacesAndNewlines))”."
                )
            }
        } else {
            GeometryReader { viewport in
            ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 10) {
                    ForEach(items) { token in
                        let remaining = store.remaining(for: token)
                        TokenRowView(
                            title: token.displayTitle,
                            code: store.code(for: token),
                            nextCode: remaining <= TokenRowView.nextCodeThreshold ? store.nextCode(for: token) : nil,
                            digits: token.digits,
                            remaining: remaining,
                            period: token.period,
                            playsSound: playsCopySound,
                            isSelected: token.id == selectedID,
                            copiedExternally: token.id == keyboardCopiedID
                        ) {
                            if autoCloseOnCopy {
                                NotificationCenter.default.post(name: .autoClosePopover, object: nil)
                            }
                        }
                        .contextMenu {
                            Button(token.isPinned ? "Unpin" : "Pin") {
                                onPin(token.id)
                            }

                            Button("Rename…") {
                                onRename(token.id)
                            }
                            
                            Button("Show QR code") {
                                onShowQR(token.id)
                            }

                            Button("Show / edit secret…") {
                                onEditSecret(token.id)
                            }

                            Divider()

                            Button("Delete") {
                                onDelete(token.id)
                            }
                        }
                        .id(token.id)
                    }
                }
                .padding(.top, 2)
                .padding(.bottom, 6)
                .padding(.trailing, 8)
                .background(
                    GeometryReader { content in
                        Color.clear.preference(
                            key: ScrollContentFrameKey.self,
                            value: content.frame(in: .named(scrollSpace))
                        )
                    }
                )
            }
            .coordinateSpace(name: scrollSpace)
            .onPreferenceChange(ScrollContentFrameKey.self) { contentFrame = $0 }
            .overlay(
                scrollIndicator(viewportHeight: viewport.size.height),
                alignment: .topTrailing
            )
            .onChange(of: selectedID) { id in
                guard let id else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    proxy.scrollTo(id)
                }
            }
            }
            }
        }
    }

    private func emptyState(icon: String, title: String, hint: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text(title)
                .font(.callout)
                .foregroundColor(.secondary)
            Text(hint)
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            Spacer()
        }
    }

    @ViewBuilder
    private func scrollIndicator(viewportHeight: CGFloat) -> some View {
        let contentHeight = contentFrame.height
        if viewportHeight > 0, contentHeight > viewportHeight + 1 {
            let inset: CGFloat = 3
            let track = viewportHeight - inset * 2
            let thumb = max(24, track * viewportHeight / contentHeight)
            let maxOffset = contentHeight - viewportHeight
            let progress = min(max(-contentFrame.minY / maxOffset, 0), 1)

            Capsule()
                .fill(Color.primary.opacity(0.35))
                .frame(width: 3, height: thumb)
                .offset(y: inset + progress * (track - thumb))
                .padding(.trailing, 2)
                .allowsHitTesting(false)
        }
    }

}
