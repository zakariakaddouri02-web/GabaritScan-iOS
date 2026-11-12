import UIKit
import AVFoundation
import ARKit
import simd

/// UIViewController principal — équivalent de ScanFragment.kt
/// Gère :
///   - AVCaptureSession (preview + analyse frame YUV)
///   - ARKit (pose téléphone)
///   - AprilTagDetector
///   - Délègue à ScanViewModel
final class ScanViewController: UIViewController {

    // ── Injected ──────────────────────────────────────────────────────────────
    var viewModel: ScanViewModel!

    // ── Camera ────────────────────────────────────────────────────────────────
    private let captureSession   = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private let videoOutput      = AVCaptureVideoDataOutput()
    private let analysisQueue    = DispatchQueue(label: "com.gabaritscan.analysis",
                                                 qos: .userInteractive)

    // ── ARKit ─────────────────────────────────────────────────────────────────
    private let arSession    = ARSession()
    private var lastTransform: simd_float4x4? = nil
    private var lastTimestamp: TimeInterval    = 0

    // ── AprilTag ──────────────────────────────────────────────────────────────
    private lazy var aprilTagDetector = AprilTagDetector(tagSizeMm: GabaritConfig.tagSizeMm)

    // ── UI ────────────────────────────────────────────────────────────────────
    private var overlayView: ScanOverlayView!
    private var guideLabel:  UILabel!
    private var captureBtn:  UIButton!
    private var progressBar: UIProgressView!
    private var progressLbl: UILabel!

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
        setupARKit()
        setupUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        captureSession.startRunning()
        arSession.run(makeARConfig(), options: [.resetTracking, .removeExistingAnchors])
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession.stopRunning()
        arSession.pause()
    }

    // MARK: - Camera Setup

    private func setupCamera() {
        captureSession.sessionPreset = .photo   // 4032×3024 (12 MP mode principal)

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video, position: .back),
              let input  = try? AVCaptureDeviceInput(device: device),
              captureSession.canAddInput(input)
        else { return }

        captureSession.addInput(input)

        // ── Lire les intrinsèques réelles depuis le capteur ──────────────────
        // AVCameraCalibrationData disponible dans AVCaptureDepthDataOutput,
        // mais pour Phase 1 on utilise les valeurs par défaut.
        // Phase 2 : activer AVCaptureDepthDataOutput pour récupérer la matrice K exacte.

        // ── Video output pour analyse frame ──────────────────────────────────
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: analysisQueue)

        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        // Orientation fixe portrait
        videoOutput.connections.first?.videoOrientation = .portrait

        // ── Preview layer ─────────────────────────────────────────────────────
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.insertSublayer(previewLayer, at: 0)
    }

    // MARK: - ARKit Setup

    private func makeARConfig() -> ARWorldTrackingConfiguration {
        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravity
        // Depth (phase optionnelle — disponible sur iPhone 12 Pro Max avec LiDAR)
        // On ne l'active pas en Phase 1.
        // if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
        //     config.sceneReconstruction = .mesh
        // }
        return config
    }

    private func setupARKit() {
        arSession.delegate = self
    }

    // MARK: - UI Setup

    private func setupUI() {
        // Overlay
        overlayView = ScanOverlayView(frame: view.bounds)
        overlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(overlayView)

        // Label guide (haut)
        guideLabel = UILabel()
        guideLabel.text = "Pointez le tag AprilTag"
        guideLabel.textColor = .white
        guideLabel.font = .boldSystemFont(ofSize: 16)
        guideLabel.numberOfLines = 3
        guideLabel.textAlignment = .center
        guideLabel.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        guideLabel.layer.cornerRadius = 8
        guideLabel.clipsToBounds = true
        guideLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(guideLabel)

        // Barre progression
        progressBar = UIProgressView(progressViewStyle: .default)
        progressBar.tintColor = UIColor(red: 0.3, green: 0.8, blue: 0.3, alpha: 1)
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(progressBar)

        progressLbl = UILabel()
        progressLbl.textColor = .white
        progressLbl.font = .systemFont(ofSize: 13, weight: .medium)
        progressLbl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(progressLbl)

        // Bouton capture
        captureBtn = UIButton(type: .custom)
        captureBtn.backgroundColor = .white
        captureBtn.layer.cornerRadius = 36
        captureBtn.layer.borderWidth  = 4
        captureBtn.layer.borderColor  = UIColor.lightGray.cgColor
        captureBtn.addTarget(self, action: #selector(onCaptureTapped), for: .touchUpInside)
        captureBtn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(captureBtn)

        NSLayoutConstraint.activate([
            guideLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            guideLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            guideLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            captureBtn.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureBtn.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            captureBtn.widthAnchor.constraint(equalToConstant: 72),
            captureBtn.heightAnchor.constraint(equalToConstant: 72),

            progressBar.bottomAnchor.constraint(equalTo: captureBtn.topAnchor, constant: -16),
            progressBar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            progressBar.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.6),

            progressLbl.bottomAnchor.constraint(equalTo: progressBar.topAnchor, constant: -4),
            progressLbl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
    }

    // MARK: - Actions

    @objc private func onCaptureTapped() {
        Task { @MainActor in
            viewModel.onManualCapture()
        }
    }

    // MARK: - Update UI from ViewModel state

    @MainActor
    private func applyState(_ state: ScanState) {
        guideLabel.text = state.guideMessage
        overlayView.update(state: state)

        let progress = state.totalGuideViews > 0
            ? Float(state.capturedCount) / Float(state.totalGuideViews)
            : 0
        progressBar.setProgress(progress, animated: true)
        progressLbl.text = "\(state.capturedCount) / \(state.totalGuideViews) vues"
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension ScanViewController: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let frameSize = CGSize(
            width:  CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )

        // ── Détection AprilTag (thread analyse) ──────────────────────────────
        let detections = aprilTagDetector.detect(
            pixelBuffer: pixelBuffer,
            intrinsics:  viewModel.intrinsics
        )

        // ── Pose ARKit (lire depuis le dernier frame ARKit reçu) ─────────────
        let arkitPose = currentARKitPose()

        // ── Mise à jour ViewModel sur le MainActor ───────────────────────────
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.viewModel.onFrameProcessed(
                arkitPose:     arkitPose,
                tagDetections: detections,
                frameSize:     frameSize
            )
            self.applyState(self.viewModel.state)
        }
    }

    private func currentARKitPose() -> ARKitPose? {
        guard let frame = arSession.currentFrame else { return nil }
        let isTracking = frame.camera.trackingState == .normal
        let transform  = frame.camera.transform

        // Estimer la vitesse à partir de la dérivée de position
        let now = frame.timestamp
        var velocity: Float = 0
        if let prev = lastTransform, lastTimestamp > 0 {
            let dt = Float(now - lastTimestamp)
            if dt > 0 {
                let dx = transform.columns.3.x - prev.columns.3.x
                let dy = transform.columns.3.y - prev.columns.3.y
                let dz = transform.columns.3.z - prev.columns.3.z
                velocity = sqrt(dx*dx + dy*dy + dz*dz) / dt
            }
        }
        lastTransform  = transform
        lastTimestamp  = now

        return ARKitPose(transform: transform, isTracking: isTracking,
                         velocityMagnitude: velocity)
    }
}

// MARK: - ARSessionDelegate

extension ScanViewController: ARSessionDelegate {
    func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor in
            guideLabel.text = "⚠️ ARKit erreur: \(error.localizedDescription)"
        }
    }
    func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor in
            guideLabel.text = "⚠️ ARKit interrompu"
        }
    }
    func sessionInterruptionEnded(_ session: ARSession) {
        arSession.run(makeARConfig(), options: [.resetTracking])
    }
}
