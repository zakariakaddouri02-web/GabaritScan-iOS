import UIKit
import ARKit
import SceneKit
import simd

// MARK: - Polycam color constants

private enum PolycamColor {
    static let background  = UIColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1)
    static let surface     = UIColor(red: 0.102, green: 0.102, blue: 0.118, alpha: 1)
    static let accent      = UIColor(red: 0.0, green: 0.898, blue: 0.816, alpha: 1)
    static let textPrimary = UIColor.white
    static let textSec     = UIColor(white: 0.6, alpha: 1)
    static let ringTrack   = UIColor(white: 0.25, alpha: 1)
}

/// Full-screen dark-theme scan screen, Polycam Object Mode style.
final class ScanViewController: UIViewController {

    var viewModel: ScanViewModel!

    // ARKit
    private var sceneView: ARSCNView!
    private lazy var aprilTagDetector = AprilTagDetector(tagSizeMm: GabaritConfig.tagSizeMm)
    private let analysisQueue = DispatchQueue(label: "com.gabaritscan.analysis", qos: .userInteractive)
    private var isProcessingFrame = false
    private var lastTransform: simd_float4x4? = nil
    private var lastTimestamp: TimeInterval = 0
    private var lastTagDetection: TagDetection? = nil
    private var latestPixelBuffer: CVPixelBuffer? = nil
    private var tagAnchorNode: SCNNode? = nil
    private var frameCounter: Int = 0
    private var lastFpsTimestamp: TimeInterval = 0
    private var currentDetPerSec: Double = 0.0

    // Overlay & UI
    private var overlayView: ScanOverlayView!
    private var flashView: UIView!

    // Top bar
    private var topBar: UIView!
    private var backButton: UIButton!
    private var titleLabel: UILabel!
    private var shareButton: UIButton!

    // Status pill (top-right)
    private var statusPill: UIView!
    private var statusDot: UIView!
    private var statusLabel: UILabel!

    // Scan ring
    private var ringContainerView: UIView!
    private var ringTrackLayer: CAShapeLayer!
    private var ringProgressLayer: CAShapeLayer!
    private var ringPercentLabel: UILabel!
    private var photoCountLabel: UILabel!

    // Motion hint
    private var motionHintLabel: UILabel!

    // Toast
    private var toastLabel: UILabel!
    private var toastTimer: Timer?

