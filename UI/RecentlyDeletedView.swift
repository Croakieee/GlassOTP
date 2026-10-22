import SwiftUI

struct RecentlyDeletedView: View {
    @ObservedObject var store: OTPStore
    let onClose: () -> Void

    @State private var pendingDeletion: TrashedToken?
    @State private var confirmEmpty: Bool = false

    private static let rowHeight: CGFloat = 54
    private static let rowSpacing: CGFloat = 8
    private static let maxListHeight: CGFloat = 260

    private var listHeight: CGFloat {
        let count = CGFloat(store.trash.count)
        return min(count * Self.rowHeight + (count - 1) * Self.rowSpacing, Self.maxListHeight)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recently Deleted")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Deleted tokens are kept here for 30 days, then removed for good.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if store.trash.isEmpty {
                Text("Nothing here.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ScrollView {
                    VStack(spacing: Self.rowSpacing) {
                        ForEach(store.trash) { item in
                            row(item)
                        }
                    }
                }
                .frame(height: listHeight)
                .alert(item: $pendingDeletion) { item in
                    Alert(
                        title: Text("Delete “\(item.token.displayTitle)” now?"),
                        message: Text("Its secret is removed from the Keychain and can't be restored."),
                        primaryButton: .destructive(Text("Delete")) { store.deletePermanently(item.id) },
                        secondaryButton: .cancel()
                    )
                }
            }

            HStack {
                Button("Empty") { confirmEmpty = true }
                    .disabled(store.trash.isEmpty)
                    .alert(isPresented: $confirmEmpty) {
                        Alert(
                            title: Text("Empty Recently Deleted?"),
                            message: Text("All \(store.trash.count) token(s) and their secrets are removed for good."),
                            primaryButton: .destructive(Text("Empty")) { store.emptyTrash() },
                            secondaryButton: .cancel()
                        )
                    }
                Spacer()
                Button("Done", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func row(_ item: TrashedToken) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.token.displayTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(item.token.displayTitle)
                Text(removalText(for: item))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 8)

            Button("Restore") { store.restore(item.id) }

            Button(action: { pendingDeletion = item }) {
                Image(systemName: "trash")
            }
            .buttonStyle(BorderlessButtonStyle())
            .help("Delete now")
        }
        .padding(.horizontal, 10)
        .frame(height: Self.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }

    private func removalText(for item: TrashedToken) -> String {
        switch OTPStore.daysLeft(in: item, now: Date()) {
        case 0: return "Removed today"
        case 1: return "Removed tomorrow"
        case let days: return "Removed in \(days) days"
        }
    }
}
