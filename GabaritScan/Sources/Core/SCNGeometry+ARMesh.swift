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
