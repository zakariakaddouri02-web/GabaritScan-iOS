import UIKit
import ARKit
import SceneKit
import simd
import AudioToolbox

/// UIViewController combinant la détection PractiCal (coins colorés, réticule)
/// et le mode objet Polycam (CropBox 3D, auto-capture et photogrammétrie)
final class ScanViewController: UIViewController {

    var viewModel: ScanViewModel!

    private var sceneView: ARSCNView!
    private lazy var aprilTagDetector = AprilTagDetector(tagSizeMm: GabaritConfig.tagSizeMm)
    private let analysisQueue = DispatchQueue(label: "com.gabaritscan.analysis", qos: .userInteractive)
    private var isProcessingFrame = false

    private var lastTransform: simd_float4x4? = nil
    private var lastTimestamp: TimeInterval = 0
    private var lastTagDetection: TagDetection? = nil
    private var latestPixelBuffer: CVPixelBuffer? = nil

    // Nœud 3D ancré dans la scène ARKit (Grille CAD + CropBox Polycam + Axes)
    private var tagAnchorNode: SCNNode? = nil

    // Calcul du taux de détection (det/s)
    private var frameCounter: Int = 0
    private var lastFpsTimestamp: TimeInterval = 0
    private var currentDetPerSec: Double = 0.0

    // UI Overlays & Contrôles PractiCal / Polycam
    private var overlayView: ScanOverlayView!
    private var flashView:   UIView!
    private var bottomHUD:   UIView!
    private var calibrateBtn: UIButton!
    private var tabFieldBtn:  UIButton!
    private var tabAlignBtn:  UIButton!
    private var tabExportBtn: UIButton!
    private var tabResetBtn:  UIButton!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupSceneView()
        setupUI()
        setupCallbacks()
        PhotogrammetryService.shared.startNewSession()
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

    // MARK: - Interface Utilisateur Style PractiCal (Image 1)

