import SwiftUI
import AppKit

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
                            copyToClipboard(store.code(for: token))

                            if autoCloseOnCopy {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                    NSApp.keyWindow?.performClose(nil)
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
                .padding(.vertical, 2)
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}
