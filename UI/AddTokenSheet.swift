import SwiftUI
import AppKit
import AVFoundation
import Vision

enum AddMode: String, CaseIterable {
    case otpauth = "Ссылка / QR"
    case manual  = "Вручную"
}

struct AddTokenSheet: View {
    let onAddMany: ([ImportedToken]) -> Void
    let onClose: () -> Void

    @State private var mode: AddMode = .otpauth

    // otpauth / migration
    @State private var otpauthText: String = ""

    // manual
    @State private var issuer: String = ""
    @State private var account: String = ""
    @State private var secretBase32: String = ""
    @State private var digits: String = "6"
    @State private var period: String = "30"
    @State private var algorithmIndex: Int = 0 // 0:SHA1 1:SHA256 2:SHA512

    @State private var errorMessage: String?
    @State private var isDropping: Bool = false

    // camera scanner
    @State private var showCameraScanner: Bool = false
    @State private var cameraRunning: Bool = false

    // small success hint
    @State private var addedMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "qrcode.viewfinder")
                    .foregroundColor(.accentColor)
                Text("Добавить токен(ы)")
                    .font(.title3).fontWeight(.semibold)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(BorderlessButtonStyle())
                .help("Закрыть")
            }

            Picker("Режим", selection: $mode) {
                ForEach(AddMode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(SegmentedPickerStyle())

            if mode == .otpauth {
                otpauthBlock
            } else {
                manualFields
            }

            if let err = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle").foregroundColor(.orange)
                    Text(err).foregroundColor(.orange).font(.footnote)
                }
            }

            if let msg = addedMessage {
                HStack {
                    Image(systemName: "checkmark.seal.fill").foregroundColor(.green)
                    Text(msg).font(.footnote).foregroundColor(.green)
                }
                .transition(.opacity)
            }

            HStack {
                Spacer()
                Button("Отмена") { onClose() }
                Button("Добавить") { addAction() }
                    .keyboardShortcut(.return)
                    .disabled(!canSubmit)
            }
            .padding(.top, 2)
        }
        .padding(18)
        // camera sheet
        .sheet(isPresented: $showCameraScanner, onDismiss: { cameraRunning = false }) {
            VStack {
                HStack {
                    Text("Сканировать QR").font(.headline)
                    Spacer()
                    Button("Закрыть") { showCameraScanner = false }
                }
                .padding([.top, .horizontal])
                Divider()
                QRCameraScannerView(onFound: { found in
                    DispatchQueue.main.async {
                        self.otpauthText = found
                        self.showCameraScanner = false
                    }
                }, isRunning: $cameraRunning)
                    .frame(minHeight: 360)
                    .padding()
                Spacer()
            }
            .frame(minWidth: 520, minHeight: 420)
            .onAppear {
                AVCaptureDevice.requestAccess(for: .video) { _ in
                    DispatchQueue.main.async { self.cameraRunning = true }
                }
            }
            .onDisappear { cameraRunning = false }
        }
    }

    private var otpauthBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Вставьте ссылку **otpauth://…** или **otpauth-migration://…** (экспорт Google Authenticator). Либо перетащите сюда изображение/скриншот с QR-кодом.")
                .font(.footnote)
                .foregroundColor(.secondary)

            TextEditor(text: $otpauthText)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .frame(minHeight: 84)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 1))

            dropZone

            HStack(spacing: 8) {
                Button(action: importFromImageFile) {
                    Label("Выбрать изображение…", systemImage: "folder")
                }
                Button(action: importFromClipboard) {
                    Label("Вставить из буфера", systemImage: "doc.on.clipboard")
                }
                Button(action: { startCameraScanner() }) {
                    Label("Сканировать с камеры", systemImage: "camera")
                }
                Spacer()
                Button(action: pasteFromClipboardIfText) {
                    Label("Вставить ссылку", systemImage: "link")
                }
            }
        }
    }

    // MARK: - Drop zone
    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(isDropping ? Color.accentColor.opacity(0.15) : Color.black.opacity(0.06))
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)

            VStack(spacing: 6) {
                Image(systemName: "tray.and.arrow.down")
                Text("Перетащите сюда изображение с QR")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .padding(12)
        }
        .frame(height: 84)
        .onDrop(of: ["public.file-url", "public.tiff", "public.png", "public.jpeg"], isTargeted: $isDropping) { providers -> Bool in
            guard let item = providers.first else { return false }
            var handled = false

            // 1) Файл-URL
            if item.hasItemConformingToTypeIdentifier("public.file-url") {
                item.loadItem(forTypeIdentifier: "public.file-url", options: nil) { (data, _) in
                    if let urlData = data as? Data,
                       let url = URL(dataRepresentation: urlData, relativeTo: nil) {
                        DispatchQueue.main.async { self.importImage(at: url) }
                    } else if let url = data as? URL {
                        DispatchQueue.main.async { self.importImage(at: url) }
                    }
                }
                handled = true
            }

            // 2) raw images
            if item.hasItemConformingToTypeIdentifier("public.tiff") {
                item.loadDataRepresentation(forTypeIdentifier: "public.tiff") { data, _ in
                    if let data = data, let img = NSImage(data: data) { self.importImage(img: img) }
                }
                handled = true
            } else if item.hasItemConformingToTypeIdentifier("public.png") {
                item.loadDataRepresentation(forTypeIdentifier: "public.png") { data, _ in
                    if let data = data, let img = NSImage(data: data) { self.importImage(img: img) }
                }
                handled = true
            } else if item.hasItemConformingToTypeIdentifier("public.jpeg") {
                item.loadDataRepresentation(forTypeIdentifier: "public.jpeg") { data, _ in
                    if let data = data, let img = NSImage(data: data) { self.importImage(img: img) }
                }
                handled = true
            }

            return handled
        }
    }

    // MARK: - Actions

    private var canSubmit: Bool {
        switch mode {
        case .otpauth:
            return !otpauthText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .manual:
            return !secretBase32.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var manualFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Issuer").font(.caption).foregroundColor(.secondary)
                    HStack {
                        Image(systemName: "building.columns").foregroundColor(.secondary)
                        TextField("напр. Google", text: $issuer)
                            .textFieldStyle(PlainTextFieldStyle())
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.06)))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Account").font(.caption).foregroundColor(.secondary)
                    HStack {
                        Image(systemName: "at").foregroundColor(.secondary)
                        TextField("напр. you@example.com", text: $account)
                            .textFieldStyle(PlainTextFieldStyle())
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.06)))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Secret (Base32)").font(.caption).foregroundColor(.secondary)
                HStack {
                    Image(systemName: "key").foregroundColor(.secondary)
                    TextField("например JBSWY3DPEHPK3PXP", text: $secretBase32)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(.body, design: .monospaced))
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.06)))
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Digits").font(.caption).foregroundColor(.secondary)
                    TextField("6 или 8", text: $digits)
                        .textFieldStyle(PlainTextFieldStyle())
                        .frame(width: 80)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.06)))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Period (сек.)").font(.caption).foregroundColor(.secondary)
                    TextField("обычно 30", text: $period)
                        .textFieldStyle(PlainTextFieldStyle())
                        .frame(width: 100)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.06)))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Algorithm").font(.caption).foregroundColor(.secondary)
                    Picker("", selection: $algorithmIndex) {
                        Text("SHA1").tag(0)
                        Text("SHA256").tag(1)
                        Text("SHA512").tag(2)
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
                Spacer()
            }
        }
    }

    private func addAction() {
        errorMessage = nil
        do {
            let list: [ImportedToken]
            if mode == .otpauth {
                list = try ImportExportService.parseOtpauthOrMigration(
                    otpauthText.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            } else {
                list = [try buildManualImported()]
            }
            onAddMany(list)

            // показываем краткий success и очищаем поля, оставляя окно открытым
            withAnimation { addedMessage = "Добавлено \(list.count) токен(ов)" }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { withAnimation { addedMessage = nil } }
            clearAllFields()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func clearAllFields() {
        otpauthText = ""
        issuer = ""
        account = ""
        secretBase32 = ""
        digits = "6"
        period = "30"
        algorithmIndex = 0
        errorMessage = nil
    }

    private func buildManualImported() throws -> ImportedToken {
        let cleanSecret = secretBase32.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let secret = Base32.decode(cleanSecret), !secret.isEmpty else { throw ImportError.badBase32 }
        guard let d = Int(digits), (d == 6 || d == 8) else { throw ImportError.badDigits }
        guard let p = Int(period), p > 0 else { throw ImportError.badPeriod }
        let algo: OTPAlgorithm = (algorithmIndex == 1) ? .sha256 : (algorithmIndex == 2 ? .sha512 : .sha1)
        let token = OTPToken(
            issuer: issuer.trimmingCharacters(in: .whitespacesAndNewlines),
            account: account.trimmingCharacters(in: .whitespacesAndNewlines),
            digits: d, period: p, algorithm: algo,
            isPinned: false, sortOrder: Int(Date().timeIntervalSince1970)
        )
        return ImportedToken(token: token, secret: secret)
    }

    private func importFromImageFile() {
        errorMessage = nil
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedFileTypes = ["png","jpg","jpeg","heic","tiff","bmp","gif"]
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            self.importImage(at: url)
        }
    }

    private func importFromClipboard() {
        errorMessage = nil
        let pb = NSPasteboard.general
        if let data = pb.data(forType: .tiff), let img = NSImage(data: data) {
            importImage(img: img)
        } else if let str = pb.string(forType: .string), str.lowercased().hasPrefix("otpauth") {
            self.otpauthText = str
        } else {
            self.errorMessage = "В буфере нет изображения с QR или otpauth/otpauth-migration ссылки."
        }
    }

    private func pasteFromClipboardIfText() {
        let pb = NSPasteboard.general
        if let str = pb.string(forType: .string), str.lowercased().hasPrefix("otpauth") {
            self.otpauthText = str
        }
    }

    private func importImage(at url: URL) {
        do {
            let link = try QRService.scanOtpauth(from: url)
            self.otpauthText = link
        } catch {
            self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func importImage(img: NSImage) {
        do {
            let link = try QRService.scanOtpauth(from: img)
            self.otpauthText = link
        } catch {
            self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // Camera helper
    private func startCameraScanner() {
        // проверим доступ
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showCameraScanner = true
            cameraRunning = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.showCameraScanner = true
                        self.cameraRunning = true
                    } else {
                        self.errorMessage = "Доступ к камере запрещён."
                    }
                }
            }
        default:
            errorMessage = "Доступ к камере запрещён. Разрешите в System Settings → Security & Privacy."
        }
    }
}
