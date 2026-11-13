import Foundation
import ARKit
import SceneKit
import ModelIO
import UIKit

// MARK: - MeshProcessingService — Polycam Object Mode avec Texture Réelle & Export GLB

final class MeshProcessingService {

    /// Construit le modèle 3D Polycam avec texture photo réelle et exporte en .glb et .usdz
    static func processAndExportMesh(
        from frame: ARFrame,
        lockedTagTransform: simd_float4x4?,
        tagDetection: TagDetection? = nil,
        featurePoints: [SIMD3<Float>] = [],
        cropRadiusMm: Float = GabaritConfig.objectMaxDimMm,
        textureImage: UIImage? = nil
    ) -> (glbURL: URL, usdzURL: URL, scene: SCNScene)? {

        // 1. Calcul du repère inversé (origine au centre du tag)
        let worldToTagTransform: simd_float4x4
        if let locked = lockedTagTransform {
            worldToTagTransform = locked.inverse
        } else if let tag = tagDetection {
            let R = rodriguesMatrix(tag.rvec)
            let t = tag.tvec / 1000.0
            let tagToCamera = simd_float4x4(
                SIMD4( R[0], -R[3], -R[6], 0),
                SIMD4(-R[1],  R[4],  R[7], 0),
                SIMD4(-R[2],  R[5],  R[8], 0),
                SIMD4(  t.x,  -t.y,  -t.z, 1)
            )
            let tagToWorld = matrix_multiply(frame.camera.transform, tagToCamera)
            worldToTagTransform = tagToWorld.inverse
        } else {
            worldToTagTransform = matrix_identity_float4x4
        }

        // 2. Préparation de la texture photo réelle
        let photoTexture: UIImage
        if let given = textureImage {
            photoTexture = given
        } else if let img = pixelBufferToUIImage(frame.capturedImage) {
            photoTexture = img
        } else {
            photoTexture = createDefaultTexture()
        }

        let radiusMeters = cropRadiusMm / 1000.0
        let scene  = SCNScene()
        let root   = SCNNode()

        // 3. Matériau avec TEXTURE PHOTO RÉELLE
        let texturedMaterial = SCNMaterial()
        texturedMaterial.diffuse.contents = photoTexture
        texturedMaterial.roughness.contents = 0.45
        texturedMaterial.metalness.contents = 0.1
        texturedMaterial.isDoubleSided = true

        var primaryGeometry: SCNGeometry? = nil

        // 4. Maillage LiDAR ou Nuage de Points Optiques
        let meshAnchors = frame.anchors.compactMap { $0 as? ARMeshAnchor }

        if !meshAnchors.isEmpty {
            for meshAnchor in meshAnchors {
                let geometry = SCNGeometry.from(arMeshGeometry: meshAnchor.geometry)
                geometry.materials = [texturedMaterial]

                let node = SCNNode(geometry: geometry)
                node.simdTransform = matrix_multiply(worldToTagTransform, meshAnchor.transform)

                let dist = simd_length(node.simdPosition)
                if dist < radiusMeters * 1.5 {
                    root.addChildNode(node)
                    if primaryGeometry == nil {
                        primaryGeometry = geometry
                    }
                }
            }
        } else {
            // Sans LiDAR : Nuage de points triangulé avec texture réelle
            var pointsInTagFrame: [SIMD3<Float>] = []
            for pt in featurePoints {
                let pWorld = SIMD4<Float>(pt.x, pt.y, pt.z, 1.0)
                let pTag   = matrix_multiply(worldToTagTransform, pWorld)
                let dist   = sqrt(pTag.x*pTag.x + pTag.y*pTag.y + pTag.z*pTag.z)
                if dist < radiusMeters * 1.5 {
                    pointsInTagFrame.append(SIMD3<Float>(pTag.x, pTag.y, pTag.z))
                }
            }

            if !pointsInTagFrame.isEmpty {
                let cloudGeometry = SCNGeometry.pointCloud(from: pointsInTagFrame, size: 0.005)
                cloudGeometry.materials = [texturedMaterial]
                let cloudNode = SCNNode(geometry: cloudGeometry)
                root.addChildNode(cloudNode)
                primaryGeometry = cloudGeometry
            }
        }

        // 5. Socle discret (sol)
        let disc = SCNCylinder(radius: 0.18, height: 0.002)
        let discMat = SCNMaterial()
        discMat.diffuse.contents = UIColor(white: 0.12, alpha: 1.0)
        disc.materials = [discMat]
        let discNode = SCNNode(geometry: disc)
        discNode.position = SCNVector3(0, -0.001, 0)
        root.addChildNode(discNode)

        // 6. Petit repère AprilTag à l'origine
        let axisLen: Float = 0.02
        func makeAxis(to: SCNVector3, color: UIColor) -> SCNNode {
            SCNNode(geometry: SCNGeometry.line(from: SCNVector3Zero, to: to, color: color))
        }
        root.addChildNode(makeAxis(to: SCNVector3(axisLen, 0, 0), color: UIColor(red: 1.0, green: 0.4, blue: 0, alpha: 0.7)))
        root.addChildNode(makeAxis(to: SCNVector3(0, axisLen, 0), color: UIColor(red: 0.3, green: 0.9, blue: 0.1, alpha: 0.7)))
        root.addChildNode(makeAxis(to: SCNVector3(0, 0, axisLen), color: UIColor(red: 0.0, green: 0.898, blue: 0.816, alpha: 0.7)))

        // Éclairage de la scène
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type  = .ambient
        ambientLight.light?.color = UIColor(white: 0.65, alpha: 1.0)
        scene.rootNode.addChildNode(ambientLight)

        let dirLight = SCNNode()
        dirLight.light = SCNLight()
        dirLight.light?.type = .directional
        dirLight.light?.color = UIColor(white: 0.85, alpha: 1.0)
        dirLight.position = SCNVector3(x: 1, y: 3, z: 2)
        scene.rootNode.addChildNode(dirLight)

        scene.rootNode.addChildNode(root)

        // 7. EXPORT DU MODÈLE EN .GLB (glTF 2.0 Binary avec texture réelle)
        let tempDir = FileManager.default.temporaryDirectory
        let glbURL  = tempDir.appendingPathComponent("gabarit_model.glb")
        let usdzURL = tempDir.appendingPathComponent("gabarit_model.usdz")

        if let geom = primaryGeometry {
            _ = GLBExporter.exportSCNGeometry(geom, texture: photoTexture, to: glbURL)
        } else {
            // Export par défaut si pas de géométrie directe
            let dummy = SCNBox(width: 0.1, height: 0.1, length: 0.1, chamferRadius: 0.01)
            _ = GLBExporter.exportSCNGeometry(dummy, texture: photoTexture, to: glbURL)
        }

        // Export USDZ pour compatibilité iOS
        scene.write(to: usdzURL, options: nil, delegate: nil, progressHandler: nil)

        return (glbURL, usdzURL, scene)
    }

    private static func pixelBufferToUIImage(_ pixelBuffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private static func createDefaultTexture() -> UIImage {
        let size = CGSize(width: 512, height: 512)
        UIGraphicsBeginImageContext(size)
        UIColor(red: 0.2, green: 0.75, blue: 0.9, alpha: 1.0).setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        let img = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()
        return img
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
