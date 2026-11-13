import UIKit
import ARKit
import SceneKit
import simd
import AudioToolbox

/// UIViewController avec Auto-Capture basée sur le déplacement et vibration forte
final class ScanViewController: UIViewController {

    var viewModel: ScanViewModel!

    private var sceneView: ARSCNView!
    private lazy var aprilTagDetector = AprilTagDetector(tagSizeMm: GabaritConfig.tagSizeMm)
    private let analysisQueue = DispatchQueue(label: "com.gabaritscan.analysis", qos: .userInteractive)
    private var isProcessingFrame = false

    private var lastTransform: simd_float4x4? = nil
    private var lastTimestamp: TimeInterval = 0
    private var lastTagDetection: TagDetection? = nil

    // UI Overlays
    private var overlayView: ScanOverlayView!
    private var guideLabel:  UILabel!
    private var statusBadge: UILabel!
    private var captureBtn:  UIButton!
    private var generate3DBtn: UIButton!
    private var progressBar: UIProgressView!
    private var progressLbl: UILabel!
    private var flashView:   UIView!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupSceneView()
        setupUI()
        setupCallbacks()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startARSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }

    // MARK: - Configuration ARKit

    private func startARSession() {
        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravity

        // LiDAR activé si disponible (ne bloque pas si absent)
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
            statusBadge.text = "🟢 LiDAR Actif"
            statusBadge.textColor = UIColor(red: 0.2, green: 1.0, blue: 0.4, alpha: 1.0)
        } else {
            statusBadge.text = "📷 Mode Optique Auto"
            statusBadge.textColor = .cyan
        }

        sceneView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    private func setupSceneView() {
        sceneView = ARSCNView(frame: view.bounds)
        sceneView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sceneView.delegate = self
        sceneView.session.delegate = self
        sceneView.autoenablesDefaultLighting = true
        view.addSubview(sceneView)
    }

    // MARK: - UI Setup

    private func setupUI() {
        // Flash visuel pour chaque capture automatique
        flashView = UIView(frame: view.bounds)
        flashView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        flashView.backgroundColor = UIColor(red: 0.2, green: 1.0, blue: 0.4, alpha: 1.0)
        flashView.alpha = 0.0
        flashView.isUserInteractionEnabled = false
        view.addSubview(flashView)

        overlayView = ScanOverlayView(frame: view.bounds)
        overlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(overlayView)

        statusBadge = UILabel()
        statusBadge.text = "📷 Prêt"
        statusBadge.font = .systemFont(ofSize: 13, weight: .bold)
        statusBadge.textColor = .white
        statusBadge.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        statusBadge.layer.cornerRadius = 6
        statusBadge.clipsToBounds = true
        statusBadge.textAlignment = .center
        statusBadge.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusBadge)

        guideLabel = UILabel()
        guideLabel.text = "Pointez vers l'AprilTag pour commencer"
        guideLabel.textColor = .white
        guideLabel.font = .boldSystemFont(ofSize: 16)
        guideLabel.numberOfLines = 2
        guideLabel.textAlignment = .center
        guideLabel.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        guideLabel.layer.cornerRadius = 10
        guideLabel.clipsToBounds = true
        guideLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(guideLabel)

        progressBar = UIProgressView(progressViewStyle: .default)
        progressBar.tintColor = UIColor(red: 0.2, green: 0.9, blue: 0.4, alpha: 1)
        progressBar.trackTintColor = UIColor.white.withAlphaComponent(0.3)
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(progressBar)

        progressLbl = UILabel()
        progressLbl.text = "0 / 30 photos capturées"
        progressLbl.textColor = .white
        progressLbl.font = .systemFont(ofSize: 14, weight: .bold)
        progressLbl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(progressLbl)

        // Bouton de capture manuelle de secours
        captureBtn = UIButton(type: .custom)
        captureBtn.backgroundColor = .white
        captureBtn.layer.cornerRadius = 35
        captureBtn.layer.borderWidth = 4
        captureBtn.layer.borderColor = UIColor.lightGray.cgColor
        captureBtn.addTarget(self, action: #selector(onCaptureTapped), for: .touchUpInside)
        captureBtn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(captureBtn)

        // Bouton Générer 3D
        generate3DBtn = UIButton(type: .system)
        generate3DBtn.setTitle("Générer 3D 🎲", for: .normal)
        generate3DBtn.setTitleColor(.black, for: .normal)
        generate3DBtn.titleLabel?.font = .boldSystemFont(ofSize: 15)
        generate3DBtn.backgroundColor = UIColor(red: 0.2, green: 0.9, blue: 0.45, alpha: 1.0)
        generate3DBtn.layer.cornerRadius = 18
        generate3DBtn.addTarget(self, action: #selector(onGenerate3D), for: .touchUpInside)
        generate3DBtn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(generate3DBtn)

        NSLayoutConstraint.activate([
            statusBadge.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            statusBadge.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            statusBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 140),
            statusBadge.heightAnchor.constraint(equalToConstant: 26),

            guideLabel.topAnchor.constraint(equalTo: statusBadge.bottomAnchor, constant: 8),
            guideLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            guideLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            guideLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 45),

            captureBtn.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureBtn.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            captureBtn.widthAnchor.constraint(equalToConstant: 70),
            captureBtn.heightAnchor.constraint(equalToConstant: 70),

            generate3DBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            generate3DBtn.centerYAnchor.constraint(equalTo: captureBtn.centerYAnchor),
            generate3DBtn.widthAnchor.constraint(equalToConstant: 120),
            generate3DBtn.heightAnchor.constraint(equalToConstant: 44),

            progressBar.bottomAnchor.constraint(equalTo: captureBtn.topAnchor, constant: -16),
            progressBar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            progressBar.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.7),
            progressBar.heightAnchor.constraint(equalToConstant: 6),

            progressLbl.bottomAnchor.constraint(equalTo: progressBar.topAnchor, constant: -6),
            progressLbl.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }

    private func setupCallbacks() {
        // Flash et vibration à chaque photo automatique !
        viewModel.onPhotoCaptured = { [weak self] in
            guard let self = self else { return }
            self.triggerFlashAnimation()
        }

        viewModel.onScanCompleted = { [weak self] in
            guard let self = self else { return }
            self.onGenerate3D()
        }
    }

    private func triggerFlashAnimation() {
        UIView.animate(withDuration: 0.08, animations: {
            self.flashView.alpha = 0.45
        }) { _ in
            UIView.animate(withDuration: 0.15) {
                self.flashView.alpha = 0.0
            }
        }
    }

    @objc private func onCaptureTapped() {
        viewModel.onManualCapture()
        applyState(viewModel.state)
    }

    @objc private func onGenerate3D() {
        guard let currentFrame = sceneView.session.currentFrame else { return }

        let alert = UIAlertController(title: "Création 3D...", message: "Alignement sur l'AprilTag...", preferredStyle: .alert)
        present(alert, animated: true)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let result = MeshProcessingService.processAndExportMesh(
                from: currentFrame,
                tagDetection: self.lastTagDetection
            )

            DispatchQueue.main.async {
                alert.dismiss(animated: true) {
                    guard let (fileURL, scene) = result else {
                        let errAlert = UIAlertController(title: "Scan en cours", message: "Continuez à tourner autour de l'objet pour enregistrer plus de points.", preferredStyle: .alert)
                        errAlert.addAction(UIAlertAction(title: "OK", style: .default))
                        self.present(errAlert, animated: true)
                        return
                    }

                    let viewerVC = ModelViewerViewController()
                    viewerVC.modelScene = scene
                    viewerVC.modelFileURL = fileURL
                    viewerVC.modalPresentationStyle = .fullScreen
                    self.present(viewerVC, animated: true)
                }
            }
        }
    }

    @MainActor
    private func applyState(_ state: ScanState) {
        guideLabel.text = state.guideMessage
        overlayView.update(state: state)

        let total = viewModel.targetPhotoCount
        let current = viewModel.capturedCount
        let progress = total > 0 ? Float(current) / Float(total) : 0
        progressBar.setProgress(progress, animated: true)
        progressLbl.text = "\(current) / \(total) photos capturées 📸"
    }
}

