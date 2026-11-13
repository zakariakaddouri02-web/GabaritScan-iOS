import Foundation
import UIKit
import SceneKit
import simd

/// Exportateur glTF 2.0 Binary (.glb) avec texture embarquée
/// Conforme au standard glTF 2.0 (compatible Blender, Windows 3D, WebGL, Three.js, Polycam)
final class GLBExporter {

    struct Vertex {
        var position: SIMD3<Float>
        var normal: SIMD3<Float>
        var texCoord: SIMD2<Float>
    }

    /// Exporte un ensemble de sommets, indices et une image de texture dans un fichier .glb
    static func export(
        vertices: [Vertex],
        indices: [UInt32],
        texture: UIImage,
        to fileURL: URL
    ) -> Bool {
        guard !vertices.isEmpty, !indices.isEmpty else { return false }

        // 1. Préparation de l'image JPEG
        guard let jpegData = texture.jpegData(compressionQuality: 0.85) else { return false }

        // 2. Calcul des Bounding Box min/max pour l'accesseur POSITION
        var minPos = SIMD3<Float>(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
        var maxPos = SIMD3<Float>(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)

        for v in vertices {
            minPos = simd_min(minPos, v.position)
            maxPos = simd_max(maxPos, v.position)
        }

        // 3. Construction des buffers binaires
        var posData = Data(capacity: vertices.count * 12)
        var normData = Data(capacity: vertices.count * 12)
        var uvData = Data(capacity: vertices.count * 8)

        for v in vertices {
            var px = v.position.x; var py = v.position.y; var pz = v.position.z
            posData.append(UnsafeBufferPointer(start: &px, count: 1))
            posData.append(UnsafeBufferPointer(start: &py, count: 1))
            posData.append(UnsafeBufferPointer(start: &pz, count: 1))

            var nx = v.normal.x; var ny = v.normal.y; var nz = v.normal.z
            normData.append(UnsafeBufferPointer(start: &nx, count: 1))
            normData.append(UnsafeBufferPointer(start: &ny, count: 1))
            normData.append(UnsafeBufferPointer(start: &nz, count: 1))

            var u = v.texCoord.x; var vCoord = v.texCoord.y
            uvData.append(UnsafeBufferPointer(start: &u, count: 1))
            uvData.append(UnsafeBufferPointer(start: &vCoord, count: 1))
        }

        // Indices (UInt16 si possible pour économiser la mémoire, sinon UInt32)
        let useUInt16 = vertices.count < 65536
        var idxData = Data()
        if useUInt16 {
            idxData.reserveCapacity(indices.count * 2)
            for idx in indices {
                var s = UInt16(idx)
                idxData.append(UnsafeBufferPointer(start: &s, count: 1))
            }
        } else {
            idxData.reserveCapacity(indices.count * 4)
            for idx in indices {
                var s = idx
                idxData.append(UnsafeBufferPointer(start: &s, count: 1))
            }
        }

        // Alignement des buffers sur 4 octets
        func pad4(_ data: inout Data) {
            let rem = data.count % 4
            if rem > 0 {
                data.append(Data(repeating: 0, count: 4 - rem))
            }
        }

        pad4(&posData)
        pad4(&normData)
        pad4(&uvData)
        pad4(&idxData)

        var imageAlignedData = jpegData
        pad4(&imageAlignedData)

        // Offsets des BufferViews
        let posOffset = 0
        let posLen = posData.count

        let normOffset = posOffset + posLen
        let normLen = normData.count

        let uvOffset = normOffset + normLen
        let uvLen = uvData.count

        let idxOffset = uvOffset + uvLen
        let idxLen = idxData.count

        let imgOffset = idxOffset + idxLen
        let imgLen = imageAlignedData.count

        let totalBinLen = imgOffset + imgLen

        // 4. Assemblage du BIN Chunk complet
        var binChunk = Data(capacity: totalBinLen)
        binChunk.append(posData)
        binChunk.append(normData)
        binChunk.append(uvData)
        binChunk.append(idxData)
        binChunk.append(imageAlignedData)

        // 5. Construction du JSON glTF 2.0
        let indexComponentType = useUInt16 ? 5123 : 5125 // 5123 = UNSIGNED_SHORT, 5125 = UNSIGNED_INT

        let gltfJson: [String: Any] = [
            "asset": [
                "version": "2.0",
                "generator": "GabaritScan Polycam Engine"
            ],
            "scene": 0,
            "scenes": [
                ["nodes": [0]]
            ],
            "nodes": [
                [
                    "mesh": 0,
                    "name": "GabaritTexturedModel"
                ]
            ],
            "meshes": [
                [
                    "name": "GabaritMesh",
                    "primitives": [
                        [
                            "attributes": [
                                "POSITION": 0,
                                "NORMAL": 1,
                                "TEXCOORD_0": 2
                            ],
                            "indices": 3,
                            "material": 0,
                            "mode": 4 // TRIANGLES
                        ]
                    ]
                ]
            ],
            "materials": [
                [
                    "name": "GabaritPhotorealisticTexture",
                    "pbrMetallicRoughness": [
                        "baseColorTexture": ["index": 0],
                        "metallicFactor": 0.05,
                        "roughnessFactor": 0.55
                    ],
                    "doubleSided": true
                ]
            ],
            "textures": [
                ["sampler": 0, "source": 0]
            ],
            "images": [
                ["bufferView": 4, "mimeType": "image/jpeg"]
            ],
            "samplers": [
                [
                    "magFilter": 9729, // LINEAR
                    "minFilter": 9987, // LINEAR_MIPMAP_LINEAR
                    "wrapS": 10497,    // REPEAT
                    "wrapT": 10497
                ]
            ],
            "accessors": [
                // 0: POSITION
                [
                    "bufferView": 0,
                    "byteOffset": 0,
                    "componentType": 5126, // FLOAT
                    "count": vertices.count,
                    "type": "VEC3",
                    "min": [minPos.x, minPos.y, minPos.z],
                    "max": [maxPos.x, maxPos.y, maxPos.z]
                ],
                // 1: NORMAL
                [
                    "bufferView": 1,
                    "byteOffset": 0,
                    "componentType": 5126,
                    "count": vertices.count,
                    "type": "VEC3"
                ],
                // 2: TEXCOORD_0
                [
                    "bufferView": 2,
                    "byteOffset": 0,
                    "componentType": 5126,
                    "count": vertices.count,
                    "type": "VEC2"
                ],
                // 3: INDICES
                [
                    "bufferView": 3,
                    "byteOffset": 0,
                    "componentType": indexComponentType,
                    "count": indices.count,
                    "type": "SCALAR"
                ]
            ],
            "bufferViews": [
                // 0: Positions
                ["buffer": 0, "byteOffset": posOffset, "byteLength": posLen, "target": 34962],
                // 1: Normals
                ["buffer": 0, "byteOffset": normOffset, "byteLength": normLen, "target": 34962],
                // 2: UVs
                ["buffer": 0, "byteOffset": uvOffset, "byteLength": uvLen, "target": 34962],
                // 3: Indices
                ["buffer": 0, "byteOffset": idxOffset, "byteLength": idxLen, "target": 34963],
                // 4: JPEG Image
                ["buffer": 0, "byteOffset": imgOffset, "byteLength": jpegData.count]
            ],
            "buffers": [
                ["byteLength": totalBinLen]
            ]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: gltfJson, options: []) else {
            return false
        }

        var jsonAlignedData = jsonData
        let jsonRem = jsonAlignedData.count % 4
        if jsonRem > 0 {
            // Dans glTF, le JSON chunk doit être paddé avec des espaces (0x20)
            jsonAlignedData.append(Data(repeating: 0x20, count: 4 - jsonRem))
        }

        // 6. Construction du conteneur GLB
        // Header (12 octets): magic (0x46546C67), version (2), totalLength
        let totalFileLength = 12 + 8 + jsonAlignedData.count + 8 + binChunk.count
        var glbData = Data(capacity: totalFileLength)

        var magic: UInt32 = 0x46546C67 // "glTF"
        var version: UInt32 = 2
        var fileLen: UInt32 = UInt32(totalFileLength)

        glbData.append(UnsafeBufferPointer(start: &magic, count: 1))
        glbData.append(UnsafeBufferPointer(start: &version, count: 1))
        glbData.append(UnsafeBufferPointer(start: &fileLen, count: 1))

        // Chunk 0: JSON (8 octets header + data)
        var jsonLen: UInt32 = UInt32(jsonAlignedData.count)
        var jsonType: UInt32 = 0x4E4F534A // "JSON"
        glbData.append(UnsafeBufferPointer(start: &jsonLen, count: 1))
        glbData.append(UnsafeBufferPointer(start: &jsonType, count: 1))
        glbData.append(jsonAlignedData)

        // Chunk 1: BIN (8 octets header + data)
        var binLen: UInt32 = UInt32(binChunk.count)
        var binType: UInt32 = 0x004E4942 // "BIN\0"
        glbData.append(UnsafeBufferPointer(start: &binLen, count: 1))
        glbData.append(UnsafeBufferPointer(start: &binType, count: 1))
        glbData.append(binChunk)

        // 7. Écriture du fichier sur le disque
        do {
            try glbData.write(to: fileURL)
            print("✅ Modèle 3D TEXTURÉ GLB généré avec succès (\(totalFileLength / 1024) Ko) à : \(fileURL.path)")
            return true
        } catch {
            print("❌ Erreur écriture GLB : \(error)")
            return false
        }
    }

    /// Convertit une géométrie SCNGeometry (ou maillage LiDAR/Points) avec texture en fichier .glb
    static func exportSCNGeometry(
        _ geometry: SCNGeometry,
        texture: UIImage,
        to fileURL: URL
    ) -> Bool {
        guard let vertexSource = geometry.sources(for: .vertex).first,
              let element = geometry.elements.first else {
            return false
        }

        let vertexCount = vertexSource.vectorCount
        var vertices: [Vertex] = []
        vertices.reserveCapacity(vertexCount)

        // Extraction des positions
        let posPointer = vertexSource.data.withUnsafeBytes { $0.baseAddress! }
        let stride = vertexSource.dataStride
        let offset = vertexSource.dataOffset

        var minP = SIMD3<Float>(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
        var maxP = SIMD3<Float>(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)

        for i in 0..<vertexCount {
            let byteOffset = offset + i * stride
            let ptr = posPointer.advanced(by: byteOffset).assumingMemoryBound(to: Float.self)
            let p = SIMD3<Float>(ptr[0], ptr[1], ptr[2])
            minP = simd_min(minP, p)
            maxP = simd_max(maxP, p)

            // Calcul normal approximé ou pointant vers l'extérieur
            let norm = simd_length(p) > 1e-4 ? simd_normalize(p) : SIMD3<Float>(0, 1, 0)
            vertices.append(Vertex(position: p, normal: norm, texCoord: SIMD2<Float>(0, 0)))
        }

        // Calcul des coordonnées UV basées sur la projection orthogonale / boîte
        let sizeX = max(maxP.x - minP.x, 0.001)
        let sizeZ = max(maxP.z - minP.z, 0.001)
        let sizeY = max(maxP.y - minP.y, 0.001)

        for i in 0..<vertexCount {
            let p = vertices[i].position
            // UV mapping planaire XZ / XY
            let u = (p.x - minP.x) / sizeX
            let v = 1.0 - ((p.z - minP.z) / sizeZ)
            vertices[i].texCoord = SIMD2<Float>(min(max(u, 0), 1), min(max(v, 0), 1))
        }

        // Extraction des indices
        var indices: [UInt32] = []
        let idxCount = element.primitiveCount * 3
        indices.reserveCapacity(idxCount)

        element.data.withUnsafeBytes { rawPtr in
            let bytesPerIdx = element.bytesPerIndex
            let base = rawPtr.baseAddress!
            for i in 0..<idxCount {
                if bytesPerIdx == 2 {
                    let val = base.advanced(by: i * 2).assumingMemoryBound(to: UInt16.self).pointee
                    indices.append(UInt32(val))
                } else {
                    let val = base.advanced(by: i * 4).assumingMemoryBound(to: UInt32.self).pointee
                    indices.append(val)
                }
            }
        }

        return export(vertices: vertices, indices: indices, texture: texture, to: fileURL)
    }
}
