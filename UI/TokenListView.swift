import SwiftUI

struct TokenListView: View {
    @ObservedObject var store: OTPStore
    @ObservedObject var timer: TimeStepTimer
    @Binding var autoCloseOnCopy: Bool

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
            ScrollView {
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
                // Reserve a lane on the right for the overlay scroll indicator so it sits
                // in its own gutter instead of overlapping the token rows. (.scrollIndicators
                // would be cleaner but is macOS 13+; this stays compatible with 11.7.)
                .padding(.vertical, 2)
                .padding(.trailing, 12)
            }
        }
    }

}
