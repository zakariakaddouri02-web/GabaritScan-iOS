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
    static func pointCloud(from points: [SIMD3<Float>], size: Float = 0.005) -> SCNGeometry {
        guard !points.isEmpty else { return SCNGeometry() }

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

            vertices.append(SCNVector3(cx + half, cy, cz))
            vertices.append(SCNVector3(cx - half, cy, cz))
            vertices.append(SCNVector3(cx, cy + half, cz))
            vertices.append(SCNVector3(cx, cy - half, cz))
            vertices.append(SCNVector3(cx, cy, cz + half))
            vertices.append(SCNVector3(cx, cy, cz - half))

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

    /// Dessine une ligne 3D
    static func line(from: SCNVector3, to: SCNVector3, color: UIColor) -> SCNGeometry {
        let indices: [Int32] = [0, 1]
        let source = SCNGeometrySource(vertices: [from, to])
        let element = SCNGeometryElement(indices: indices, primitiveType: .line)
        let geom = SCNGeometry(sources: [source], elements: [element])
        geom.firstMaterial?.diffuse.contents = color
        return geom
    }
}

// MARK: - Constructeurs d'Environnement 3D CAD (Style PractiCal Image 2 & 3)

struct CADSceneBuilder {

    /// Crée une grille 3D CAD métrique (lignes blanches/cyan)
    static func createGrid(sizeMeters: Float = 0.8, stepMeters: Float = 0.05, isVertical: Bool = false) -> SCNNode {
        let gridNode = SCNNode()
        let half = sizeMeters * 0.5
        var vertices: [SCNVector3] = []
        var indices: [Int32] = []
        var idx: Int32 = 0

        var val = -half
        while val <= half + 1e-4 {
            if isVertical {
                // Grille verticale murale (XY)
                vertices.append(SCNVector3(-half, val, 0))
                vertices.append(SCNVector3( half, val, 0))
                indices.append(contentsOf: [idx, idx+1])
                idx += 2

                vertices.append(SCNVector3(val, -half, 0))
                vertices.append(SCNVector3(val,  half, 0))
                indices.append(contentsOf: [idx, idx+1])
                idx += 2
            } else {
                // Grille horizontale table/sol (XZ)
                vertices.append(SCNVector3(-half, 0, val))
                vertices.append(SCNVector3( half, 0, val))
                indices.append(contentsOf: [idx, idx+1])
                idx += 2

                vertices.append(SCNVector3(val, 0, -half))
                vertices.append(SCNVector3(val, 0,  half))
                indices.append(contentsOf: [idx, idx+1])
                idx += 2
            }
            val += stepMeters
        }

        let source = SCNGeometrySource(vertices: vertices)
        let element = SCNGeometryElement(indices: indices, primitiveType: .line)
        let geom = SCNGeometry(sources: [source], elements: [element])
        geom.firstMaterial?.diffuse.contents = UIColor(white: 0.7, alpha: 0.35)
        gridNode.geometry = geom
        return gridNode
    }

    /// Crée les axes 3D du repère Tag (X: Rouge/Jaune, Y: Vert, Z: Bleu/Cyan)
    static func createAxes(length: Float = 0.08) -> SCNNode {
        let node = SCNNode()

        func makeAxis(to: SCNVector3, color: UIColor) -> SCNNode {
            let n = SCNNode(geometry: SCNGeometry.line(from: SCNVector3Zero, to: to, color: color))
            return n
        }

        node.addChildNode(makeAxis(to: SCNVector3(length, 0, 0), color: UIColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 1.0))) // X: Orange
        node.addChildNode(makeAxis(to: SCNVector3(0, length, 0), color: UIColor(red: 0.4, green: 0.9, blue: 0.1, alpha: 1.0))) // Y: Vert/Jaune
        node.addChildNode(makeAxis(to: SCNVector3(0, 0, length), color: UIColor(red: 0.1, green: 0.8, blue: 1.0, alpha: 1.0))) // Z: Cyan
        return node
    }

    /// Crée un rectangle de gabarit virtuel calibré avec libellé (Style "Rectangle 1" en Cyan / Magenta des Images 2 & 3)
    static func createCalibratedRectangle(
        width: Float,
        height: Float,
        color: UIColor,
        label: String,
        position: SCNVector3 = SCNVector3Zero
    ) -> SCNNode {
        let container = SCNNode()
        container.position = position

        let halfW = width * 0.5
        let halfH = height * 0.5

        // Cadre filaire
        let p0 = SCNVector3(-halfW, -halfH, 0)
        let p1 = SCNVector3( halfW, -halfH, 0)
        let p2 = SCNVector3( halfW,  halfH, 0)
        let p3 = SCNVector3(-halfW,  halfH, 0)

        let vertices = [p0, p1, p1, p2, p2, p3, p3, p0]
        let indices: [Int32] = [0, 1, 2, 3, 4, 5, 6, 7]
        let source = SCNGeometrySource(vertices: vertices)
        let element = SCNGeometryElement(indices: indices, primitiveType: .line)
        let borderGeom = SCNGeometry(sources: [source], elements: [element])
        borderGeom.firstMaterial?.diffuse.contents = color
        container.addChildNode(SCNNode(geometry: borderGeom))

        // Surface semi-transparente
        let plane = SCNPlane(width: CGFloat(width), height: CGFloat(height))
        let mat = SCNMaterial()
        mat.diffuse.contents = color.withAlphaComponent(0.2)
        mat.isDoubleSided = true
        plane.materials = [mat]
        container.addChildNode(SCNNode(geometry: plane))

        // Étiquette texte
        let textGeom = SCNText(string: label, extrusionDepth: 0.001)
        textGeom.font = UIFont.boldSystemFont(ofSize: 0.012)
        textGeom.firstMaterial?.diffuse.contents = color
        let textNode = SCNNode(geometry: textGeom)
        textNode.position = SCNVector3(-halfW + 0.008, halfH - 0.022, 0.002)
        textNode.scale = SCNVector3(0.5, 0.5, 0.5)
        container.addChildNode(textNode)

        return container
    }
}
