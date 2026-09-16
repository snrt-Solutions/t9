import AVFoundation
import SwiftUI

/// Full-screen camera that reads one `aesms://contact` QR and dismisses.
struct QRScannerView: View {
    var onCode: (String) -> Void
    var onCancel: () -> Void

    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let errorMessage {
                VStack(alignment: .leading, spacing: T9Theme.space2) {
                    Text("Camera unavailable")
                        .font(T9Theme.font(18, .semibold))
                        .foregroundStyle(.white)
                    Text(errorMessage)
                        .font(T9Theme.font(14))
                        .foregroundStyle(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                    Button(action: onCancel) {
                        Text("Close")
                            .font(T9Theme.font(15, .medium))
                            .foregroundStyle(.white)
                            .frame(minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }
                .padding(T9Theme.pageInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                QRScannerRepresentable(
                    onCode: onCode,
                    onError: { errorMessage = $0 }
                )
                .ignoresSafeArea()

                VStack {
                    HStack {
                        Button(action: onCancel) {
                            Text("Cancel")
                                .font(T9Theme.font(15, .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color.black.opacity(0.45))
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.horizontal, T9Theme.pageInset)
                    .padding(.top, T9Theme.space2)

                    Spacer()

                    Text("Point at their AeSMS QR")
                        .font(T9Theme.font(14, .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.45))
                        .padding(.bottom, T9Theme.space4)
                }
            }
        }
    }
}

private struct QRScannerRepresentable: UIViewControllerRepresentable {
    var onCode: (String) -> Void
    var onError: (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let vc = QRScannerViewController()
        vc.onCode = onCode
        vc.onError = onError
        return vc
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
}

final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    var onError: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var handled = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startSessionIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning {
            session.stopRunning()
        }
    }

    private func configureSession() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCapture()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.setupCapture()
                        self?.startSessionIfNeeded()
                    } else {
                        self?.onError?("Camera access denied. Enable it in Settings.")
                    }
                }
            }
        case .denied, .restricted:
            onError?("Camera access denied. Enable it in Settings.")
        @unknown default:
            onError?("Camera access unavailable.")
        }
    }

    private func setupCapture() {
        guard previewLayer == nil else { return }
        session.beginConfiguration()
        session.sessionPreset = .high

        guard let device = AVCaptureDevice.default(for: .video) else {
            session.commitConfiguration()
            onError?("No camera available on this device.")
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                onError?("Could not open the camera.")
                return
            }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else {
                session.commitConfiguration()
                onError?("Could not start QR detection.")
                return
            }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            output.metadataObjectTypes = [.qr]

            session.commitConfiguration()

            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            view.layer.insertSublayer(layer, at: 0)
            previewLayer = layer
        } catch {
            session.commitConfiguration()
            onError?("Could not open the camera.")
        }
    }

    private func startSessionIfNeeded() {
        guard previewLayer != nil, !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !handled,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              object.type == .qr,
              let value = object.stringValue,
              !value.isEmpty else { return }

        handled = true
        if session.isRunning {
            session.stopRunning()
        }
        onCode?(value)
    }
}
