import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

struct TokenQRView: View {

    let token: OTPToken
    @ObservedObject var store: OTPStore
    let onClose: () -> Void

    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    var body: some View {

        VStack(spacing: 16) {

            Text("Token QR code")
                .font(.title3)

            if let image = generateQR() {

                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 220, height: 220)

            }

            Text(token.displayTitle)
                .font(.footnote)
                .foregroundColor(.secondary)

            Button("Close") {
                onClose()
            }

        }
        .padding(24)
        .frame(width: 300)
    }

    private func generateQR() -> NSImage? {
        guard let secret = store.secret(for: token) else { return nil }

        // Label path components must encode `:` (issuer:account separator) and `/` (path separator).
        var labelCharSet = CharacterSet.urlQueryAllowed
        labelCharSet.remove(charactersIn: ":/")

        let issuerEncoded  = token.issuer.addingPercentEncoding(withAllowedCharacters: labelCharSet) ?? ""
        let accountEncoded = token.account.addingPercentEncoding(withAllowedCharacters: labelCharSet) ?? ""

        let label: String
        if issuerEncoded.isEmpty {
            label = accountEncoded
        } else if accountEncoded.isEmpty {
            label = issuerEncoded
        } else {
            label = "\(issuerEncoded):\(accountEncoded)"
        }

        let issuerQuery = token.issuer.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let url = "otpauth://totp/\(label)?secret=\(secret)&issuer=\(issuerQuery)&period=\(token.period)&digits=\(token.digits)"

        filter.setValue(Data(url.utf8), forKey: "inputMessage")

        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgimg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgimg, size: .zero)
    }

}