    // Bottom sheet
    private var bottomSheet: UIView!
    private var captureButton: UIButton!
    private var fixButton: UIButton!
    private var doneButton: UIButton!

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = PolycamColor.background
        setupSceneView()
        setupOverlay()
        setupTopBar()
        setupStatusPill()
        setupScanRing()
        setupMotionHint()
        setupToast()
        setupBottomSheet()
        setupCallbacks()
        PhotogrammetryService.shared.startNewSession()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
        startARSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }

    override var prefersStatusBarHidden: Bool { true }

    // MARK: - ARKit Setup

    private func startARSession() {
        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravity
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        sceneView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    private func setupSceneView() {
        sceneView = ARSCNView(frame: view.bounds)
        sceneView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sceneView.delegate = self
        sceneView.session.delegate = self
        sceneView.autoenablesDefaultLighting = true
        sceneView.backgroundColor = .black
        view.addSubview(sceneView)
    }

    // MARK: - Overlay

    private func setupOverlay() {
        flashView = UIView(frame: view.bounds)
        flashView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        flashView.backgroundColor = .white
        flashView.alpha = 0.0
        flashView.isUserInteractionEnabled = false
        view.addSubview(flashView)

        overlayView = ScanOverlayView(frame: view.bounds)
        overlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(overlayView)
    }

    // MARK: - Top Bar

    private func setupTopBar() {
        topBar = UIView()
        topBar.backgroundColor = .clear
        topBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topBar)

        backButton = UIButton(type: .system)
        backButton.setTitle("", for: .normal) // chevron.left
        backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton.tintColor = PolycamColor.textPrimary
        backButton.addTarget(self, action: #selector(onBackTapped), for: .touchUpInside)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(backButton)

        titleLabel = UILabel()
        titleLabel.text = "GabaritScan"
        titleLabel.textColor = PolycamColor.textPrimary
        titleLabel.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(titleLabel)

        shareButton = UIButton(type: .system)
        shareButton.setImage(UIImage(systemName: "square.and.arrow.up"), for: .normal)
        shareButton.tintColor = PolycamColor.textPrimary
        shareButton.addTarget(self, action: #selector(onShareTapped), for: .touchUpInside)
        shareButton.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(shareButton)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 48),

            backButton.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 16),
            backButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 40),
            backButton.heightAnchor.constraint(equalToConstant: 40),

            titleLabel.centerXAnchor.constraint(equalTo: topBar.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),

            shareButton.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -16),
            shareButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            shareButton.widthAnchor.constraint(equalToConstant: 40),
            shareButton.heightAnchor.constraint(equalToConstant: 40)
        ])
    }

    // MARK: - Status Pill

    private func setupStatusPill() {
        statusPill = UIView()
        statusPill.backgroundColor = UIColor(white: 0.12, alpha: 0.9)
        statusPill.layer.cornerRadius = 12
        statusPill.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusPill)

        statusDot = UIView()
        statusDot.backgroundColor = UIColor(red: 0.2, green: 0.9, blue: 0.4, alpha: 1.0)
        statusDot.layer.cornerRadius = 4
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        statusPill.addSubview(statusDot)

        statusLabel = UILabel()
        statusLabel.text = "Suivi actif"
        statusLabel.textColor = PolycamColor.textPrimary
        statusLabel.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusPill.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            statusPill.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 8),
            statusPill.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            statusPill.heightAnchor.constraint(equalToConstant: 24),

            statusDot.leadingAnchor.constraint(equalTo: statusPill.leadingAnchor, constant: 8),
            statusDot.centerYAnchor.constraint(equalTo: statusPill.centerYAnchor),
            statusDot.widthAnchor.constraint(equalToConstant: 8),
            statusDot.heightAnchor.constraint(equalToConstant: 8),

            statusLabel.leadingAnchor.constraint(equalTo: statusDot.trailingAnchor, constant: 4),
            statusLabel.trailingAnchor.constraint(equalTo: statusPill.trailingAnchor, constant: -8),
            statusLabel.centerYAnchor.constraint(equalTo: statusPill.centerYAnchor)
        ])
    }

    // MARK: - Scan Ring

    private func setupScanRing() {
        ringContainerView = UIView()
        ringContainerView.backgroundColor = .clear
        ringContainerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(ringContainerView)

        let ringDiameter: CGFloat = 90
        let ringRadius: CGFloat   = ringDiameter / 2 - 6

        // Track layer (grey background)
        ringTrackLayer = CAShapeLayer()
        ringTrackLayer.frame = CGRect(x: 0, y: 0, width: ringDiameter, height: ringDiameter)
        let center = CGPoint(x: ringDiameter / 2, y: ringDiameter / 2)
        let circlePath = UIBezierPath(arcCenter: center, radius: ringRadius, startAngle: -.pi / 2, endAngle: .pi * 1.5, clockwise: true)
        ringTrackLayer.path = circlePath.cgPath
        ringTrackLayer.strokeColor = PolycamColor.ringTrack.cgColor
        ringTrackLayer.fillColor   = UIColor.clear.cgColor
        ringTrackLayer.lineWidth   = 5
        ringTrackLayer.lineCap     = .round

        // Progress layer (teal)
        ringProgressLayer = CAShapeLayer()
        ringProgressLayer.frame = CGRect(x: 0, y: 0, width: ringDiameter, height: ringDiameter)
        ringProgressLayer.path         = circlePath.cgPath
        ringProgressLayer.strokeColor  = PolycamColor.accent.cgColor
        ringProgressLayer.fillColor    = UIColor.clear.cgColor
        ringProgressLayer.lineWidth    = 5
        ringProgressLayer.lineCap      = .round
        ringProgressLayer.strokeEnd    = 0.0

        // Percent label centered in the ring
        ringPercentLabel = UILabel()
        ringPercentLabel.text          = "0%"
        ringPercentLabel.textColor     = PolycamColor.textPrimary
        ringPercentLabel.font          = UIFont.systemFont(ofSize: 18, weight: .bold)
        ringPercentLabel.textAlignment = .center
        ringPercentLabel.translatesAutoresizingMaskIntoConstraints = false

        // Photo count label below ring
        photoCountLabel = UILabel()
        photoCountLabel.text          = "0 / 30 photos"
        photoCountLabel.textColor     = PolycamColor.accent
        photoCountLabel.font          = UIFont.systemFont(ofSize: 13, weight: .medium)
        photoCountLabel.textAlignment = .center
        photoCountLabel.translatesAutoresizingMaskIntoConstraints = false

        ringContainerView.layer.addSublayer(ringTrackLayer)
        ringContainerView.layer.addSublayer(ringProgressLayer)
        ringContainerView.addSubview(ringPercentLabel)
        ringContainerView.addSubview(photoCountLabel)

        NSLayoutConstraint.activate([
            ringContainerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            ringContainerView.widthAnchor.constraint(equalToConstant: ringDiameter),
            ringContainerView.heightAnchor.constraint(equalToConstant: ringDiameter + 28),

            ringPercentLabel.centerXAnchor.constraint(equalTo: ringContainerView.centerXAnchor),
            ringPercentLabel.centerYAnchor.constraint(equalTo: ringContainerView.topAnchor, constant: ringDiameter / 2),

            photoCountLabel.topAnchor.constraint(equalTo: ringContainerView.topAnchor, constant: ringDiameter + 4),
            photoCountLabel.centerXAnchor.constraint(equalTo: ringContainerView.centerXAnchor)
        ])
    }

    // MARK: - Motion Hint

    private func setupMotionHint() {
        motionHintLabel = UILabel()
        motionHintLabel.text          = "Tournez lentement autour de l'objet"
        motionHintLabel.textColor     = PolycamColor.textPrimary
        motionHintLabel.font          = UIFont.systemFont(ofSize: 14, weight: .regular)
        motionHintLabel.textAlignment = .center
        motionHintLabel.numberOfLines = 2
        motionHintLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(motionHintLabel)
    }

    // MARK: - Toast Banner

    private func setupToast() {
        toastLabel = UILabel()
        toastLabel.textColor     = PolycamColor.textPrimary
        toastLabel.font          = UIFont.systemFont(ofSize: 14, weight: .semibold)
        toastLabel.textAlignment = .center
        toastLabel.backgroundColor = UIColor(white: 0.1, alpha: 0.88)
        toastLabel.layer.cornerRadius = 12
        toastLabel.layer.masksToBounds = true
        toastLabel.alpha = 0
        toastLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toastLabel)

        NSLayoutConstraint.activate([
            toastLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toastLabel.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 48),
            toastLabel.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -40),
            toastLabel.heightAnchor.constraint(equalToConstant: 40)
        ])
    }

    private func showToast(_ message: String) {
        toastLabel.text = "  \(message)  "
        toastTimer?.invalidate()
        UIView.animate(withDuration: 0.3) { self.toastLabel.alpha = 1 }
        toastTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            UIView.animate(withDuration: 0.4) { self?.toastLabel.alpha = 0 }
        }
    }

    // MARK: - Bottom Sheet

    private func setupBottomSheet() {
        bottomSheet = UIView()
        bottomSheet.backgroundColor = PolycamColor.surface
        bottomSheet.layer.cornerRadius = 24
        bottomSheet.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        bottomSheet.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomSheet)

        // — Capture button (large white circle) —
        captureButton = UIButton(type: .custom)
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        captureButton.backgroundColor = .white
        captureButton.layer.cornerRadius = 35
        captureButton.layer.borderColor = UIColor.white.cgColor
        captureButton.layer.borderWidth = 4
        captureButton.addTarget(self, action: #selector(onCaptureTapped), for: .touchUpInside)

        // Inner grey ring (visual only via sublayer)
        let innerRing = CAShapeLayer()
        innerRing.path = UIBezierPath(arcCenter: CGPoint(x: 35, y: 35), radius: 28, startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath
        innerRing.strokeColor = UIColor(white: 0.5, alpha: 0.5).cgColor
        innerRing.fillColor   = UIColor.clear.cgColor
        innerRing.lineWidth   = 2
        captureButton.layer.addSublayer(innerRing)

        // — Fix button (left) —
        fixButton = UIButton(type: .system)
        fixButton.translatesAutoresizingMaskIntoConstraints = false
        fixButton.setTitle("🔒 Fixer", for: .normal)
        fixButton.setTitleColor(PolycamColor.textSec, for: .normal)
        fixButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        fixButton.addTarget(self, action: #selector(onFixTapped), for: .touchUpInside)

        // — Done button (right) —
        doneButton = UIButton(type: .system)
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.setTitle("Terminer", for: .normal)
        doneButton.setTitleColor(PolycamColor.accent, for: .normal)
        doneButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        doneButton.addTarget(self, action: #selector(onGenerate3D), for: .touchUpInside)

        bottomSheet.addSubview(captureButton)
        bottomSheet.addSubview(fixButton)
        bottomSheet.addSubview(doneButton)

        let sheetHeight: CGFloat = 130
        let ringBottomOffset: CGFloat = sheetHeight + 60

        NSLayoutConstraint.activate([
            bottomSheet.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomSheet.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomSheet.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomSheet.heightAnchor.constraint(equalToConstant: sheetHeight),

            captureButton.centerXAnchor.constraint(equalTo: bottomSheet.centerXAnchor),
            captureButton.topAnchor.constraint(equalTo: bottomSheet.topAnchor, constant: 20),
            captureButton.widthAnchor.constraint(equalToConstant: 70),
            captureButton.heightAnchor.constraint(equalToConstant: 70),

            fixButton.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor),
            fixButton.trailingAnchor.constraint(equalTo: captureButton.leadingAnchor, constant: -28),

            doneButton.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor),
            doneButton.leadingAnchor.constraint(equalTo: captureButton.trailingAnchor, constant: 28),

            // Ring positioned above the bottom sheet
            ringContainerView.bottomAnchor.constraint(equalTo: bottomSheet.topAnchor, constant: -20),
            motionHintLabel.bottomAnchor.constraint(equalTo: bottomSheet.topAnchor, constant: -8),
            motionHintLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            motionHintLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])
    }

    // MARK: - Callbacks

    private func setupCallbacks() {
        viewModel.onPhotoCaptured = { [weak self] in
            guard let self = self else { return }
            self.triggerFlashAnimation()
            self.updateRingDisplay()

            if let pb = self.latestPixelBuffer, let camT = self.lastTransform {
                PhotogrammetryService.shared.captureFrame(
                    pixelBuffer: pb,
                    cameraTransform: camT,
                    intrinsics: self.viewModel.intrinsics
                )
            }
        }

        viewModel.onTagLockedFirstTime = { [weak self] worldTransform in
            guard let self = self else { return }
            self.anchorTagAxesInWorld(transform: worldTransform)
            self.showToast("🔒 Repère fixé – Tournez autour de l'objet")
        }

        viewModel.onScanCompleted = { [weak self] in
            self?.showToast("🎉 Scan complet ! Appuyez sur Terminer")
        }
    }

    // MARK: - Minimal tag anchor (small axes only)

    private func anchorTagAxesInWorld(transform: simd_float4x4) {
        guard tagAnchorNode == nil else { return }
        let container = SCNNode()
        container.simdTransform = transform

        // Small subtle axes 2 cm
        let axisLen: Float = 0.02
        func axis(to: SCNVector3, color: UIColor) -> SCNNode {
            SCNNode(geometry: SCNGeometry.line(from: SCNVector3Zero, to: to, color: color))
        }
        container.addChildNode(axis(to: SCNVector3(axisLen, 0, 0), color: UIColor(red: 1, green: 0.4, blue: 0, alpha: 0.8)))
        container.addChildNode(axis(to: SCNVector3(0, axisLen, 0), color: UIColor(red: 0.3, green: 0.9, blue: 0.1, alpha: 0.8)))
        container.addChildNode(axis(to: SCNVector3(0, 0, axisLen), color: PolycamColor.accent.withAlphaComponent(0.8)))

        sceneView.scene.rootNode.addChildNode(container)
        tagAnchorNode = container
    }

    // MARK: - Ring update

    private func updateRingDisplay() {
        let progress = viewModel.scanProgressPercent
        let pct = Int(round(progress * 100))
        ringPercentLabel.text = "\(pct)%"
        photoCountLabel.text  = "\(viewModel.capturedCount) / \(viewModel.targetPhotoCount) photos"

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.3)
        ringProgressLayer.strokeEnd = CGFloat(progress)
        CATransaction.commit()
    }

    private func updateMotionHint() {
        switch viewModel.motionState {
        case .idle:
            motionHintLabel.text = viewModel.isTagLocked
                ? "Bougez pour commencer à capturer"
                : "Pointez l'AprilTag pour démarrer"
        case .scanning:
            motionHintLabel.text = "Tournez lentement autour de l'objet"
        case .tooFast:
            motionHintLabel.text = "⚠ Ralentissez !"
        case .complete:
            motionHintLabel.text = "Scan complet ! Appuyez sur Terminer"
        }
    }

    // MARK: - Flash

    private func triggerFlashAnimation() {
        UIView.animate(withDuration: 0.07, animations: { self.flashView.alpha = 0.35 }) { _ in
            UIView.animate(withDuration: 0.15) { self.flashView.alpha = 0 }
        }
    }

    // MARK: - Button Actions

    @objc private func onBackTapped() {
        dismiss(animated: true)
    }

    @objc private func onShareTapped() {
        // Placeholder — will be linked after scan
    }

    @objc private func onCaptureTapped() {
        viewModel.onManualCapture()
        updateRingDisplay()
    }

    @objc private func onFixTapped() {
        if viewModel.isTagLocked {
            viewModel.unlockTag()
            tagAnchorNode?.removeFromParentNode()
            tagAnchorNode = nil
            fixButton.setTitle("🔒 Fixer", for: .normal)
            showToast("Repère déverrouillé")
        } else {
            showToast("Pointez d'abord l'AprilTag")
        }
    }

    @objc private func onGenerate3D() {
        guard let currentFrame = sceneView.session.currentFrame else { return }

        let alert = UIAlertController(title: "Reconstruction 3D", message: "Génération du modèle…", preferredStyle: .alert)
        present(alert, animated: true)

        let lockedTransform = viewModel.lockedTagWorldTransform
        let points          = viewModel.accumulatedPoints
        let tagDet          = self.lastTagDetection

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let result = MeshProcessingService.processAndExportMesh(
                from: currentFrame,
                lockedTagTransform: lockedTransform,
                tagDetection: tagDet,
                featurePoints: points
            )
            DispatchQueue.main.async {
                alert.dismiss(animated: true) {
                    guard let (fileURL, scene) = result else { return }
                    let viewerVC = ModelViewerViewController()
                    viewerVC.modelScene = scene
                    viewerVC.modelFileURL = fileURL
                    viewerVC.modalPresentationStyle = .fullScreen
                    self.present(viewerVC, animated: true)
                }
            }
        }
    }
}

