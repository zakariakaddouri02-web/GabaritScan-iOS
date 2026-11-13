import Foundation
import ARKit
import SceneKit

extension SCNGeometry {

    /// Convertit le maillage physique ARMeshGeometry du LiDAR en géométrie SceneKit 3D
    static func from(arMeshGeometry: ARMeshGeometry) -> SCNGeometry {
        let vertices = arMeshGeometry.vertices
        let faces = arMeshGeometry.faces

        let vertexSource = SCNGeometrySource(
            buffer: vertices.buffer,
            vertexFormat: vertices.format,
            semantic: .vertex,
            vertexCount: vertices.count,
            dataOffset: vertices.offset,
            dataStride: vertices.stride
        )

        let faceData = Data(bytesNoCopy: faces.buffer.contents(), count: faces.buffer.length, deallocator: .none)
        let faceElement = SCNGeometryElement(
            data: faceData,
            primitiveType: .triangles,
            primitiveCount: faces.count,
            bytesPerIndex: faces.bytesPerIndex
        )

        return SCNGeometry(sources: [vertexSource], elements: [faceElement])
    }

    /// Construit une géométrie de nuage de points 3D solide (triangles octaédriques)
    /// Visible dans SceneKit et 100% compatible avec l'export USDZ/OBJ (sans LiDAR)
    static func pointCloud(from points: [SIMD3<Float>], size: Float = 0.005) -> SCNGeometry {
        guard !points.isEmpty else {
            return SCNGeometry()
        }

        var vertices: [SCNVector3] = []
        var indices: [Int32] = []
        vertices.reserveCapacity(points.count * 6)
        indices.reserveCapacity(points.count * 24)

        let half = size * 0.5
        for (i, pt) in points.enumerated() {
            let base = Int32(i * 6)
            let cx = pt.x
            let cy = pt.y
            let cz = pt.z

            // 6 sommets d'un octaèdre 3D centré sur le point
            vertices.append(SCNVector3(cx + half, cy, cz)) // 0: +X
            vertices.append(SCNVector3(cx - half, cy, cz)) // 1: -X
            vertices.append(SCNVector3(cx, cy + half, cz)) // 2: +Y
            vertices.append(SCNVector3(cx, cy - half, cz)) // 3: -Y
            vertices.append(SCNVector3(cx, cy, cz + half)) // 4: +Z
            vertices.append(SCNVector3(cx, cy, cz - half)) // 5: -Z

            // 8 faces triangulaires
            let faces: [Int32] = [
                base+0, base+2, base+4,
                base+2, base+1, base+4,
                base+1, base+3, base+4,
                base+3, base+0, base+4,
                base+2, base+0, base+5,
                base+1, base+2, base+5,
                base+3, base+1, base+5,
                base+0, base+3, base+5
            ]
            indices.append(contentsOf: faces)
        }

        let vertexSource = SCNGeometrySource(vertices: vertices)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let geom = SCNGeometry(sources: [vertexSource], elements: [element])

        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor(red: 0.1, green: 0.75, blue: 1.0, alpha: 1.0)
        mat.roughness.contents = 0.3
        mat.metalness.contents = 0.5
        geom.materials = [mat]

        return geom
    }

    /// Dessine une ligne 3D (utile pour les axes de coordonnées du tag)
    static func line(from: SCNVector3, to: SCNVector3, color: UIColor) -> SCNGeometry {
        let indices: [Int32] = [0, 1]
        let source = SCNGeometrySource(vertices: [from, to])
        let element = SCNGeometryElement(indices: indices, primitiveType: .line)
        let geom = SCNGeometry(sources: [source], elements: [element])
        geom.firstMaterial?.diffuse.contents = color
        return geom
    }
}
