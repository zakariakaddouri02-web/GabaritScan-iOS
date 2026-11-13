import Foundation
import UIKit
import CoreVideo
import CoreImage
import simd
import RealityKit

/// Service de photogrammétrie inspiré de Polycam (Object Mode & Apple Object Capture iOS 17+)
final class PhotogrammetryService {

    static let shared = PhotogrammetryService()

    private let ciContext = CIContext(options: nil)
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    private(set) var currentSessionDir: URL? = nil
    private(set) var imagesDir: URL? = nil
    private var imageCount: Int = 0

    private var poses: [[String: Any]] = []

    // MARK: - Initialisation d'une session de capture

    func startNewSession() {
        let fileManager = FileManager.default
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let timestamp = Int(Date().timeIntervalSince1970)
        let session = docs.appendingPathComponent("Scan_\(timestamp)", isDirectory: true)
        let imgs = session.appendingPathComponent("Images", isDirectory: true)

        try? fileManager.createDirectory(at: imgs, withIntermediateDirectories: true)
        self.currentSessionDir = session
        self.imagesDir = imgs
        self.imageCount = 0
        self.poses = []

        print("📸 Nouvelle session de capture Polycam initialisée : \(session.path)")
    }

    // MARK: - Sauvegarde d'une photo haute résolution + Pose Caméra

    func captureFrame(pixelBuffer: CVPixelBuffer, cameraTransform: simd_float4x4, intrinsics: CameraIntrinsics) {
        guard let imgs = imagesDir else { return }

        imageCount += 1
        let fileName = String(format: "IMG_%04d.jpg", imageCount)
        let fileURL = imgs.appendingPathComponent(fileName)

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let data = ciContext.jpegRepresentation(of: ciImage, colorSpace: colorSpace, options: [:]) else {
            return
        }
        try? data.write(to: fileURL)

        // Enregistrement de la pose dans le repère universel
        let c0 = [cameraTransform.columns.0.x, cameraTransform.columns.0.y, cameraTransform.columns.0.z, cameraTransform.columns.0.w]
        let c1 = [cameraTransform.columns.1.x, cameraTransform.columns.1.y, cameraTransform.columns.1.z, cameraTransform.columns.1.w]
        let c2 = [cameraTransform.columns.2.x, cameraTransform.columns.2.y, cameraTransform.columns.2.z, cameraTransform.columns.2.w]
        let c3 = [cameraTransform.columns.3.x, cameraTransform.columns.3.y, cameraTransform.columns.3.z, cameraTransform.columns.3.w]

        let poseEntry: [String: Any] = [
            "file_path": fileName,
            "transform_matrix": [c0, c1, c2, c3],
            "fl_x": intrinsics.fx,
            "fl_y": intrinsics.fy,
            "cx": intrinsics.cx,
            "cy": intrinsics.cy
        ]
        poses.append(poseEntry)
    }

    // MARK: - Sauvegarde des métadonnées transforms.json (standard Polycam/NeRF)

    func finalizeCaptures() {
        guard let session = currentSessionDir else { return }
        let jsonURL = session.appendingPathComponent("transforms.json")

        let meta: [String: Any] = [
            "capture_count": imageCount,
            "camera_model": "iPhone",
            "frames": poses
        ]
        if let data = try? JSONSerialization.data(withJSONObject: meta, options: .prettyPrinted) {
            try? data.write(to: jsonURL)
        }
    }

    // MARK: - Reconstruction 3D (Apple PhotogrammetrySession iOS 17+ ou Fallback)

    func reconstruct3DModel(outputURL: URL, progress: @escaping (Float) -> Void) async -> URL? {
        finalizeCaptures()
        guard let imgs = imagesDir, imageCount >= 10 else {
            print("⚠️ Pas assez d'images pour la photogrammétrie (minimum 10)")
            return nil
        }

        #if canImport(RealityKit)
        if #available(iOS 17.0, *) {
            if PhotogrammetrySession.isSupported {
                print("🚀 Démarrage de la reconstruction PhotogrammetrySession (Apple Object Capture iOS 17)...")
                do {
                    var config = PhotogrammetrySession.Configuration()
                    // Masquage automatique du décor (style Object Masking de Polycam !)
                    config.isObjectMaskingEnabled = true

                    let session = try PhotogrammetrySession(input: imgs, configuration: config)
                    let request = PhotogrammetrySession.Request.modelFile(url: outputURL, detail: .reduced)
                    try session.process(requests: [request])

                    for try await output in session.outputs {
                        switch output {
                        case .processingComplete:
                            print("🎉 Reconstruction 3D Polycam réussie !")
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
