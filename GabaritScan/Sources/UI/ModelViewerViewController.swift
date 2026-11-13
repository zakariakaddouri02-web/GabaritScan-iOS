import UIKit
import SceneKit
import QuickLook

// MARK: - Polycam-style 3D model viewer

final class ModelViewerViewController: UIViewController {

    var modelScene: SCNScene?
    var modelFileURL: URL?

    private var scnView: SCNView!
    private var currentViewMode: ViewMode = .mesh

    private enum ViewMode { case mesh, points, axes }
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

        // Soft ambient environment
        scnView.scene?.background.contents = UIColor(white: 0.03, alpha: 1)
        view.addSubview(scnView)
    }

    private func setupInitialCamera(scene: SCNScene) {
        let cameraNode = SCNNode()
        cameraNode.name   = "ViewerCamera"
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 60
        // Isometric-ish view from above-front (Polycam default)
        cameraNode.position    = SCNVector3(x: 0.20, y: 0.28, z: 0.45)
        cameraNode.eulerAngles = SCNVector3(x: -0.55, y: 0.4, z: 0)
        scene.rootNode.addChildNode(cameraNode)
        scnView.pointOfView = cameraNode
    }

    // MARK: - Top Bar

    private func setupTopBar() {
        let headerView = UIView()
        headerView.backgroundColor = UIColor(red: 0.102, green: 0.102, blue: 0.118, alpha: 0.95)
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)

        let titleLabel = UILabel()
        titleLabel.text          = "GabaritScan 3D"
        titleLabel.textColor     = .white
        titleLabel.font          = UIFont.systemFont(ofSize: 17, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(titleLabel)

        let closeBtn = UIButton(type: .system)
        closeBtn.setTitle("← Retour", for: .normal)
        closeBtn.setTitleColor(.white, for: .normal)
        closeBtn.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        closeBtn.addTarget(self, action: #selector(onClose), for: .touchUpInside)
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(closeBtn)

        let exportBtn = UIButton(type: .system)
        exportBtn.setTitle("Exporter ↑", for: .normal)
        exportBtn.setTitleColor(UIColor(red: 0.0, green: 0.898, blue: 0.816, alpha: 1.0), for: .normal)
        exportBtn.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        exportBtn.addTarget(self, action: #selector(onShare), for: .touchUpInside)
        exportBtn.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(exportBtn)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 50),

            closeBtn.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
            closeBtn.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            titleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            exportBtn.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16),
            exportBtn.centerYAnchor.constraint(equalTo: headerView.centerYAnchor)
        ])
    }

    // MARK: - Bottom Toolbar (orbit presets)

    private func setupBottomToolbar() {
        let toolbar = UIView()
        toolbar.backgroundColor   = UIColor(red: 0.102, green: 0.102, blue: 0.118, alpha: 0.95)
        toolbar.layer.cornerRadius = 20
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toolbar)

        let orbitBtn = makePresetButton(title: "⟲ Orbite", tag: 0)
        let frontBtn = makePresetButton(title: "⊡ Face",   tag: 1)
        let topBtn   = makePresetButton(title: "↑ Dessus", tag: 2)

        let stack = UIStackView(arrangedSubviews: [orbitBtn, frontBtn, topBtn])
        stack.axis         = .horizontal
        stack.distribution = .fillEqually
        stack.spacing      = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(stack)

        NSLayoutConstraint.activate([
            toolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -56),
            toolbar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toolbar.widthAnchor.constraint(equalToConstant: 300),
            toolbar.heightAnchor.constraint(equalToConstant: 44),

            stack.topAnchor.constraint(equalTo: toolbar.topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -8),
            stack.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: -4)
        ])
    }

    // MARK: - View Mode Toggle (Mesh / Points / Axes)

    private func setupViewModeToggle() {
        let toggleBar = UIView()
        toggleBar.backgroundColor   = UIColor(red: 0.102, green: 0.102, blue: 0.118, alpha: 0.95)
        toggleBar.layer.cornerRadius = 16
        toggleBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toggleBar)

        let meshBtn   = makeModeButton(title: "Mesh",   tag: 10)
        let pointsBtn = makeModeButton(title: "Points", tag: 11)
        let axesBtn   = makeModeButton(title: "Axes",   tag: 12)

        let stack = UIStackView(arrangedSubviews: [meshBtn, pointsBtn, axesBtn])
        stack.axis         = .horizontal
        stack.distribution = .fillEqually
        stack.spacing      = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        toggleBar.addSubview(stack)

        NSLayoutConstraint.activate([
            toggleBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            toggleBar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toggleBar.widthAnchor.constraint(equalToConstant: 240),
            toggleBar.heightAnchor.constraint(equalToConstant: 36),

            stack.topAnchor.constraint(equalTo: toggleBar.topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: toggleBar.leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: toggleBar.trailingAnchor, constant: -6),
            stack.bottomAnchor.constraint(equalTo: toggleBar.bottomAnchor, constant: -4)
        ])
    }

    // MARK: - Button factories

    private func makePresetButton(title: String, tag: Int) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.setTitleColor(.white, for: .normal)
        btn.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        btn.backgroundColor  = UIColor(white: 0.2, alpha: 0.8)
        btn.layer.cornerRadius = 10
        btn.tag = tag
        btn.addTarget(self, action: #selector(onPresetTapped(_:)), for: .touchUpInside)
        return btn
    }

    private func makeModeButton(title: String, tag: Int) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.setTitleColor(UIColor(white: 0.75, alpha: 1), for: .normal)
        btn.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        btn.backgroundColor  = UIColor(white: 0.15, alpha: 0.8)
        btn.layer.cornerRadius = 8
        btn.tag = tag
        btn.addTarget(self, action: #selector(onModeTapped(_:)), for: .touchUpInside)
        return btn
    }

    // MARK: - Preset view actions

    @objc private func onPresetTapped(_ sender: UIButton) {
        guard let cam = scnView.pointOfView else { return }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.5
        switch sender.tag {
        case 0: // Orbite
            cam.position    = SCNVector3(x: 0.20, y: 0.28, z: 0.45)
            cam.eulerAngles = SCNVector3(x: -0.55, y: 0.4, z: 0)
        case 1: // Face
            cam.position    = SCNVector3(x: 0, y: 0.08, z: 0.5)
            cam.eulerAngles = SCNVector3(x: 0, y: 0, z: 0)
        case 2: // Dessus
            cam.position    = SCNVector3(x: 0, y: 0.6, z: 0.001)
            cam.eulerAngles = SCNVector3(x: -.pi / 2, y: 0, z: 0)
        default: break
        }
        SCNTransaction.commit()
    }

    // MARK: - View mode actions

    @objc private func onModeTapped(_ sender: UIButton) {
        guard let scene = scnView.scene else { return }

        switch sender.tag {
        case 10: // Mesh — apply matcap material to all mesh nodes
            setRenderingMode(.mesh, scene: scene)
            currentViewMode = .mesh
        case 11: // Points
            setRenderingMode(.points, scene: scene)
            currentViewMode = .points
        case 12: // Axes only
            setRenderingMode(.axes, scene: scene)
            currentViewMode = .axes
        default: break
        }
    }

    private func setRenderingMode(_ mode: ViewMode, scene: SCNScene) {
        scene.rootNode.enumerateChildNodes { node, _ in
            guard let geo = node.geometry else { return }
            switch mode {
            case .mesh:
                // Reapply matcap material
                let mat = SCNGeometry.matcapMaterial()
                geo.materials = [mat]
            case .points:
                // Wireframe-like: use fillMode lines if available, else just tint
                let mat = SCNMaterial()
                mat.diffuse.contents = UIColor(red: 0.0, green: 0.898, blue: 0.816, alpha: 1.0)
                mat.fillMode = .lines
                geo.materials = [mat]
            case .axes:
                // Semi-transparent grey
                let mat = SCNMaterial()
                mat.diffuse.contents = UIColor(white: 0.5, alpha: 0.3)
                mat.isDoubleSided = true
                geo.materials = [mat]
            }
        }
    }

    // MARK: - Navigation

    @objc private func onClose() { dismiss(animated: true) }

    @objc private func onShare() {
        guard let url = modelFileURL else { return }
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: 100, width: 0, height: 0)
        }
        present(activityVC, animated: true)
    }
}
