import SwiftUI

struct QuickAddBanner: View {
    let feedback: QuickAddFeedback
    let showsDetails: Bool
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
            Text(showsDetails ? feedback.message : feedback.lockedMessage)
                .font(.footnote)
                .lineLimit(2)
            Spacer(minLength: 4)
            if feedback.kind == .permission {
                Button("Open Settings", action: onOpenSettings)
                    .buttonStyle(BorderlessButtonStyle())
                    .font(.footnote)
                    .foregroundColor(.accentColor)
            }
        }
        .foregroundColor(feedback.kind == .success ? .green : .secondary)
        .padding(.horizontal, 6)
    }

    private var icon: String {
        switch feedback.kind {
        case .success: return "checkmark.circle.fill"
        case .info: return "qrcode.viewfinder"
        case .permission: return "lock.shield"
        }
    }
}
