import Foundation
import UIKit
import CoreVideo
import CoreImage
import simd
import RealityKit

/// Service de capture et d'export du dataset complet (Photos HD + Poses dans le repère AprilTag + transforms.json)
/// Prêt pour traitement direct sur PC (Photogrammétrie, COLMAP, NeRF, Blender, Python)
final class PhotogrammetryService {

    static let shared = PhotogrammetryService()

    private let ciContext = CIContext(options: nil)
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    private(set) var currentSessionDir: URL? = nil
    private(set) var imagesDir: URL? = nil
    private var imageCount: Int = 0

    private var poses: [[String: Any]] = []
    private var lastIntrinsics: CameraIntrinsics? = nil

    // MARK: - Initialisation d'une session de capture

    func startNewSession() {
        let fileManager = FileManager.default
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let timestamp = Int(Date().timeIntervalSince1970)
        let session = docs.appendingPathComponent("GabaritScan_\(timestamp)", isDirectory: true)
        let imgs = session.appendingPathComponent("images", isDirectory: true)

        try? fileManager.createDirectory(at: imgs, withIntermediateDirectories: true)
        self.currentSessionDir = session
        self.imagesDir = imgs
        self.imageCount = 0
        self.poses = []

        print("📸 Nouvelle session de capture initialisée : \(session.path)")
    }

    // MARK: - Sauvegarde d'une photo haute résolution + Pose relative au Tag

    func captureFrame(
        pixelBuffer: CVPixelBuffer,
        cameraTransform: simd_float4x4,
        intrinsics: CameraIntrinsics,
        lockedTagTransform: simd_float4x4?
    ) {
        guard let imgs = imagesDir else { return }

        imageCount += 1
        lastIntrinsics = intrinsics
        let fileName = String(format: "IMG_%04d.jpg", imageCount)
        let fileURL = imgs.appendingPathComponent(fileName)

        // Sauvegarde de l'image JPEG haute définition
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let data = ciContext.jpegRepresentation(of: ciImage, colorSpace: colorSpace, options: [:]) else {
            return
        }
        try? data.write(to: fileURL)

        // Matrice de la caméra dans le repère de l'AprilTag (0,0,0 = Centre du Tag)
        let camPoseInTag: simd_float4x4
        if let tagWorld = lockedTagTransform {
            let worldToTag = tagWorld.inverse
            camPoseInTag = matrix_multiply(worldToTag, cameraTransform)
        } else {
            camPoseInTag = cameraTransform
        }

        // Matrice 4x4 au format standard NeRF / Polycam (colonnes)
        let c0 = [camPoseInTag.columns.0.x, camPoseInTag.columns.0.y, camPoseInTag.columns.0.z, camPoseInTag.columns.0.w]
        let c1 = [camPoseInTag.columns.1.x, camPoseInTag.columns.1.y, camPoseInTag.columns.1.z, camPoseInTag.columns.1.w]
        let c2 = [camPoseInTag.columns.2.x, camPoseInTag.columns.2.y, camPoseInTag.columns.2.z, camPoseInTag.columns.2.w]
        let c3 = [camPoseInTag.columns.3.x, camPoseInTag.columns.3.y, camPoseInTag.columns.3.z, camPoseInTag.columns.3.w]

        let poseEntry: [String: Any] = [
            "file_path": "images/\(fileName)",
            "transform_matrix": [c0, c1, c2, c3],
            "timestamp": ProcessInfo.processInfo.systemUptime
        ]
        poses.append(poseEntry)
    }

    // MARK: - Sauvegarde des métadonnées transforms.json (standard NeRF / Polycam / COLMAP)

    func finalizeCaptures() {
        guard let session = currentSessionDir else { return }
        let jsonURL = session.appendingPathComponent("transforms.json")

        let fx = lastIntrinsics?.fx ?? 2870.0
        let fy = lastIntrinsics?.fy ?? 2870.0
        let cx = lastIntrinsics?.cx ?? 960.0
        let cy = lastIntrinsics?.cy ?? 720.0

        let meta: [String: Any] = [
            "camera_model": "PINHOLE",
            "fl_x": fx,
            "fl_y": fy,
            "cx": cx,
            "cy": cy,
            "w": 1920,
            "h": 1440,
            "tag_info": [
                "family": "tag36h11",
                "size_mm": GabaritConfig.tagSizeMm,
                "origin": [0.0, 0.0, 0.0],
                "unit": "meters"
            ],
            "frames": poses
        ]

        if let data = try? JSONSerialization.data(withJSONObject: meta, options: .prettyPrinted) {
            try? data.write(to: jsonURL)
            print("📝 transforms.json généré avec succès (\(imageCount) photos) !")
        }
    }

    // MARK: - Création de l'archive ZIP complète pour le PC

    func exportDatasetZip() -> URL? {
        finalizeCaptures()
        guard let session = currentSessionDir else { return nil }

        let coordinator = NSFileCoordinator()
        var zipURL: URL?

        coordinator.coordinate(readingItemAt: session, options: .forUploading, error: nil) { zippedURL in
            let timestamp = Int(Date().timeIntervalSince1970)
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent("GabaritScan_Dataset_\(timestamp).zip")
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: zippedURL, to: dest)
            zipURL = dest
        }

        print("📦 Archive ZIP créée pour le PC : \(zipURL?.path ?? "erreur")")
        return zipURL
    }

    // MARK: - Reconstruction 3D locale sur l'iPhone (Apple Object Capture iOS 17+)

    func reconstruct3DModel(outputURL: URL, progress: @escaping (Float) -> Void) async -> URL? {
        finalizeCaptures()
        guard let imgs = imagesDir, imageCount >= 10 else {
            return nil
        }

        #if canImport(RealityKit)
        if #available(iOS 17.0, *) {
            if PhotogrammetrySession.isSupported {
                do {
                    var config = PhotogrammetrySession.Configuration()
                    config.isObjectMaskingEnabled = true

                    let session = try PhotogrammetrySession(input: imgs, configuration: config)
                    let request = PhotogrammetrySession.Request.modelFile(url: outputURL, detail: .reduced)
                    try session.process(requests: [request])

                    for try await output in session.outputs {
                        switch output {
                        case .processingComplete:
                            return outputURL
                        case .requestProgress(_, let frac):
                            progress(Float(frac))
                        case .requestError(_, let err):
                            print("⚠️ Erreur PhotogrammetrySession: \(err)")
                            return nil
                        default:
                            break
                        }
                    }
                    return outputURL
                } catch {
                    print("⚠️ Échec PhotogrammetrySession: \(error)")
                }
            }
        }
        #endif

        return nil
    }
}
