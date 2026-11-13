import UIKit
import SceneKit
import QuickLook

/// Écran de visualisation 3D interactive du gabarit scanné
final class ModelViewerViewController: UIViewController {

    var modelScene: SCNScene?
    var modelFileURL: URL?

    private var scnView: SCNView!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.1, alpha: 1.0)
        setupSCNView()
        setupNavigationBar()
        setupInfoOverlay()
    }

    private func setupSCNView() {
        scnView = SCNView(frame: view.bounds)
        scnView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scnView.backgroundColor = UIColor(red: 0.12, green: 0.12, blue: 0.15, alpha: 1.0)

        // Permet à l'utilisateur de tourner, zoomer et déplacer le modèle à 360° avec ses doigts !
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true
        scnView.showsStatistics = false

        if let scene = modelScene {
            scnView.scene = scene

            // Caméra initiale avec recul adapté
            let cameraNode = SCNNode()
            cameraNode.camera = SCNCamera()
            cameraNode.position = SCNVector3(x: 0, y: 0.25, z: 0.45)
            cameraNode.eulerAngles = SCNVector3(x: -0.4, y: 0, z: 0)
            scene.rootNode.addChildNode(cameraNode)
        }

        view.addSubview(scnView)
    }

    private func setupNavigationBar() {
        // Barre supérieure
        let headerView = UIView()
        headerView.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)

        let titleLabel = UILabel()
        titleLabel.text = "Modèle 3D du Gabarit"
        titleLabel.textColor = .white
        titleLabel.font = .boldSystemFont(ofSize: 17)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(titleLabel)

        let closeBtn = UIButton(type: .system)
        closeBtn.setTitle("Fermer", for: .normal)
        closeBtn.setTitleColor(.white, for: .normal)
        closeBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        closeBtn.addTarget(self, action: #selector(onClose), for: .touchUpInside)
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(closeBtn)

        let shareBtn = UIButton(type: .system)
        shareBtn.setTitle("Exporter / Partager", for: .normal)
        shareBtn.setTitleColor(UIColor(red: 0.2, green: 0.8, blue: 0.4, alpha: 1.0), for: .normal)
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

    private func setupInfoOverlay() {
        let infoCard = UIView()
        infoCard.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        infoCard.layer.cornerRadius = 10
        infoCard.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(infoCard)

        let infoText = UILabel()
        infoText.text = "🎯 Origine (0,0,0) : Centre AprilTag\n📐 Échelle : 1:1 millimétrique\n👆 Touchez et glissez pour tourner à 360°"
        infoText.textColor = .white
        infoText.numberOfLines = 3
        infoText.font = .systemFont(ofSize: 13, weight: .medium)
        infoText.textAlignment = .center
        infoText.translatesAutoresizingMaskIntoConstraints = false
        infoCard.addSubview(infoText)

        NSLayoutConstraint.activate([
            infoCard.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            infoCard.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            infoCard.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            infoCard.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),

            infoText.topAnchor.constraint(equalTo: infoCard.topAnchor, constant: 10),
            infoText.bottomAnchor.constraint(equalTo: infoCard.bottomAnchor, constant: -10),
            infoText.leadingAnchor.constraint(equalTo: infoCard.leadingAnchor, constant: 16),
            infoText.trailingAnchor.constraint(equalTo: infoCard.trailingAnchor, constant: -16)
        ])
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