// MARK: - ARSCNViewDelegate

extension ScanViewController: ARSCNViewDelegate {

    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        guard let meshAnchor = anchor as? ARMeshAnchor else { return nil }

        let geometry = SCNGeometry.from(arMeshGeometry: meshAnchor.geometry)
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(red: 0.1, green: 0.65, blue: 1.0, alpha: 0.35)
        material.fillMode = .lines
        geometry.materials = [material]

        return SCNNode(geometry: geometry)
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let meshAnchor = anchor as? ARMeshAnchor else { return }
        let geometry = SCNGeometry.from(arMeshGeometry: meshAnchor.geometry)
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(red: 0.1, green: 0.65, blue: 1.0, alpha: 0.35)
        material.fillMode = .lines
        geometry.materials = [material]
        node.geometry = geometry
    }
}

// MARK: - ARSessionDelegate

extension ScanViewController: ARSessionDelegate {

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard !isProcessingFrame else { return }
        isProcessingFrame = true

        let pixelBuffer = frame.capturedImage
        let intrinsicsMatrix = frame.camera.intrinsics

        let intrinsics = CameraIntrinsics(
            fx: intrinsicsMatrix[0][0],
            fy: intrinsicsMatrix[1][1],
            cx: intrinsicsMatrix[2][0],
            cy: intrinsicsMatrix[2][1]
        )
        self.viewModel.intrinsics = intrinsics

        let transform = frame.camera.transform
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

        let imageWidth = CVPixelBufferGetWidth(pixelBuffer)
        let imageHeight = CVPixelBufferGetHeight(pixelBuffer)
        let frameSize = CGSize(width: imageWidth, height: imageHeight)

        analysisQueue.async { [weak self] in
            guard let self = self else { return }
            let detections = self.aprilTagDetector.detect(pixelBuffer: pixelBuffer, intrinsics: intrinsics)

            Task { @MainActor in
                if let firstTag = detections.first {
                    self.lastTagDetection = firstTag
                }

                // Auto-capture déclenchée automatiquement par déplacement (7cm ou 10°)
                self.viewModel.onFrameProcessed(
                    cameraTransform: transform,
                    cameraVelocity: velocity,
                    tagDetections: detections,
                    frameSize: frameSize
                )

                self.applyState(self.viewModel.state)
                self.isProcessingFrame = false
            }
        }
    }
}
