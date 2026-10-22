import SwiftUI
import AppKit
import AVFoundation

enum AddMode: String, CaseIterable {
    case otpauth = "Link / QR"
    case manual  = "Manually"
}

struct AddTokenSheet: View {
    let onAddMany: ([ImportedToken]) -> ImportResult
    let onClose: () -> Void
    var onModeChange: (AddMode) -> Void = { _ in }

    @State private var mode: AddMode = .otpauth

    // otpauth / migration
    @State private var otpauthText: String = ""

    // camera devices — selectedCameraID persists between sheet opens
    @State private var selectedCameraID: String? = nil

    // manual
    @State private var issuer: String = ""
    @State private var account: String = ""
    @State private var secretBase32: String = ""
    @State private var digits: Int = 6
    @State private var period: String = "30"
    @State private var algorithm: OTPAlgorithm = .sha1

    @State private var errorMessage: String?
    @State private var isDropping: Bool = false

    // camera scanner
    @State private var showCameraScanner: Bool = false

    // small success hint
    @State private var addedMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Picker("", selection: $mode) {
                ForEach(AddMode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .labelsHidden()

            if mode == .otpauth {
                otpauthBlock
            } else {
                manualFields
            }

            Spacer(minLength: 0)

            footer
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: mode) { onModeChange($0) }
        .sheet(isPresented: $showCameraScanner) {
            CameraSheetView(
                selectedCameraID: $selectedCameraID,
                onFound: { found in
                    otpauthText = found
                    showCameraScanner = false
                },
                onClose: { showCameraScanner = false }
            )
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            statusMessage
            Spacer(minLength: 12)
            Button("Close", action: onClose)
                .keyboardShortcut(.cancelAction)
            Button("Add", action: addAction)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
        }
    }

    @ViewBuilder
    private var statusMessage: some View {
        if let err = errorMessage {
            Label(err, systemImage: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        } else if let msg = addedMessage {
            Label(msg, systemImage: "checkmark.seal.fill")
                .foregroundColor(.green)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
        }
    }

    private var otpauthBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            dropZone

            HStack(spacing: 8) {
                sourceButton("Choose Image…", systemImage: "photo", action: importFromImageFile)
                sourceButton("Paste", systemImage: "doc.on.clipboard", action: importFromClipboard)
                sourceButton("Scan with Camera", systemImage: "camera", action: startCameraScanner)
            }

            labeled("Link") {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $otpauthText)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .frame(height: 64)

                    if otpauthText.isEmpty {
                        Text("otpauth://totp/… or otpauth-migration://…")
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
                .padding(6)
                .background(fieldBackground)
            }
        }
    }

    private func sourceButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Drop zone

    private var dropZone: some View {
        VStack(spacing: 8) {
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 34, weight: .light))
                .foregroundColor(isDropping ? .accentColor : .secondary)
            Text("Drop a QR code image here")
                .font(.system(size: 13, weight: .semibold))
            Text("PNG, JPEG, HEIC or a screenshot")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isDropping ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isDropping ? Color.accentColor : Color.primary.opacity(0.18),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
        )
        .animation(.easeInOut(duration: 0.15), value: isDropping)
        .onDrop(of: ["public.file-url", "public.tiff", "public.png", "public.jpeg"], isTargeted: $isDropping) { providers -> Bool in
            guard let item = providers.first else { return false }
            var handled = false

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
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                inputField("Issuer", systemImage: "building.columns", placeholder: "e.g. GitHub", text: $issuer)
                inputField("Account", systemImage: "at", placeholder: "e.g. you@example.com", text: $account)
            }

            inputField("Secret (Base32)", systemImage: "key", placeholder: "e.g. JBSWY3DPEHPK3PXP", text: $secretBase32, monospaced: true)

            HStack(alignment: .top, spacing: 12) {
                labeled("Digits") {
                    Picker("", selection: $digits) {
                        Text("6").tag(6)
                        Text("8").tag(8)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .labelsHidden()
                    .frame(width: 110)
                }

                labeled("Period") {
                    HStack(spacing: 6) {
                        TextField("30", text: $period)
                            .textFieldStyle(PlainTextFieldStyle())
                        Text("sec")
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .frame(width: 110)
                    .background(fieldBackground)
                }

                labeled("Algorithm") {
                    Picker("", selection: $algorithm) {
                        ForEach(OTPAlgorithm.allCases, id: \.self) { value in
                            Text(value.rawValue).tag(value)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }

                Spacer(minLength: 0)
            }

            Text("Keep the default digits, period and algorithm unless the service says otherwise.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    private func inputField(_ title: String, systemImage: String, placeholder: String, text: Binding<String>, monospaced: Bool = false) -> some View {
        labeled(title) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundColor(.secondary)
                    .frame(width: 16)
                TextField(placeholder, text: text)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(monospaced ? .system(.body, design: .monospaced) : .body)
            }
            .padding(8)
            .background(fieldBackground)
        }
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            content()
        }
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.primary.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
    }

    private func addAction() {
        errorMessage = nil
        do {
            let list: [ImportedToken]
            var unsupported = 0
            if mode == .otpauth {
                let parsed = try ImportExportService.parseOtpauthOrMigration(
                    otpauthText.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                list = parsed.tokens
                unsupported = parsed.unsupported
            } else {
                list = [try buildManualImported()]
            }
            let result = onAddMany(list)

            if result.added > 0 {
                var msg = "Added \(result.added) token(s)"
                if result.duplicates > 0 { msg += ", \(result.duplicates) already existed" }
                if result.failed > 0 { msg += ", \(result.failed) couldn't be saved" }
                if unsupported > 0 { msg += ", \(unsupported) unsupported (HOTP/MD5) skipped" }
                withAnimation { addedMessage = msg }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { withAnimation { addedMessage = nil } }
                clearAllFields()
            } else if result.failed > 0 {
                errorMessage = "Couldn't save to the Keychain. Check the warning in the GlassOTP menu-bar window."
            } else {
                errorMessage = result.duplicates <= 1
                    ? "This token already exists."
                    : "All \(result.duplicates) tokens already exist."
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func clearAllFields() {
        otpauthText = ""
        issuer = ""
        account = ""
        secretBase32 = ""
        digits = 6
        period = "30"
        algorithm = .sha1
        errorMessage = nil
    }

    private func buildManualImported() throws -> ImportedToken {
        let cleanSecret = secretBase32.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let secret = Base32.decode(cleanSecret), !secret.isEmpty else { throw ImportError.badBase32 }
        guard let p = Int(period.trimmingCharacters(in: .whitespacesAndNewlines)), p > 0 else { throw ImportError.badPeriod }
        let cleanIssuer = issuer.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !(cleanIssuer.isEmpty && cleanAccount.isEmpty) else { throw ImportError.missingName }
        let token = OTPToken(
            issuer: cleanIssuer,
            account: cleanAccount,
            digits: digits, period: p, algorithm: algorithm,
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
        let fileURLs = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]

        if let text = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           text.lowercased().hasPrefix("otpauth") {
            otpauthText = text
        } else if let url = fileURLs?.first {
            importImage(at: url)
        } else if let image = NSImage(pasteboard: pb) {
            importImage(img: image)
        } else {
            errorMessage = "The clipboard has no QR image or otpauth link."
        }
    }

    private func importImage(at url: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let link = try QRService.scanOtpauth(from: url)
                DispatchQueue.main.async { self.otpauthText = link }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                DispatchQueue.main.async { self.errorMessage = message }
            }
        }
    }

    private func importImage(img: NSImage) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let link = try QRService.scanOtpauth(from: img)
                DispatchQueue.main.async { self.otpauthText = link }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                DispatchQueue.main.async { self.errorMessage = message }
            }
        }
    }

    private func startCameraScanner() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showCameraScanner = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { self.showCameraScanner = true }
                    else { self.errorMessage = "Camera access is denied." }
                }
            }
        default:
            errorMessage = "Camera access is denied. Allow it in System Settings → Security & Privacy."
        }
    }

}


