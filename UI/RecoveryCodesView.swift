import SwiftUI

struct RecoveryCodesView: View {
    @ObservedObject var store: OTPStore
    let token: OTPToken
    let onClose: () -> Void

    @State private var codes: [RecoveryCode] = []
    @State private var loadFailed = false
    @State private var errorText: String?
    @State private var statusText: String?
    @State private var pasted: String = ""
    @State private var copiedID: UUID?
    @State private var pendingDeletion: RecoveryCode?

    private static let copiedFeedbackDuration: TimeInterval = 1.5
    private static let allCodesID = UUID()
    private static let rowHeight: CGFloat = 34
    private static let rowSpacing: CGFloat = 6
    private static let maxListHeight: CGFloat = 160

    private var unusedCodes: [RecoveryCode] { codes.filter { !$0.isUsed } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Recovery Codes")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(token.displayTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Text("Single-use codes from the site for when GlassOTP isn't at hand. Kept in the Keychain.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if loadFailed {
                Label("Couldn't read the recovery codes from the Keychain.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.footnote)
            } else {
                codeList
                addSection
            }

            if let errorText {
                Text(errorText)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button(copiedID == Self.allCodesID ? "Copied" : "Copy unused", action: copyUnused)
                    .disabled(loadFailed || unusedCodes.isEmpty)
                Spacer()
                Button("Done", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 340)
        .onAppear(perform: load)
    }

    private var codeList: some View {
        VStack(alignment: .leading, spacing: 6) {
            if codes.isEmpty {
                Text("No recovery codes yet. Paste them below.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ScrollView {
                    VStack(spacing: Self.rowSpacing) {
                        ForEach(codes) { code in
                            row(code)
                        }
                    }
                }
                .frame(height: listHeight)
                .alert(item: $pendingDeletion) { code in
                    Alert(
                        title: Text("Delete this recovery code?"),
                        message: Text("It is removed from the Keychain."),
                        primaryButton: .destructive(Text("Delete")) { delete(code) },
                        secondaryButton: .cancel()
                    )
                }

                Text("\(unusedCodes.count) of \(codes.count) left")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var listHeight: CGFloat {
        let count = CGFloat(codes.count)
        return min(count * Self.rowHeight + (count - 1) * Self.rowSpacing, Self.maxListHeight)
    }

    private func row(_ code: RecoveryCode) -> some View {
        HStack(spacing: 10) {
            Button(action: { toggleUsed(code) }) {
                Image(systemName: code.isUsed ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(code.isUsed ? .green : .secondary)
            }
            .buttonStyle(BorderlessButtonStyle())
            .help(code.isUsed ? "Mark as unused" : "Mark as used")

            VStack(alignment: .leading, spacing: 1) {
                Text(code.code)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .strikethrough(code.isUsed)
                    .foregroundColor(code.isUsed ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(code.code)
                if let note = code.note {
                    Text(note)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Button(action: { copy(code) }) {
                Image(systemName: copiedID == code.id ? "checkmark" : "doc.on.doc")
                    .foregroundColor(copiedID == code.id ? .green : .primary)
            }
            .buttonStyle(BorderlessButtonStyle())
            .help("Copy")

            Button(action: { pendingDeletion = code }) {
                Image(systemName: "trash")
            }
            .buttonStyle(BorderlessButtonStyle())
            .help("Delete")
        }
        .padding(.horizontal, 10)
        .frame(height: Self.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }

    private var addSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $pasted)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(height: 52)
                if pasted.isEmpty {
                    Text("Paste codes, one per line")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(0.12))
            )

            HStack {
                if let statusText {
                    Text(statusText)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Add codes", action: addPasted)
                    .disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func load() {
        do {
            codes = try store.recoveryCodes(for: token.id)
        } catch {
            loadFailed = true
        }
    }

    private func save(_ updated: [RecoveryCode]) -> Bool {
        do {
            try store.saveRecoveryCodes(updated, for: token.id)
            codes = updated
            errorText = nil
            return true
        } catch {
            errorText = "Couldn't save to the Keychain: \(error.localizedDescription)"
            return false
        }
    }

    private func addPasted() {
        let merge = RecoveryCode.merging(pasted, into: codes)
        guard merge.added > 0 else {
            statusText = codes.count >= RecoveryCode.maxCount
                ? "You can keep up to \(RecoveryCode.maxCount) codes."
                : "Nothing new to add."
            return
        }
        guard save(merge.codes) else { return }
        pasted = ""
        statusText = merge.skipped > 0
            ? "Added \(merge.added), skipped \(merge.skipped)."
            : "Added \(merge.added)."
    }

    private func toggleUsed(_ code: RecoveryCode) {
        _ = save(codes.map { $0.id == code.id ? $0.toggledUsed() : $0 })
    }

    private func delete(_ code: RecoveryCode) {
        _ = save(codes.filter { $0.id != code.id })
    }

    private func copy(_ code: RecoveryCode) {
        CodeClipboard.copy(code.code, playSound: false)
        flashCopied(code.id)
    }

    private func copyUnused() {
        CodeClipboard.copy(unusedCodes.map(\.code).joined(separator: "\n"), playSound: false)
        flashCopied(Self.allCodesID)
    }

    private func flashCopied(_ id: UUID) {
        copiedID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.copiedFeedbackDuration) {
            if copiedID == id { copiedID = nil }
        }
    }
}
