import Foundation
import ARKit
import SceneKit
import ModelIO
import UIKit

// MARK: - MeshProcessingService — Polycam Object Mode style

final class MeshProcessingService {

    /// Builds a Polycam-style 3D scene: matcap mesh or point cloud,
    /// subtle ground disc, ambient environment, small tag-origin axes.
    static func processAndExportMesh(
        from frame: ARFrame,
        lockedTagTransform: simd_float4x4?,
        tagDetection: TagDetection? = nil,
        featurePoints: [SIMD3<Float>] = [],
        cropRadiusMm: Float = GabaritConfig.objectMaxDimMm
    ) -> (fileURL: URL, scene: SCNScene)? {

        // ── Compute world→tag transform ──
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

        let radiusMeters = cropRadiusMm / 1000.0
        let scene  = SCNScene()
        let root   = SCNNode()

        // ── 1. Subtle ground disc ──
        let disc = SCNCylinder(radius: 0.18, height: 0.002)
        let discMat = SCNMaterial()
        discMat.diffuse.contents   = UIColor(white: 0.12, alpha: 1.0)
        discMat.roughness.contents = 0.9
        discMat.metalness.contents = 0.0
        discMat.isDoubleSided      = true
        disc.materials = [discMat]
        let discNode = SCNNode(geometry: disc)
        discNode.position = SCNVector3(0, -0.001, 0)
        root.addChildNode(discNode)

        // ── 2. Small AprilTag origin axes (2 cm, subtle) ──
        let axisLen: Float = 0.02
        func makeAxis(to: SCNVector3, color: UIColor) -> SCNNode {
            SCNNode(geometry: SCNGeometry.line(from: SCNVector3Zero, to: to, color: color))
        }
        root.addChildNode(makeAxis(to: SCNVector3(axisLen, 0, 0), color: UIColor(red: 1.0, green: 0.4, blue: 0, alpha: 0.7)))
        root.addChildNode(makeAxis(to: SCNVector3(0, axisLen, 0), color: UIColor(red: 0.3, green: 0.9, blue: 0.1, alpha: 0.7)))
        root.addChildNode(makeAxis(to: SCNVector3(0, 0, axisLen), color: UIColor(red: 0.0, green: 0.898, blue: 0.816, alpha: 0.7)))

        // ── 3. LiDAR mesh or point cloud ──
        let meshAnchors = frame.anchors.compactMap { $0 as? ARMeshAnchor }

        if !meshAnchors.isEmpty {
            // LiDAR mesh with matcap shading
            for meshAnchor in meshAnchors {
                let geometry  = SCNGeometry.from(arMeshGeometry: meshAnchor.geometry)
                let matcapMat = SCNGeometry.matcapMaterial()
                geometry.materials = [matcapMat]

                let node = SCNNode(geometry: geometry)
                node.simdTransform = matrix_multiply(worldToTagTransform, meshAnchor.transform)

                let dist = simd_length(node.simdPosition)
                if dist < radiusMeters * 1.5 {
                    root.addChildNode(node)
                }
            }
        } else {
            // Point cloud (no LiDAR) with matcap look
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
                let cloudGeometry  = SCNGeometry.pointCloud(from: pointsInTagFrame, size: 0.004)
                let matcapMat      = SCNGeometry.matcapMaterial()
                cloudGeometry.materials = [matcapMat]
                root.addChildNode(SCNNode(geometry: cloudGeometry))
            }
        }

        // ── 4. Lighting — soft ambient environment ──
        let ambientLight    = SCNNode()
        ambientLight.light  = SCNLight()
        ambientLight.light?.type  = .ambient
        ambientLight.light?.color = UIColor(white: 0.55, alpha: 1.0)
        scene.rootNode.addChildNode(ambientLight)

        let omni = SCNNode()
        omni.light          = SCNLight()
        omni.light?.type    = .omni
        omni.light?.color   = UIColor(white: 0.70, alpha: 1.0)
        omni.position       = SCNVector3(x: 0.5, y: 1.0, z: 0.8)
        scene.rootNode.addChildNode(omni)

        scene.rootNode.addChildNode(root)

        // ── 5. Export USDZ ──
        let tempDir  = FileManager.default.temporaryDirectory
        let fileURL  = tempDir.appendingPathComponent("gabarit_3d.usdz")
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
