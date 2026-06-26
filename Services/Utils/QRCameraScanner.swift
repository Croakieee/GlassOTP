import Foundation
import AVFoundation
import AppKit
import SwiftUI
import Vision

// NSViewRepresentable
struct QRCameraScannerView: NSViewRepresentable {
    typealias NSViewType = CameraPreviewView

    var onFound: (String) -> Void
    @Binding var isRunning: Bool
    @Binding var selectedDeviceID: String?

    func makeNSView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: CameraPreviewView, context: Context) {
        DispatchQueue.main.async {
            if nsView.currentDeviceID != selectedDeviceID {
                nsView.currentDeviceID = selectedDeviceID
                nsView.restartSession()
                return  // restartSession handles start; don't double-call startSessionIfNeeded
            }

            if isRunning {
                nsView.startSessionIfNeeded()
            } else {
                nsView.stopSession()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject {
        var parent: QRCameraScannerView
        private let detectQueue = DispatchQueue(label: "glassotp.qr.detect")

        init(parent: QRCameraScannerView) {
            self.parent = parent
            super.init()
        }

        func handleSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
            detectQueue.async {
                guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

                let request = VNDetectBarcodesRequest { [weak self] request, _ in
                    guard let self = self else { return }
                    if let results = request.results as? [VNBarcodeObservation] {
                        for obs in results {
                            if let payload = obs.payloadStringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                               !payload.isEmpty,
                               payload.lowercased().hasPrefix("otpauth") {
                                DispatchQueue.main.async {
                                    self.parent.isRunning = false
                                    self.parent.onFound(payload)
                                }
                                return
                            }
                        }
                    }
                }

                request.symbologies = [.QR]

                let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
                do { try handler.perform([request]) } catch { }
            }
        }
    }
}


/// NSView + preview layer
final class CameraPreviewView: NSView {

    var captureSession: AVCaptureSession?
    var previewLayer: AVCaptureVideoPreviewLayer?
    var coordinator: QRCameraScannerView.Coordinator?
    var currentDeviceID: String?

    // Single persistent queue for sample buffer delivery.
    private let captureQueue = DispatchQueue(label: "glassotp.camera.queue", qos: .userInitiated)
    // Serial queue for session configuration / startRunning (must not be main).
    private let sessionQueue = DispatchQueue(label: "glassotp.session.queue", qos: .userInitiated)

    func restartSession() {
        stopSession()
        startSessionIfNeeded()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    deinit {
        // Don't call stopSession() from deinit — it uses weak-self async blocks that
        // become no-ops after deallocation, leaving the session running. Capture the
        // session and layer directly so the async closures have no reference to self.
        NotificationCenter.default.removeObserver(self)
        let session = captureSession
        captureSession = nil
        let layer = previewLayer
        previewLayer = nil
        if let session = session {
            sessionQueue.async {
                if session.isRunning { session.stopRunning() }
            }
        }
        if let layer = layer {
            DispatchQueue.main.async { layer.removeFromSuperlayer() }
        }
    }

    func startSessionIfNeeded() {
        guard captureSession == nil else { return }
        sessionQueue.async { [weak self] in
            self?._startSession()
        }
    }

    private func _startSession() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .denied || status == .restricted { return }
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { _ in }
            return
        }

        let session = AVCaptureSession()
        session.sessionPreset = .high

        let device: AVCaptureDevice?
        if let id = currentDeviceID {
            device = CameraPreviewView.discoverCameras().first { $0.uniqueID == id }
        } else {
            device = AVCaptureDevice.default(for: .video)
        }

        guard let camera = device,
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input)
        else { return }

        session.addInput(input)

        let dataOutput = AVCaptureVideoDataOutput()
        dataOutput.alwaysDiscardsLateVideoFrames = true
        dataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        dataOutput.setSampleBufferDelegate(self, queue: captureQueue)

        guard session.canAddOutput(dataOutput) else { return }
        session.addOutput(dataOutput)

        if let conn = dataOutput.connection(with: .video), conn.isVideoOrientationSupported {
            conn.videoOrientation = .portrait
        }

        // Set captureSession on sessionQueue before startRunning so stopSession()
        // (called from main) can find it if the view is closed immediately.
        self.captureSession = session

        // Preview layer must be set up on main; async is fine — the layer appears
        // within one frame, and we no longer block sessionQueue with main.sync.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.frame = self.bounds
            self.layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
            self.layer?.addSublayer(previewLayer)
            self.previewLayer = previewLayer

            self.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.frameChanged),
                name: NSView.frameDidChangeNotification,
                object: self
            )
        }

        // startRunning blocks until ready — keep it off main.
        session.startRunning()
    }

    @objc private func frameChanged() {
        previewLayer?.frame = bounds
    }

    func stopSession() {
        NotificationCenter.default.removeObserver(self)
        if let session = captureSession, session.isRunning {
            sessionQueue.async { session.stopRunning() }
        }
        captureSession = nil
        DispatchQueue.main.async { [weak self] in
            self?.previewLayer?.removeFromSuperlayer()
            self?.previewLayer = nil
        }
    }

    // MARK: - Camera discovery

    static func discoverCameras() -> [AVCaptureDevice] {
        var deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .externalUnknown
        ]
        if #available(macOS 14.0, *) {
            deviceTypes.append(.continuityCamera)
        }
        return AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: .unspecified
        ).devices
    }
}

extension CameraPreviewView: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        coordinator?.handleSampleBuffer(sampleBuffer)
    }
}