// MARK: - Camera scanner sheet

private struct CameraSheetView: View {
    @Binding var selectedCameraID: String?
    let onFound: (String) -> Void
    let onClose: () -> Void

    @State private var cameras: [AVCaptureDevice] = []
    @State private var isRunning: Bool = false

    var body: some View {
        ZStack(alignment: .top) {
            Color.black

            QRCameraScannerView(
                onFound: { payload in
                    isRunning = false
                    onFound(payload)
                },
                isRunning: $isRunning,
                selectedDeviceID: $selectedCameraID
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            ViewfinderCorners()
                .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .frame(width: 230, height: 230)
                .shadow(color: .black.opacity(0.5), radius: 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Overlay controls — live above the AVCaptureVideoPreviewLayer regardless of layout.
            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .help("Close")

                    Spacer()

                    Text("Scan QR Code")
                        .font(.headline)
                        .foregroundColor(.white)

                    Spacer()

                    // Invisible balance element to keep the title centered
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .hidden()
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .background(
                    LinearGradient(
                        colors: [Color.black.opacity(0.7), Color.black.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                Spacer()

                // Bottom bar — always visible so the user can see / switch cameras.
                VStack(spacing: 10) {
                    Text("Hold the QR code inside the frame")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.9))

                    if !cameras.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 12))
                                .foregroundColor(Color.white.opacity(0.7))

                            if cameras.count > 1 {
                                Picker("", selection: $selectedCameraID) {
                                    ForEach(cameras, id: \.uniqueID) { cam in
                                        Text(cam.localizedName).tag(Optional(cam.uniqueID))
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: 260)
                                .colorScheme(.dark)
                            } else {
                                Text(cameras[0].localizedName)
                                    .font(.system(size: 13))
                                    .foregroundColor(Color.white.opacity(0.85))
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 28)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(
                        colors: [Color.black.opacity(0), Color.black.opacity(0.75)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .frame(width: 520, height: 400)
        .onAppear {
            // Discover cameras fresh each time the sheet opens.
            let found = CameraPreviewView.discoverCameras()
            cameras = found
            if selectedCameraID == nil || !found.contains(where: { $0.uniqueID == selectedCameraID }) {
                selectedCameraID = found.first?.uniqueID
            }

            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                isRunning = true
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    DispatchQueue.main.async { if granted { self.isRunning = true } }
                }
            default:
                break
            }
        }
        .onDisappear { isRunning = false }
    }
}

private struct ViewfinderCorners: Shape {
    var length: CGFloat = 32

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: rect.minX, y: rect.minY), 1, 1),
            (CGPoint(x: rect.maxX, y: rect.minY), -1, 1),
            (CGPoint(x: rect.minX, y: rect.maxY), 1, -1),
            (CGPoint(x: rect.maxX, y: rect.maxY), -1, -1),
        ]
        for (corner, dx, dy) in corners {
            path.move(to: CGPoint(x: corner.x, y: corner.y + dy * length))
            path.addLine(to: corner)
            path.addLine(to: CGPoint(x: corner.x + dx * length, y: corner.y))
        }
        return path
    }
}
