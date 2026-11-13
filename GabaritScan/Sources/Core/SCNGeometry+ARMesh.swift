import Foundation
import ARKit
import SceneKit
import UIKit

// MARK: - SCNGeometry extensions — Polycam Object Mode helpers

extension SCNGeometry {

    // MARK: LiDAR mesh from ARMeshGeometry

    /// Converts ARMeshGeometry (LiDAR) to SceneKit geometry.
    static func from(arMeshGeometry: ARMeshGeometry) -> SCNGeometry {
        let vertices = arMeshGeometry.vertices
        let faces    = arMeshGeometry.faces

        let vertexSource = SCNGeometrySource(
            buffer:      vertices.buffer,
            vertexFormat: vertices.format,
            semantic:    .vertex,
            vertexCount: vertices.count,
            dataOffset:  vertices.offset,
            dataStride:  vertices.stride
        )

        let faceData = Data(bytesNoCopy: faces.buffer.contents(),
                            count: faces.buffer.length, deallocator: .none)
        let faceElement = SCNGeometryElement(
            data:            faceData,
            primitiveType:   .triangles,
            primitiveCount:  faces.count,
            bytesPerIndex:   faces.bytesPerIndex
        )

        return SCNGeometry(sources: [vertexSource], elements: [faceElement])
    }

    // MARK: Point cloud (octahedral sprites)

    /// Builds a dense point-cloud geometry from an array of 3D positions.
    static func pointCloud(from points: [SIMD3<Float>], size: Float = 0.005) -> SCNGeometry {
        guard !points.isEmpty else { return SCNGeometry() }

        var vertices: [SCNVector3] = []
        var indices:  [Int32]      = []
        vertices.reserveCapacity(points.count * 6)
        indices.reserveCapacity(points.count * 24)

        let half = size * 0.5
        for (i, pt) in points.enumerated() {
            let base: Int32 = Int32(i * 6)
            let cx = pt.x, cy = pt.y, cz = pt.z

            vertices.append(SCNVector3(cx + half, cy, cz))  // +X
            vertices.append(SCNVector3(cx - half, cy, cz))  // -X
            vertices.append(SCNVector3(cx, cy + half, cz))  // +Y
            vertices.append(SCNVector3(cx, cy - half, cz))  // -Y
            vertices.append(SCNVector3(cx, cy, cz + half))  // +Z
            vertices.append(SCNVector3(cx, cy, cz - half))  // -Z

            indices.append(contentsOf: [
                base+0, base+2, base+4,
                base+2, base+1, base+4,
                base+1, base+3, base+4,
                base+3, base+0, base+4,
                base+2, base+0, base+5,
                base+1, base+2, base+5,
                base+3, base+1, base+5,
                base+0, base+3, base+5
            ])
        }

        let source  = SCNGeometrySource(vertices: vertices)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        return SCNGeometry(sources: [source], elements: [element])
    }

    // MARK: Line segment helper

    /// Draws a simple 3D line segment between two world-space points.
    static func line(from: SCNVector3, to: SCNVector3, color: UIColor) -> SCNGeometry {
        let indices: [Int32] = [0, 1]
        let source  = SCNGeometrySource(vertices: [from, to])
        let element = SCNGeometryElement(indices: indices, primitiveType: .line)
        let geom    = SCNGeometry(sources: [source], elements: [element])
        geom.firstMaterial?.diffuse.contents = color
        return geom
    }

    // MARK: Matcap material (Polycam scan-preview look)

    /// Returns a SceneKit material that mimics Polycam's matcap shading:
    /// bright specular highlights on mesh edges, cool blue-grey tones.
    /// Uses SCNMaterial.shaderModifiers to implement a reflect-based UV lookup.
    static func matcapMaterial() -> SCNMaterial {
        let mat = SCNMaterial()

        // Base appearance — cool light blue-grey
        mat.diffuse.contents   = UIColor(red: 0.85, green: 0.90, blue: 0.95, alpha: 1.0)
        mat.metalness.contents = 0.7
        mat.roughness.contents = 0.1
        mat.isDoubleSided      = true
        mat.lightingModel      = .physicallyBased

        // Matcap shader modifier — reflect-based sphere UV lookup.
        // This replicates the matcap technique used in Polycam's matcap.metal:
        //   uv = reflect(viewDir, normal) → map to hemisphere UV.
        let matcapSurface = """
        #pragma arguments
        // no extra args needed

        #pragma body
        // Compute view-space normal for the matcap UV
        float3 N = normalize(_surface.normalWS);
        float3 V = normalize(_surface.position - scn_frame.inverseViewTransform[3].xyz);
        float3 R = reflect(V, N);

        // Sphere mapping: UV from reflection direction
        float m = 2.0 * sqrt(R.x * R.x + R.y * R.y + (R.z + 1.0) * (R.z + 1.0));
        float2 matcapUV = float2(R.x / m + 0.5, R.y / m + 0.5);

        // Polycam-style: blend bright highlight near specular pole
        float highlight = pow(max(0.0, dot(R, float3(0, 0, 1))), 6.0);
        float3 baseColor = float3(0.85, 0.90, 0.95);
        float3 specColor = float3(1.0, 1.0, 1.0);
        _surface.diffuse = float4(mix(baseColor, specColor, highlight * 0.75), 1.0);
        """

        mat.shaderModifiers = [SCNShaderModifierEntryPoint.surface: matcapSurface]
        return mat
    }
}
