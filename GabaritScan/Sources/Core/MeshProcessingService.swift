import Foundation
import ARKit
import SceneKit
import ModelIO

/// Service de traitement et génération du modèle 3D aligné sur l'AprilTag
final class MeshProcessingService {

    /// Reconstruit le modèle 3D du gabarit à partir des données LiDAR et du tag
    /// - Parameters:
    ///   - frame: La dernière frame ARKit
    ///   - tagDetection: Détection de l'AprilTag pour centrer l'origine
    ///   - cropRadiusMm: Rayon autour du tag à conserver (en mm)
    /// - Returns: URL du fichier 3D généré (.usdz) et la scène SCNScene pour affichage direct
    static func processAndExportMesh(
        from frame: ARFrame,
        tagDetection: TagDetection?,
        cropRadiusMm: Float = GabaritConfig.objectMaxDimMm
    ) -> (fileURL: URL, scene: SCNScene)? {

        let meshAnchors = frame.anchors.compactMap { $0 as? ARMeshAnchor }
        guard !meshAnchors.isEmpty else {
            print("⚠️ Aucun maillage LiDAR disponible")
            return nil
        }

        // Matrice inverse du tag (pour ramener le repère (0,0,0) au centre du tag)
        let worldToTagTransform: simd_float4x4
        if let tag = tagDetection {
            let cameraToWorld = frame.camera.transform
            let R = rodriguesMatrix(tag.rvec)
            let t = tag.tvec / 1000.0 // mm vers mètres pour ARKit
            let tagToCamera = simd_float4x4(
                SIMD4(R[0], R[3], R[6], 0),
                SIMD4(R[1], R[4], R[7], 0),
                SIMD4(R[2], R[5], R[8], 0),
                SIMD4(t.x, t.y, t.z, 1)
            )
            let tagToWorld = matrix_multiply(cameraToWorld, tagToCamera)
            worldToTagTransform = tagToWorld.inverse
        } else {
            worldToTagTransform = matrix_identity_float4x4
        }

        let radiusMeters = cropRadiusMm / 1000.0
        let rootNode = SCNNode()

        // 2. Fusionner et recadrer les morceaux de maillage autour du tag
        for meshAnchor in meshAnchors {
            let geometry = SCNGeometry.from(arMeshGeometry: meshAnchor.geometry)

            let material = SCNMaterial()
            material.diffuse.contents = UIColor(red: 0.85, green: 0.85, blue: 0.88, alpha: 1.0)
            material.roughness.contents = 0.4
            material.metalness.contents = 0.2
            material.isDoubleSided = true
            geometry.materials = [material]

            let node = SCNNode(geometry: geometry)
            node.simdTransform = matrix_multiply(worldToTagTransform, meshAnchor.transform)

            let distanceToOrigin = simd_length(node.simdPosition)
            if distanceToOrigin < radiusMeters * 1.5 {
                rootNode.addChildNode(node)
            }
        }

        // 3. Créer la scène 3D
        let scene = SCNScene()
        scene.rootNode.addChildNode(rootNode)

        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.color = UIColor(white: 0.5, alpha: 1.0)
        scene.rootNode.addChildNode(ambientLight)

        let dirLight = SCNNode()
        dirLight.light = SCNLight()
        dirLight.light?.type = .directional
        dirLight.light?.color = UIColor(white: 0.8, alpha: 1.0)
        dirLight.position = SCNVector3(x: 1, y: 3, z: 2)
        scene.rootNode.addChildNode(dirLight)

        // Axes de coordonnées au centre de l'AprilTag (X=Rouge, Y=Vert, Z=Bleu)
        let axesNode = createAxesNode(size: 0.04)
        scene.rootNode.addChildNode(axesNode)

        // 4. Exporter le fichier 3D
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("gabarit_3d.usdz")

        scene.write(to: fileURL, options: nil, delegate: nil, progressHandler: nil)
        print("✅ Modèle 3D exporté avec succès à : \(fileURL.path)")

        return (fileURL, scene)
    }

    private static func createAxesNode(size: Float) -> SCNNode {
        let node = SCNNode()

        func makeAxis(color: UIColor, end: SCNVector3) -> SCNNode {
            let line = SCNNode()
            let geom = SCNGeometry.line(from: SCNVector3Zero, to: end, color: color)
            line.geometry = geom
            return line
        }

        node.addChildNode(makeAxis(color: .red, end: SCNVector3(size, 0, 0)))
        node.addChildNode(makeAxis(color: .green, end: SCNVector3(0, size, 0)))
        node.addChildNode(makeAxis(color: .blue, end: SCNVector3(0, 0, size)))
        return node
    }

    private static func rodriguesMatrix(_ r: SIMD3<Float>) -> [Float] {
        let angle = sqrt(r.x*r.x + r.y*r.y + r.z*r.z)
        guard angle > 1e-6 else { return [1,0,0, 0,1,0, 0,0,1] }
        let ax = r.x/angle, ay = r.y/angle, az = r.z/angle
        let c = cos(angle), s = sin(angle), t = 1-c
        return [
            t*ax*ax+c,    t*ax*ay-s*az, t*ax*az+s*ay,
            t*ax*ay+s*az, t*ay*ay+c,    t*ay*az-s*ax,
            t*ax*az-s*ay, t*ay*az+s*ax, t*az*az+c
        ]
    }
}