// MARK: - ARSCNViewDelegate

extension ScanViewController: ARSCNViewDelegate {}

// MARK: - ARSessionDelegate

extension ScanViewController: ARSessionDelegate {

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        frameCounter += 1
        let nowTime = ProcessInfo.processInfo.systemUptime
        if nowTime - lastFpsTimestamp >= 0.5 {
            currentDetPerSec = Double(frameCounter) / (nowTime - lastFpsTimestamp)
            frameCounter     = 0
            lastFpsTimestamp = nowTime
        }

        if let featurePoints = frame.rawFeaturePoints?.points {
            viewModel.addFeaturePoints(featurePoints)
        }

        guard !isProcessingFrame else { return }
        isProcessingFrame = true

        let pixelBuffer    = frame.capturedImage
        self.latestPixelBuffer = pixelBuffer
        let intrinsicsMatrix   = frame.camera.intrinsics

        let intrinsics = CameraIntrinsics(
            fx: intrinsicsMatrix[0][0],
            fy: intrinsicsMatrix[1][1],
            cx: intrinsicsMatrix[2][0],
            cy: intrinsicsMatrix[2][1]
        )
        self.viewModel.intrinsics = intrinsics

        let transform = frame.camera.transform
        let now       = frame.timestamp

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

        let imgW       = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let imgH       = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let imageSize  = CGSize(width: imgW, height: imgH)
        let displayTx  = frame.displayTransform(for: .portrait, viewportSize: sceneView.bounds.size)

        analysisQueue.async { [weak self] in
            guard let self = self else { return }
            let detections = self.aprilTagDetector.detect(pixelBuffer: pixelBuffer, intrinsics: intrinsics)

            Task { @MainActor in
                if let firstTag = detections.first { self.lastTagDetection = firstTag }

                self.viewModel.onFrameProcessed(
                    cameraTransform: transform,
                    cameraVelocity:  velocity,
                    tagDetections:   detections,
                    frameSize:       imageSize
                )

                self.overlayView.update(
                    detections: detections,
                    transform:  displayTx,
                    imgSize:    imageSize,
                    tracking:   true,
                    locked:     self.viewModel.isTagLocked,
                    fps:        self.currentDetPerSec
                )

                self.updateMotionHint()
                self.isProcessingFrame = false
            }
        }
    }
}