    private func setupUI() {
        flashView = UIView(frame: view.bounds)
        flashView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        flashView.backgroundColor = UIColor(red: 0.2, green: 1.0, blue: 0.4, alpha: 1.0)
        flashView.alpha = 0.0
        flashView.isUserInteractionEnabled = false
        view.addSubview(flashView)

        overlayView = ScanOverlayView(frame: view.bounds)
        overlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(overlayView)

        bottomHUD = UIView()
        bottomHUD.backgroundColor = UIColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 0.92)
        bottomHUD.layer.cornerRadius = 24
        bottomHUD.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        bottomHUD.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomHUD)

        calibrateBtn = UIButton(type: .system)
        calibrateBtn.setTitle("▶ Calibrate / Fixer", for: .normal)
        calibrateBtn.setTitleColor(.white, for: .normal)
        calibrateBtn.titleLabel?.font = .systemFont(ofSize: 17, weight: .heavy)
        calibrateBtn.backgroundColor = UIColor(red: 0.15, green: 0.78, blue: 0.35, alpha: 1.0)
        calibrateBtn.layer.cornerRadius = 24
        calibrateBtn.addTarget(self, action: #selector(onCalibrateTapped), for: .touchUpInside)
        calibrateBtn.translatesAutoresizingMaskIntoConstraints = false
        bottomHUD.addSubview(calibrateBtn)

        tabExportBtn = createTabButton(title: "Export", action: #selector(onExportTapped))
        tabFieldBtn  = createTabButton(title: "3D Field", action: #selector(onFieldTapped), isHighlighted: true)
        tabAlignBtn  = createTabButton(title: "Align ┼", action: #selector(onAlignTapped))
        tabResetBtn  = createTabButton(title: "Clear", action: #selector(onResetTapped))

        let tabsStack = UIStackView(arrangedSubviews: [tabExportBtn, tabFieldBtn, tabAlignBtn, tabResetBtn])
        tabsStack.axis = .horizontal
        tabsStack.distribution = .fillEqually
        tabsStack.spacing = 8
        tabsStack.translatesAutoresizingMaskIntoConstraints = false
        bottomHUD.addSubview(tabsStack)

        NSLayoutConstraint.activate([
            bottomHUD.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomHUD.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomHUD.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomHUD.heightAnchor.constraint(equalToConstant: 145),

            calibrateBtn.topAnchor.constraint(equalTo: bottomHUD.topAnchor, constant: 14),
            calibrateBtn.trailingAnchor.constraint(equalTo: bottomHUD.trailingAnchor, constant: -16),
            calibrateBtn.leadingAnchor.constraint(equalTo: bottomHUD.leadingAnchor, constant: 16),
            calibrateBtn.heightAnchor.constraint(equalToConstant: 48),

            tabsStack.topAnchor.constraint(equalTo: calibrateBtn.bottomAnchor, constant: 12),
            tabsStack.leadingAnchor.constraint(equalTo: bottomHUD.leadingAnchor, constant: 16),
            tabsStack.trailingAnchor.constraint(equalTo: bottomHUD.trailingAnchor, constant: -16),
            tabsStack.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    private func createTabButton(title: String, action: Selector, isHighlighted: Bool = false) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.setTitleColor(isHighlighted ? .white : UIColor(white: 0.7, alpha: 1.0), for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 14, weight: isHighlighted ? .bold : .medium)
        btn.backgroundColor = isHighlighted ? UIColor(red: 0.1, green: 0.45, blue: 0.95, alpha: 0.9) : UIColor(white: 0.18, alpha: 0.8)
        btn.layer.cornerRadius = 10
        btn.addTarget(self, action: action, for: .touchUpInside)
        return btn
    }

    private func setupCallbacks() {
        viewModel.onPhotoCaptured = { [weak self] in
            guard let self = self else { return }
            self.triggerFlashAnimation()

            // Sauvegarde de l'image haute définition pour Polycam Object Mode
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
            self.anchorCADSceneInWorld(transform: worldTransform)
        }
    }

    // MARK: - Ancrage 3D Polycam Object Mode & Grille CAD dans le Monde ARKit

    private func anchorCADSceneInWorld(transform: simd_float4x4) {
        guard tagAnchorNode == nil else { return }

        let container = SCNNode()
        container.simdTransform = transform

        // 1. Grille 3D CAD métrique sur la surface (Image 2)
        let grid = CADSceneBuilder.createGrid(sizeMeters: 0.9, stepMeters: 0.05, isVertical: false)
        container.addChildNode(grid)

        // 2. Grille verticale murale (Image 2)
        let wallGrid = CADSceneBuilder.createGrid(sizeMeters: 0.9, stepMeters: 0.05, isVertical: true)
        container.addChildNode(wallGrid)

        // 3. Axes 3D (X: Orange, Y: Vert, Z: Cyan)
        let axes = CADSceneBuilder.createAxes(length: 0.09)
        container.addChildNode(axes)

        // 4. 3D Bounding Box Polycam ("cropBox")
        let polycamCropBox = CADSceneBuilder.createPolycamCropBox(
            width: 0.28,
            height: 0.18,
            depth: 0.22,
            position: SCNVector3(0, 0.09, 0)
        )
        container.addChildNode(polycamCropBox)

        // 5. Rectangles calibrés virtuels ("Rectangle 1" Cyan et Magenta style Image 2 & 3)
        let rect1 = CADSceneBuilder.createCalibratedRectangle(
            width: 0.20,
            height: 0.14,
            color: UIColor(red: 0.1, green: 0.85, blue: 0.95, alpha: 1.0),
            label: "Rectangle 1",
            position: SCNVector3(0, 0.11, 0)
        )
        container.addChildNode(rect1)

        // 6. Cadre AprilTag 80mm
        let tagPlane = SCNPlane(width: CGFloat(GabaritConfig.tagSizeMm / 1000.0),
                                height: CGFloat(GabaritConfig.tagSizeMm / 1000.0))
        tagPlane.cornerRadius = 0.003
        let tagMat = SCNMaterial()
        tagMat.diffuse.contents = UIColor.yellow.withAlphaComponent(0.35)
        tagMat.isDoubleSided = true
        tagPlane.materials = [tagMat]
        container.addChildNode(SCNNode(geometry: tagPlane))

        sceneView.scene.rootNode.addChildNode(container)
        tagAnchorNode = container
        print("🏛️ Scène 3D Polycam & CAD ancrée dans le monde ARKit !")
    }

    // MARK: - Actions des Boutons

    @objc private func onCalibrateTapped() {
        if let currentTag = lastTagDetection, !viewModel.isTagLocked {
            viewModel.onManualCapture()
            calibrateBtn.setTitle("✔ Calibré (Polycam Mode)", for: .normal)
            calibrateBtn.backgroundColor = UIColor(red: 0.1, green: 0.5, blue: 0.9, alpha: 1.0)
        } else {
            viewModel.onManualCapture()
        }
    }

    @objc private func onFieldTapped() {
        guard let currentFrame = sceneView.session.currentFrame else { return }

        let alert = UIAlertController(title: "Reconstruction 3D", message: "Traitement du modèle Polycam...", preferredStyle: .alert)
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

    @objc private func onAlignTapped() {
        overlayView.showCrosshairs.toggle()
        tabAlignBtn.backgroundColor = overlayView.showCrosshairs ?
            UIColor(red: 0.1, green: 0.45, blue: 0.95, alpha: 0.9) : UIColor(white: 0.18, alpha: 0.8)
    }

    @objc private func onResetTapped() {
        tagAnchorNode?.removeFromParentNode()
        tagAnchorNode = nil
        viewModel.unlockTag()
        calibrateBtn.setTitle("▶ Calibrate / Fixer", for: .normal)
        calibrateBtn.backgroundColor = UIColor(red: 0.15, green: 0.78, blue: 0.35, alpha: 1.0)
        PhotogrammetryService.shared.startNewSession()
    }

    @objc private func onExportTapped() {
        onFieldTapped()
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
            frameCounter = 0
            lastFpsTimestamp = nowTime
        }

        if let featurePoints = frame.rawFeaturePoints?.points {
            viewModel.addFeaturePoints(featurePoints)
        }

        guard !isProcessingFrame else { return }
        isProcessingFrame = true

        let pixelBuffer = frame.capturedImage
        self.latestPixelBuffer = pixelBuffer
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

        let imgW = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let imgH = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let imageSize = CGSize(width: imgW, height: imgH)

        let displayTransform = frame.displayTransform(for: .portrait, viewportSize: sceneView.bounds.size)

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
                    frameSize: imageSize
                )

                self.overlayView.update(
                    detections: detections,
                    transform: displayTransform,
                    imgSize: imageSize,
                    tracking: true,
                    locked: self.viewModel.isTagLocked,
                    fps: self.currentDetPerSec
                )

                self.isProcessingFrame = false
            }
        }
    }
}
