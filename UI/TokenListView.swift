import SwiftUI

/// Frame of the scrolled content in the scroll view's coordinate space
/// (minY goes negative as the list scrolls down).
private struct ScrollContentFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        // Siblings that don't set the key contribute the default (.zero); taking the last
        // value blindly would overwrite the real frame with it.
        let next = nextValue()
        if next != .zero { value = next }
    }
}

struct TokenListView: View {
    @ObservedObject var store: OTPStore
    @ObservedObject var timer: TimeStepTimer
    @Binding var autoCloseOnCopy: Bool

    // Drives the custom scroll indicator.
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
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "qrcode")
                    .font(.system(size: 44))
                    .foregroundColor(.secondary)
                Text("No tokens yet")
                    .font(.callout)
                    .foregroundColor(.secondary)
                Text("Tap “+” and add an otpauth:// link or import a QR code.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                Spacer()
            }
        } else {
            GeometryReader { viewport in
            // The system scroller is hidden: its width depends on the user's "Show scroll
            // bars" setting / connected mouse and can't be styled from SwiftUI on macOS 11
            // (.scrollIndicators is 13+). A fixed thin indicator is drawn as an overlay instead.
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 10) {
                    ForEach(items) { token in
                        TokenRowView(
                            title: token.displayTitle,
                            code: store.code(for: token),
                            remaining: store.remaining(for: token),
                            period: token.period
                        ) {
                            if autoCloseOnCopy {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                    NotificationCenter.default.post(name: .autoClosePopover, object: nil)
                                }
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
                    }
                }
                // Narrow right gutter for the custom indicator. Bottom padding gives the last
                // row breathing room now that the list runs to the popover's bottom edge.
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
            }
        }
    }

    // MARK: - Scroll indicator

    /// Thin, fixed-width indicator shown only when the list overflows. Display-only
    /// (scrolling is by wheel / trackpad), so it never intercepts clicks.
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
