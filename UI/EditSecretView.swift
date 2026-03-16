import SwiftUI

struct EditSecretView: View {

    let token: OTPToken
    @ObservedObject var store: OTPStore
    let onClose: () -> Void

    @State private var secret: String = ""
    @State private var errorMessage: String?
    
    var body: some View {

        VStack(alignment: .leading, spacing: 12) {

            Text("Секрет токена")
                .font(.title3)

            TextField("Base32 секрет", text: $secret)
                .font(.system(.body, design: .monospaced))

            if let errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.footnote)
            }

            HStack {

                Button("Отмена") {
                    onClose()
                }

                Spacer()

                Button("Сохранить") {

                    do {
                        try store.updateSecret(for: token, base32: secret)
                        onClose()
                    } catch {
                        errorMessage = "Неверный Base32"
                    }

                }

            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            secret = store.secret(for: token) ?? ""
        }
    }
}
