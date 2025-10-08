import SwiftUI
import AppKit

struct TokenListView: View {
    @ObservedObject var store: OTPStore
    @ObservedObject var timer: TimeStepTimer
    @Binding var autoCloseOnCopy: Bool

    // колбэки для действий
    let onPin: (UUID) -> Void
    let onRename: (UUID) -> Void
    let onDelete: (UUID) -> Void

    var body: some View {
        let items = store.filteredTokens()

        if items.isEmpty {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "qrcode")
                    .font(.system(size: 44))
                    .foregroundColor(.secondary)
                Text("Пока нет токенов")
                    .font(.callout)
                    .foregroundColor(.secondary)
                Text("Нажми “+” и добавь otpauth:// ссылку или импортируй QR.")
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
                            if autoCloseOnCopy { NSApp.keyWindow?.performClose(nil) }
                        }
                        .contextMenu {
                            Button(token.isPinned ? "Открепить" : "Закрепить") {
                                onPin(token.id)
                            }
                            Button("Переименовать…") {
                                onRename(token.id)
                            }
                            Divider()
                            Button("Удалить") {
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
