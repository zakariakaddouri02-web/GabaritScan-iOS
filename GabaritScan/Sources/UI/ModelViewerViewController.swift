import UIKit
import SceneKit
import QuickLook

// MARK: - Polycam-style 3D model viewer avec Texture Réelle & Export GLB

final class ModelViewerViewController: UIViewController {

    var modelScene: SCNScene?
    var glbFileURL: URL?
    var usdzFileURL: URL?
    var modelFileURL: URL? // Pour compatibilité

    private var scnView: SCNView!
    private var currentViewMode: ViewMode = .texture

    private enum ViewMode { case texture, mesh, points }
    private enum PresetView { case orbit, front, top }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1)
        setupSceneView()
        setupTopBar()
        setupBottomToolbar()
        setupViewModeToggle()
    }

    override var prefersStatusBarHidden: Bool { true }

    // MARK: - SceneKit View

    private func setupSceneView() {
        scnView = SCNView(frame: view.bounds)
        scnView.autoresizingMask    = [.flexibleWidth, .flexibleHeight]
        scnView.backgroundColor     = .black
        scnView.allowsCameraControl = true
        scnView.showsStatistics     = false
        scnView.antialiasingMode    = .multisampling4X

        if let scene = modelScene {
            scnView.scene = scene
            setupInitialCamera(scene: scene)
        }

        scnView.scene?.background.contents = UIColor(white: 0.03, alpha: 1)
        view.addSubview(scnView)
    }

    private func setupInitialCamera(scene: SCNScene) {
        let cameraNode = SCNNode()
        cameraNode.name   = "ViewerCamera"
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 60
        cameraNode.position    = SCNVector3(x: 0.18, y: 0.22, z: 0.42)
        cameraNode.eulerAngles = SCNVector3(x: -0.48, y: 0.38, z: 0)
        scene.rootNode.addChildNode(cameraNode)
        scnView.pointOfView = cameraNode
    }

    // MARK: - Top Bar

    private func setupTopBar() {
        let bar = UIView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.backgroundColor = UIColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 0.85)
        view.addSubview(bar)

        let backBtn = UIButton(type: .system)
        backBtn.translatesAutoresizingMaskIntoConstraints = false
        backBtn.setTitle("← Retour", for: .normal)
        backBtn.setTitleColor(.white, for: .normal)
        backBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        backBtn.addTarget(self, action: #selector(onClose), for: .touchUpInside)
        bar.addSubview(backBtn)

        let titleLbl = UILabel()
        titleLbl.translatesAutoresizingMaskIntoConstraints = false
        titleLbl.text = "Gabarit 3D (GLB Texturé)"
        titleLbl.textColor = .white
        titleLbl.font = .systemFont(ofSize: 16, weight: .bold)
        bar.addSubview(titleLbl)

        let exportBtn = UIButton(type: .system)
        exportBtn.translatesAutoresizingMaskIntoConstraints = false
        exportBtn.setTitle("Exporter GLB 📤", for: .normal)
        exportBtn.setTitleColor(UIColor(red: 0.0, green: 0.898, blue: 0.816, alpha: 1), for: .normal)
        exportBtn.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
        exportBtn.addTarget(self, action: #selector(onShare), for: .touchUpInside)
        bar.addSubview(exportBtn)

        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: 48),

            backBtn.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 16),
            backBtn.centerYAnchor.constraint(equalTo: bar.centerYAnchor),

            titleLbl.centerXAnchor.constraint(equalTo: bar.centerXAnchor),
            titleLbl.centerYAnchor.constraint(equalTo: bar.centerYAnchor),

            exportBtn.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -16),
            exportBtn.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
    }

    // MARK: - Bottom Preset View Toolbar

    private func setupBottomToolbar() {
        let pill = UIView()
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.backgroundColor = UIColor(red: 0.102, green: 0.102, blue: 0.118, alpha: 0.95)
        pill.layer.cornerRadius = 20
        pill.clipsToBounds = true
        view.addSubview(pill)

        let orbitBtn = makeToolbarButton(title: "⟲ Orbite", action: #selector(onOrbit))
        let frontBtn = makeToolbarButton(title: "⊡ Face",   action: #selector(onFront))
        let topBtn   = makeToolbarButton(title: "↑ Dessus", action: #selector(onTop))

        let stack = UIStackView(arrangedSubviews: [orbitBtn, frontBtn, topBtn])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.distribution = .fillEqually
        stack.spacing = 2
        pill.addSubview(stack)

        NSLayoutConstraint.activate([
            pill.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pill.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            pill.heightAnchor.constraint(equalToConstant: 42),
            pill.widthAnchor.constraint(equalToConstant: 270),

            stack.topAnchor.constraint(equalTo: pill.topAnchor, constant: 3),
            stack.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -3),
            stack.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -4),
        ])
    }

    private func makeToolbarButton(title: String, action: Selector) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.setTitleColor(.white, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        btn.addTarget(self, action: action, for: .touchUpInside)
        return btn
    }

    // MARK: - View Mode Toggle ([Texture] [Mesh] [Points])

    private var modeButtons: [UIButton] = []

    private func setupViewModeToggle() {
        let toggle = UIView()
        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.backgroundColor = UIColor(white: 0.15, alpha: 0.8)
        toggle.layer.cornerRadius = 14
        toggle.clipsToBounds = true
        view.addSubview(toggle)

        let texBtn   = makeModeButton(title: "Texture", mode: .texture)
        let meshBtn  = makeModeButton(title: "Mesh",    mode: .mesh)
        let ptsBtn   = makeModeButton(title: "Points",  mode: .points)

        modeButtons = [texBtn, meshBtn, ptsBtn]
        updateModeButtonHighlight(activeMode: .texture)

        let stack = UIStackView(arrangedSubviews: [texBtn, meshBtn, ptsBtn])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.distribution = .fillEqually
        stack.spacing = 2
        toggle.addSubview(stack)

        NSLayoutConstraint.activate([
            toggle.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toggle.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -66),
            toggle.heightAnchor.constraint(equalToConstant: 32),
            toggle.widthAnchor.constraint(equalToConstant: 240),

            stack.topAnchor.constraint(equalTo: toggle.topAnchor, constant: 2),
            stack.bottomAnchor.constraint(equalTo: toggle.bottomAnchor, constant: -2),
            stack.leadingAnchor.constraint(equalTo: toggle.leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: toggle.trailingAnchor, constant: -2),
        ])
    }

    private func makeModeButton(title: String, mode: ViewMode) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 12, weight: .bold)
        btn.layer.cornerRadius = 12
        btn.tag = (mode == .texture ? 0 : (mode == .mesh ? 1 : 2))
        btn.addTarget(self, action: #selector(onModeSelected(_:)), for: .touchUpInside)
        return btn
    }

    @objc private func onModeSelected(_ sender: UIButton) {
        let mode: ViewMode = sender.tag == 0 ? .texture : (sender.tag == 1 ? .mesh : .points)
        currentViewMode = mode
        updateModeButtonHighlight(activeMode: mode)
        if let scene = scnView.scene {
            setRenderingMode(mode, scene: scene)
        }
    }

    private func updateModeButtonHighlight(activeMode: ViewMode) {
        let activeTag = (activeMode == .texture ? 0 : (activeMode == .mesh ? 1 : 2))
        for btn in modeButtons {
            if btn.tag == activeTag {
                btn.backgroundColor = UIColor(red: 0.0, green: 0.898, blue: 0.816, alpha: 1)
                btn.setTitleColor(.black, for: .normal)
            } else {
                btn.backgroundColor = .clear
                btn.setTitleColor(UIColor(white: 0.7, alpha: 1), for: .normal)
            }
        }
    }

    // MARK: - Camera Presets

    @objc private func onOrbit() { applyCameraPreset(.orbit) }
    @objc private func onFront() { applyCameraPreset(.front) }
    @objc private func onTop()   { applyCameraPreset(.top)   }

    private func applyCameraPreset(_ preset: PresetView) {
        guard let camNode = scnView.pointOfView else { return }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.5
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        switch preset {
        case .orbit:
            camNode.position    = SCNVector3(x: 0.18, y: 0.22, z: 0.42)
            camNode.eulerAngles = SCNVector3(x: -0.48, y: 0.38, z: 0)
        case .front:
            camNode.position    = SCNVector3(x: 0, y: 0.08, z: 0.45)
            camNode.eulerAngles = SCNVector3(x: 0, y: 0, z: 0)
        case .top:
            camNode.position    = SCNVector3(x: 0, y: 0.55, z: 0.001)
            camNode.eulerAngles = SCNVector3(x: -.pi / 2.0, y: 0, z: 0)
        }
        SCNTransaction.commit()
    }

    private func setRenderingMode(_ mode: ViewMode, scene: SCNScene) {
        scene.rootNode.enumerateChildNodes { node, _ in
            guard let geo = node.geometry else { return }
            switch mode {
            case .texture:
                // Texture réelle originale
                geo.materials.first?.fillMode = .fill
            case .mesh:
                // Matcap shading
                let mat = SCNGeometry.matcapMaterial()
                geo.materials = [mat]
            case .points:
                // Wireframe / Nuage de points
                let mat = SCNMaterial()
                mat.diffuse.contents = UIColor(red: 0.0, green: 0.898, blue: 0.816, alpha: 1.0)
                mat.fillMode = .lines
                geo.materials = [mat]
            }
        }
    }

    // MARK: - Navigation & Export

    @objc private func onClose() { dismiss(animated: true) }

    @objc private func onShare() {
        // Exporte en priorité le fichier .glb (ou usdz en fallback)
        var itemsToShare: [Any] = []
        if let glb = glbFileURL {
            itemsToShare.append(glb)
        }
        if let usdz = usdzFileURL ?? modelFileURL {
            itemsToShare.append(usdz)
        }

        guard !itemsToShare.isEmpty else { return }

        let activityVC = UIActivityViewController(activityItems: itemsToShare, applicationActivities: nil)
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: 100, width: 0, height: 0)
        }
        present(activityVC, animated: true)
    }
}
