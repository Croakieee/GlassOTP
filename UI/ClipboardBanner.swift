import SwiftUI

struct ClipboardBanner: View {
    let offer: ClipboardOffer
    let onAdd: () -> Void
    let onCheck: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
            Text(message)
                .font(.footnote)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            actions
        }
        .foregroundColor(color)
        .padding(.horizontal, 6)
    }

    @ViewBuilder
    private var actions: some View {
        switch offer {
        case .accounts:
            actionButton("Add", action: onAdd)
            dismissButton
        case .check:
            actionButton("Check", action: onCheck)
            dismissButton
        case .nothingFound, .added:
            EmptyView()
        }
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(BorderlessButtonStyle())
            .font(.footnote)
            .foregroundColor(.accentColor)
    }

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .semibold))
        }
        .buttonStyle(BorderlessButtonStyle())
        .foregroundColor(.secondary)
        .help("Hide until the clipboard changes")
    }

    private var icon: String {
        switch offer {
        case .added: return "checkmark.circle.fill"
        default: return "doc.on.clipboard"
        }
    }

    private var color: Color {
        if case .added = offer { return .green }
        return .secondary
    }

    private var message: String {
        switch offer {
        case .accounts(let title): return "Clipboard has \(title)."
        case .check: return "The clipboard may hold an account link."
        case .nothingFound: return "No account link in the clipboard."
        case .added(let title, let cleared): return cleared ? "Added \(title). Clipboard cleared." : "Added \(title)."
        }
    }
}
