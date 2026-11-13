import Foundation
import ARKit
import SceneKit
import ModelIO

/// Service de traitement et génération de la scène 3D complète style PractiCal (Grille CAD + Axes + Rectangles)
final class MeshProcessingService {

    /// Reconstruit la scène 3D complète avec Grille CAD, Rectangles calibrés et Modèle du gabarit
    static func processAndExportMesh(
        from frame: ARFrame,
        lockedTagTransform: simd_float4x4?,
        tagDetection: TagDetection? = nil,
        featurePoints: [SIMD3<Float>] = [],
        cropRadiusMm: Float = GabaritConfig.objectMaxDimMm
    ) -> (fileURL: URL, scene: SCNScene)? {

        let worldToTagTransform: simd_float4x4
        if let locked = lockedTagTransform {
            worldToTagTransform = locked.inverse
        } else if let tag = tagDetection {
            let cameraToWorld = frame.camera.transform
            let R = rodriguesMatrix(tag.rvec)
            let t = tag.tvec / 1000.0
            let tagToCamera = simd_float4x4(
                SIMD4( R[0], -R[3], -R[6], 0),
                SIMD4(-R[1],  R[4],  R[7], 0),
                SIMD4(-R[2],  R[5],  R[8], 0),
                SIMD4(  t.x,  -t.y,  -t.z, 1)
            )
            let tagToWorld = matrix_multiply(cameraToWorld, tagToCamera)
            worldToTagTransform = tagToWorld.inverse
        } else {
            worldToTagTransform = matrix_identity_float4x4
        }

        let radiusMeters = cropRadiusMm / 1000.0
        let rootNode = SCNNode()

        // ── 1. GRILLE 3D CAD (Style PractiCal Image 2) ──
        let floorGrid = CADSceneBuilder.createGrid(sizeMeters: 1.0, stepMeters: 0.05, isVertical: false)
        rootNode.addChildNode(floorGrid)

        let wallGrid = CADSceneBuilder.createGrid(sizeMeters: 1.0, stepMeters: 0.05, isVertical: true)
        rootNode.addChildNode(wallGrid)

        // ── 2. AXES 3D AU CENTRE DU TAG (0,0,0) ──
        let axes = CADSceneBuilder.createAxes(length: 0.10)
        rootNode.addChildNode(axes)

        // ── 3. RECTANGLES CALIBRÉS VIRTUELS (Style "Rectangle 1" Cyan & Magenta Images 2 & 3) ──
        let rect1 = CADSceneBuilder.createCalibratedRectangle(
            width: 0.20,
            height: 0.14,
            color: UIColor(red: 0.1, green: 0.85, blue: 0.95, alpha: 1.0), // Cyan
            label: "Rectangle 1 (200x140 mm)",
            position: SCNVector3(0, 0.12, 0)
        )
        rootNode.addChildNode(rect1)

        let rect2 = CADSceneBuilder.createCalibratedRectangle(
            width: 0.12,
            height: 0.12,
            color: UIColor(red: 1.0, green: 0.2, blue: 0.7, alpha: 1.0), // Magenta
            label: "Gabarit Ref",
            position: SCNVector3(-0.14, 0.15, 0)
        )
        rootNode.addChildNode(rect2)

        // ── 4. PLAN VIRTUEL DE L'APRILTAG (80mm x 80mm) ──
        let tagPlane = SCNPlane(width: CGFloat(GabaritConfig.tagSizeMm / 1000.0),
                                height: CGFloat(GabaritConfig.tagSizeMm / 1000.0))
        tagPlane.cornerRadius = 0.003
        let tagMat = SCNMaterial()
        tagMat.diffuse.contents = UIColor.white
        tagMat.isDoubleSided = true
        tagPlane.materials = [tagMat]
        let tagNode = SCNNode(geometry: tagPlane)
        rootNode.addChildNode(tagNode)

        // ── 5. MODÈLE 3D DU GABARIT (LiDAR ou Nuage de Points Optiques) ──
        let meshAnchors = frame.anchors.compactMap { $0 as? ARMeshAnchor }

        if !meshAnchors.isEmpty {
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

                let dist = simd_length(node.simdPosition)
                if dist < radiusMeters * 1.5 {
                    rootNode.addChildNode(node)
                }
            }
        } else {
            // Nuage de points ARKit
            var pointsInTagFrame: [SIMD3<Float>] = []
            for pt in featurePoints {
                let pWorld = SIMD4<Float>(pt.x, pt.y, pt.z, 1.0)
                let pTag = matrix_multiply(worldToTagTransform, pWorld)
                let dist = sqrt(pTag.x*pTag.x + pTag.y*pTag.y + pTag.z*pTag.z)
                if dist < radiusMeters * 1.5 {
                    pointsInTagFrame.append(SIMD3<Float>(pTag.x, pTag.y, pTag.z))
                }
            }

            if !pointsInTagFrame.isEmpty {
                let cloudGeometry = SCNGeometry.pointCloud(from: pointsInTagFrame, size: 0.004)
                let cloudNode = SCNNode(geometry: cloudGeometry)
                rootNode.addChildNode(cloudNode)
            }
        }

        // ── 6. SCÈNE 3D FINALE & EXPORT USDZ ──
        let scene = SCNScene()
        scene.rootNode.addChildNode(rootNode)

        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.color = UIColor(white: 0.65, alpha: 1.0)
        scene.rootNode.addChildNode(ambientLight)

        let dirLight = SCNNode()
        dirLight.light = SCNLight()
        dirLight.light?.type = .directional
        dirLight.light?.color = UIColor(white: 0.85, alpha: 1.0)
        dirLight.position = SCNVector3(x: 1, y: 3, z: 2)
        scene.rootNode.addChildNode(dirLight)

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("gabarit_3d.usdz")
        scene.write(to: fileURL, options: nil, delegate: nil, progressHandler: nil)

        return (fileURL, scene)
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
