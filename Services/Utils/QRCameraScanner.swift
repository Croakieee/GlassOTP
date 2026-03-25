import Foundation
import AVFoundation
import AppKit
import SwiftUI
import Vision

// NSViewRepresentable
struct QRCameraScannerView: NSViewRepresentable {
    typealias NSViewType = CameraPreviewView
    
    // observer на смену камеры
    var currentDeviceID: String?

    var onFound: (String) -> Void
    @Binding var isRunning: Bool

    // чпоньк
    @Binding var selectedDeviceID: String?

    func makeNSView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.coordinator = context.coordinator

        // передаём выбранную камеру
        // view.selectedDeviceID = selectedDeviceID

        return view
    }

    func updateNSView(_ nsView: CameraPreviewView, context: Context) {
        DispatchQueue.main.async {
            if nsView.currentDeviceID != selectedDeviceID {
                nsView.currentDeviceID = selectedDeviceID
                nsView.restartSession() // рестар после выбора камеры
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
                               !payload.isEmpty {
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
    
    // restart session для подхвата смены камеры
    func restartSession() {
        stopSession()
        startSessionIfNeeded()
    }

    // чпоньк =)
    // var selectedDeviceID: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    deinit {
        stopSession()
    }

    func startSessionIfNeeded() {
        DispatchQueue.main.async { [weak self] in
            self?._startSession()
        }
    }

    private func _startSession() {
        guard captureSession == nil else { return }

        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .denied || status == .restricted { return }

        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { _ in }
        }

        let session = AVCaptureSession()
        session.sessionPreset = .high

        // выбор камеры
        let device: AVCaptureDevice?

        if let id = currentDeviceID {
            device = AVCaptureDevice.devices(for: .video).first { $0.uniqueID == id }
        } else {
            device = AVCaptureDevice.default(for: .video)
        }

        guard let camera = device,
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input)
        else { return }

        session.addInput(input)

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = bounds

        layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        layer?.addSublayer(previewLayer)

        self.previewLayer = previewLayer

        let dataOutput = AVCaptureVideoDataOutput()
        dataOutput.alwaysDiscardsLateVideoFrames = true
        dataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

        let queue = DispatchQueue(label: "glassotp.camera.queue")
        dataOutput.setSampleBufferDelegate(self, queue: queue)

        guard session.canAddOutput(dataOutput) else {
            previewLayer.removeFromSuperlayer()
            self.previewLayer = nil
            return
        }

        session.addOutput(dataOutput)

        if let conn = dataOutput.connection(with: .video), conn.isVideoOrientationSupported {
            conn.videoOrientation = .portrait
        }

        self.captureSession = session

        postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(frameChanged),
            name: NSView.frameDidChangeNotification,
            object: self
        )

        session.startRunning()
    }

    @objc private func frameChanged() {
        previewLayer?.frame = bounds
    }

    func stopSession() {
        NotificationCenter.default.removeObserver(self)

        if let session = captureSession {
            if session.isRunning {
                session.stopRunning()
            }
        }

        captureSession = nil
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
    }
}

extension CameraPreviewView: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {

        coordinator?.handleSampleBuffer(sampleBuffer)
    }
}
