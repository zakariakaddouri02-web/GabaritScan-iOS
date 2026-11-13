import UIKit
import ARKit
import SceneKit
import simd
import AudioToolbox

/// UIViewController avec Auto-Capture basée sur le déplacement, vibration forte et repère AprilTag verrouillé
final class ScanViewController: UIViewController {

    var viewModel: ScanViewModel!

    private var sceneView: ARSCNView!
    private lazy var aprilTagDetector = AprilTagDetector(tagSizeMm: GabaritConfig.tagSizeMm)
    private let analysisQueue = DispatchQueue(label: "com.gabaritscan.analysis", qos: .userInteractive)
    private var isProcessingFrame = false

    private var lastTransform: simd_float4x4? = nil
    private var lastTimestamp: TimeInterval = 0
    private var lastTagDetection: TagDetection? = nil

    // Nœud 3D ancré de manière permanente dans la scène ARKit
    private var tagAnchorNode: SCNNode? = nil

    // UI Overlays
    private var overlayView: ScanOverlayView!
    private var guideLabel:  UILabel!
    private var statusBadge: UIButton!
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

        // Activer la reconstruction si supportée (sans bloquer si le LiDAR est inactif)
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

        statusBadge = UIButton(type: .system)
        statusBadge.setTitle("📷 Visez l'AprilTag", for: .normal)
        statusBadge.setTitleColor(.white, for: .normal)
        statusBadge.titleLabel?.font = .systemFont(ofSize: 13, weight: .bold)
        statusBadge.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        statusBadge.layer.cornerRadius = 8
        statusBadge.clipsToBounds = true
        statusBadge.contentEdgeInsets = UIEdgeInsets(top: 4, left: 12, bottom: 4, right: 12)
        statusBadge.addTarget(self, action: #selector(onStatusBadgeTapped), for: .touchUpInside)
        statusBadge.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusBadge)

        guideLabel = UILabel()
        guideLabel.text = "Pointez vers l'AprilTag pour verrouiller le repère"
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
            statusBadge.heightAnchor.constraint(equalToConstant: 28),

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
        // Flash visuel à chaque capture automatique
        viewModel.onPhotoCaptured = { [weak self] in
            guard let self = self else { return }
            self.triggerFlashAnimation()
        }

        // Ancrage 3D physique immédiat de l'AprilTag dans le monde
        viewModel.onTagLockedFirstTime = { [weak self] worldTransform in
            guard let self = self else { return }
            self.anchorTagIn3DScene(transform: worldTransform)
        }

        viewModel.onScanCompleted = { [weak self] in
            guard let self = self else { return }
            self.onGenerate3D()
        }
    }

    // MARK: - Ancrage 3D Permanent de l'AprilTag dans la scène ARKit

    private func anchorTagIn3DScene(transform: simd_float4x4) {
        guard tagAnchorNode == nil else { return }

        let container = SCNNode()
        container.simdTransform = transform

        // 1. Plan 80mm x 80mm centré sur l'AprilTag
        let plane = SCNPlane(width: CGFloat(GabaritConfig.tagSizeMm / 1000.0),
                             height: CGFloat(GabaritConfig.tagSizeMm / 1000.0))
        plane.cornerRadius = 0.003
        let planeMat = SCNMaterial()
        planeMat.diffuse.contents = UIColor.yellow.withAlphaComponent(0.45)
        planeMat.isDoubleSided = true
        plane.materials = [planeMat]
        let planeNode = SCNNode(geometry: plane)
        container.addChildNode(planeNode)

        // 2. Axes 3D (X: Rouge 5cm, Y: Vert 5cm, Z: Bleu 5cm)
        let axisLen: Float = 0.05
        let xAxis = SCNGeometry.line(from: SCNVector3Zero, to: SCNVector3(axisLen, 0, 0), color: .systemRed)
        let yAxis = SCNGeometry.line(from: SCNVector3Zero, to: SCNVector3(0, axisLen, 0), color: .systemGreen)
        let zAxis = SCNGeometry.line(from: SCNVector3Zero, to: SCNVector3(0, 0, axisLen), color: .systemCyan)
        container.addChildNode(SCNNode(geometry: xAxis))
        container.addChildNode(SCNNode(geometry: yAxis))
        container.addChildNode(SCNNode(geometry: zAxis))

        sceneView.scene.rootNode.addChildNode(container)
        tagAnchorNode = container
        print("📌 AprilTag ancré et verrouillé de manière fixe dans la scène 3D !")
    }

    @objc private func onStatusBadgeTapped() {
        if viewModel.isTagLocked {
            let alert = UIAlertController(title: "Repère Fixé 🔒", message: "Voulez-vous réinitialiser et re-pointer l'AprilTag ?", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Recalibrer", style: .destructive) { [weak self] _ in
                self?.tagAnchorNode?.removeFromParentNode()
                self?.tagAnchorNode = nil
                self?.viewModel.unlockTag()
            })
            alert.addAction(UIAlertAction(title: "Conserver", style: .cancel))
            present(alert, animated: true)
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

        let lockedTransform = viewModel.lockedTagWorldTransform
        let points = viewModel.accumulatedPoints
        let tagDet = self.lastTagDetection

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
                    guard let (fileURL, scene) = result else {
                        let errAlert = UIAlertController(
                            title: "Scan en cours",
                            message: "Pointez l'AprilTag et tournez autour du gabarit pour accumuler des points 3D.",
                            preferredStyle: .alert
                        )
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

        if viewModel.isTagLocked {
            statusBadge.setTitle("🔒 Repère Fixé (80mm)", for: .normal)
            statusBadge.setTitleColor(UIColor(red: 0.2, green: 1.0, blue: 0.4, alpha: 1.0), for: .normal)
        } else {
            statusBadge.setTitle("📷 Visez l'AprilTag", for: .normal)
            statusBadge.setTitleColor(.cyan, for: .normal)
        }

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
        // Collecte continue des points 3D optiques (fonctionne sans aucun LiDAR !)
        if let featurePoints = frame.rawFeaturePoints?.points {
            viewModel.addFeaturePoints(featurePoints)
        }

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
