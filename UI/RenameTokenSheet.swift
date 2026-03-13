import SwiftUI

struct RenameTokenSheet: View {
    @Environment(\.presentationMode) private var presentation

    let originalIssuer: String
    let originalAccount: String
    let onSave: (String, String) -> Void

    @State private var issuer: String
    @State private var account: String

    init(originalIssuer: String, originalAccount: String, onSave: @escaping (String, String) -> Void) {
        self.originalIssuer = originalIssuer
        self.originalAccount = originalAccount
        self.onSave = onSave
        _issuer = State(initialValue: originalIssuer)
        _account = State(initialValue: originalAccount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Переименовать").font(.headline)

            VStack(alignment: .leading) {
                Text("Issuer").font(.caption).foregroundColor(.secondary)
                TextField("напр. Google", text: $issuer)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.06)))
            }

            VStack(alignment: .leading) {
                Text("Account").font(.caption).foregroundColor(.secondary)
                TextField("напр. you@example.com", text: $account)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.06)))
            }

            HStack {
                Spacer()
                Button("Отмена") { presentation.wrappedValue.dismiss() }
                Button("Сохранить") {
                    onSave(issuer, account)
                    presentation.wrappedValue.dismiss()
                }
                .keyboardShortcut(.return)
            }
            .padding(.top, 6)
        }
        .padding(16)
        .frame(width: 420)
    }
}
