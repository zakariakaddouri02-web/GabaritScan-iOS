import UIKit
import ARKit
import simd

/// UIViewController utilisant ARKit natif pour la capture et le tracking
final class ScanViewController: UIViewController {

    var viewModel: ScanViewModel!

    // ARSCNView gère le rendu de la caméra à 60 fps avec l'orientation exacte
    private var sceneView: ARSCNView!

    // AprilTag detector
    private lazy var aprilTagDetector = AprilTagDetector(tagSizeMm: GabaritConfig.tagSizeMm)
    private let analysisQueue = DispatchQueue(label: "com.gabaritscan.analysis", qos: .userInteractive)
    private var isProcessingFrame = false

    // AR tracking velocity estimation
    private var lastTransform: simd_float4x4? = nil
    private var lastTimestamp: TimeInterval = 0

    // UI Overlays
    private var overlayView: ScanOverlayView!
    private var guideLabel:  UILabel!
    private var captureBtn:  UIButton!
    private var progressBar: UIProgressView!
    private var progressLbl: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupSceneView()
        setupUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravity
        sceneView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }

    // MARK: - SceneView (ARKit Camera)

    private func setupSceneView() {
        sceneView = ARSCNView(frame: view.bounds)
        sceneView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sceneView.session.delegate = self
        view.addSubview(sceneView)
    }

    // MARK: - UI Setup

    private func setupUI() {
        overlayView = ScanOverlayView(frame: view.bounds)
        overlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(overlayView)

        guideLabel = UILabel()
        guideLabel.text = "Pointez le tag AprilTag"
        guideLabel.textColor = .white
        guideLabel.font = .boldSystemFont(ofSize: 16)
        guideLabel.numberOfLines = 3
        guideLabel.textAlignment = .center
        guideLabel.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        guideLabel.layer.cornerRadius = 10
        guideLabel.clipsToBounds = true
        guideLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(guideLabel)

        progressBar = UIProgressView(progressViewStyle: .default)
        progressBar.tintColor = UIColor(red: 0.2, green: 0.8, blue: 0.3, alpha: 1)
        progressBar.trackTintColor = UIColor.white.withAlphaComponent(0.3)
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(progressBar)

        progressLbl = UILabel()
        progressLbl.textColor = .white
        progressLbl.font = .systemFont(ofSize: 14, weight: .semibold)
        progressLbl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(progressLbl)

        captureBtn = UIButton(type: .custom)
        captureBtn.backgroundColor = .white
        captureBtn.layer.cornerRadius = 36
        captureBtn.layer.borderWidth = 4
        captureBtn.layer.borderColor = UIColor.lightGray.cgColor
        captureBtn.addTarget(self, action: #selector(onCaptureTapped), for: .touchUpInside)
        captureBtn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(captureBtn)

        NSLayoutConstraint.activate([
            guideLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            guideLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            guideLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            guideLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 50),

            captureBtn.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureBtn.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            captureBtn.widthAnchor.constraint(equalToConstant: 72),
            captureBtn.heightAnchor.constraint(equalToConstant: 72),

            progressBar.bottomAnchor.constraint(equalTo: captureBtn.topAnchor, constant: -16),
            progressBar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            progressBar.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.65),
            progressBar.heightAnchor.constraint(equalToConstant: 6),

            progressLbl.bottomAnchor.constraint(equalTo: progressBar.topAnchor, constant: -6),
            progressLbl.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }

    @objc private func onCaptureTapped() {
        // Animation du bouton
        UIView.animate(withDuration: 0.1, animations: {
            self.captureBtn.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        }) { _ in
            UIView.animate(withDuration: 0.1) {
                self.captureBtn.transform = .identity
            }
        }
        viewModel.onManualCapture()
        applyState(viewModel.state)
    }

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

// MARK: - ARSessionDelegate

extension ScanViewController: ARSessionDelegate {

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard !isProcessingFrame else { return }
        isProcessingFrame = true

        let pixelBuffer = frame.capturedImage
        let intrinsicsMatrix = frame.camera.intrinsics

        // Mettre à jour les intrinsèques exactes du capteur
        let intrinsics = CameraIntrinsics(
            fx: intrinsicsMatrix[0][0],
            fy: intrinsicsMatrix[1][1],
            cx: intrinsicsMatrix[2][0],
            cy: intrinsicsMatrix[2][1]
        )
        self.viewModel.intrinsics = intrinsics

        let transform = frame.camera.transform
        let isTracking = frame.camera.trackingState == .normal || !self.viewModel.state.tagDetections.isEmpty
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
        lastTransform = transform
        lastTimestamp = now

        let arkitPose = ARKitPose(transform: transform, isTracking: isTracking, velocityMagnitude: velocity)

        let imageWidth = CVPixelBufferGetWidth(pixelBuffer)
        let imageHeight = CVPixelBufferGetHeight(pixelBuffer)
        let frameSize = CGSize(width: imageWidth, height: imageHeight)

        analysisQueue.async { [weak self] in
            guard let self = self else { return }
            let detections = self.aprilTagDetector.detect(pixelBuffer: pixelBuffer, intrinsics: intrinsics)

            Task { @MainActor in
                self.viewModel.onFrameProcessed(
                    arkitPose: arkitPose,
                    tagDetections: detections,
                    frameSize: frameSize
                )
                self.applyState(self.viewModel.state)
                self.isProcessingFrame = false
            }
        }
    }
}
