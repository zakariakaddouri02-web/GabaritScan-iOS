import UIKit
import SceneKit
import QuickLook

/// Écran de visualisation 3D interactive du gabarit (Mode 3D Field & Alignement style PractiCal Images 2 & 3)
final class ModelViewerViewController: UIViewController {

    var modelScene: SCNScene?
    var modelFileURL: URL?

    private var scnView: SCNView!
    private var crosshairsOverlay: UIView!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.1, green: 0.1, blue: 0.14, alpha: 1.0)
        setupSCNView()
        setupCrosshairsOverlay()
        setupNavigationBar()
        setupViewPresetControls()
    }

    private func setupSCNView() {
        scnView = SCNView(frame: view.bounds)
        scnView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scnView.backgroundColor = UIColor(red: 0.10, green: 0.10, blue: 0.14, alpha: 1.0)

        // Permet la rotation à 360°, le zoom et le pan avec les doigts
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true
        scnView.showsStatistics = false

        if let scene = modelScene {
            scnView.scene = scene

            // Caméra perspective 3D initiale (comme Image 2)
            let cameraNode = SCNNode()
            cameraNode.camera = SCNCamera()
            cameraNode.name = "ViewerCamera"
            cameraNode.position = SCNVector3(x: 0.15, y: 0.25, z: 0.50)
            cameraNode.eulerAngles = SCNVector3(x: -0.35, y: 0.25, z: 0)
            scene.rootNode.addChildNode(cameraNode)
        }

        view.addSubview(scnView)
    }

    private func setupCrosshairsOverlay() {
        // Réticule en croix plein écran (style Image 3)
        crosshairsOverlay = UIView(frame: view.bounds)
        crosshairsOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        crosshairsOverlay.backgroundColor = .clear
        crosshairsOverlay.isUserInteractionEnabled = false

        let hLine = UIView(frame: CGRect(x: 0, y: view.bounds.midY, width: view.bounds.width, height: 1.5))
        hLine.backgroundColor = UIColor.systemRed.withAlphaComponent(0.85)
        hLine.autoresizingMask = [.flexibleWidth, .flexibleTopMargin, .flexibleBottomMargin]
        crosshairsOverlay.addSubview(hLine)

        let vLine = UIView(frame: CGRect(x: view.bounds.midX, y: 0, width: 1.5, height: view.bounds.height))
        vLine.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.85)
        vLine.autoresizingMask = [.flexibleHeight, .flexibleLeftMargin, .flexibleRightMargin]
        crosshairsOverlay.addSubview(vLine)

        crosshairsOverlay.isHidden = true // Masqué par défaut en mode Orbit
        view.addSubview(crosshairsOverlay)
    }

    private func setupNavigationBar() {
        let headerView = UIView()
        headerView.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)

        let titleLabel = UILabel()
        titleLabel.text = "PractiCal 3D Field"
        titleLabel.textColor = .white
        titleLabel.font = .boldSystemFont(ofSize: 17)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(titleLabel)

        let closeBtn = UIButton(type: .system)
        closeBtn.setTitle("◀ Retour", for: .normal)
        closeBtn.setTitleColor(.white, for: .normal)
        closeBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        closeBtn.addTarget(self, action: #selector(onClose), for: .touchUpInside)
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(closeBtn)

        let shareBtn = UIButton(type: .system)
        shareBtn.setTitle("Exporter 📤", for: .normal)
        shareBtn.setTitleColor(UIColor(red: 0.2, green: 0.9, blue: 0.45, alpha: 1.0), for: .normal)
        shareBtn.titleLabel?.font = .boldSystemFont(ofSize: 16)
        shareBtn.addTarget(self, action: #selector(onShare), for: .touchUpInside)
        shareBtn.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(shareBtn)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 50),

            closeBtn.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
            closeBtn.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            titleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            shareBtn.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16),
            shareBtn.centerYAnchor.constraint(equalTo: headerView.centerYAnchor)
        ])
    }

    private func setupViewPresetControls() {
        // Barre de contrôle des vues : [ 3D Orbit ] [ Face / Align ] [ Top ]
        let toolbar = UIView()
        toolbar.backgroundColor = UIColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 0.9)
        toolbar.layer.cornerRadius = 16
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toolbar)

        let orbitBtn = createPresetButton(title: "3D Orbit", action: #selector(setOrbitView))
        let alignBtn = createPresetButton(title: "Face ┼", action: #selector(setFrontView))
        let topBtn   = createPresetButton(title: "Dessus", action: #selector(setTopView))

        let stack = UIStackView(arrangedSubviews: [orbitBtn, alignBtn, topBtn])
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(stack)

        NSLayoutConstraint.activate([
            toolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            toolbar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toolbar.widthAnchor.constraint(equalToConstant: 290),
            toolbar.heightAnchor.constraint(equalToConstant: 44),

            stack.topAnchor.constraint(equalTo: toolbar.topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -8),
            stack.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: -4)
        ])
    }

    private func createPresetButton(title: String, action: Selector) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(title, for: .normal)
        btn.setTitleColor(.white, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .bold)
        btn.backgroundColor = UIColor(white: 0.22, alpha: 0.8)
        btn.layer.cornerRadius = 10
        btn.addTarget(self, action: action, for: .touchUpInside)
        return btn
    }

    @objc private func setOrbitView() {
        // Vue 3D Perspective (Image 2)
        crosshairsOverlay.isHidden = true
        scnView.pointOfView?.position = SCNVector3(x: 0.2, y: 0.25, z: 0.5)
        scnView.pointOfView?.eulerAngles = SCNVector3(x: -0.35, y: 0.35, z: 0)
    }

    @objc private func setFrontView() {
        // Vue Frontale Face + Réticule en croix (Image 3)
        crosshairsOverlay.isHidden = false
        scnView.pointOfView?.position = SCNVector3(x: 0, y: 0.08, z: 0.45)
        scnView.pointOfView?.eulerAngles = SCNVector3(x: 0, y: 0, z: 0)
    }

    @objc private func setTopView() {
        crosshairsOverlay.isHidden = true
        scnView.pointOfView?.position = SCNVector3(x: 0, y: 0.6, z: 0.001)
        scnView.pointOfView?.eulerAngles = SCNVector3(x: -.pi / 2.0, y: 0, z: 0)
    }

    @objc private func onClose() {
        dismiss(animated: true)
    }

    @objc private func onShare() {
        guard let url = modelFileURL else { return }
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        }
        present(activityVC, animated: true)
    }
}
