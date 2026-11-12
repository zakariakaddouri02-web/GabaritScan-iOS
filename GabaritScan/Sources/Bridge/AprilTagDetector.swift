// AprilTagDetector.swift
// Wrapper Swift pur autour de AprilTagDetectorObjC.
// Convertit les TagDetectionObjC → TagDetection (struct Swift).

import Foundation
import CoreVideo
import simd

final class AprilTagDetector {

    private let bridge: AprilTagDetectorObjC

    init(tagSizeMm: Float = GabaritConfig.tagSizeMm) {
        bridge = AprilTagDetectorObjC(
            tagFamily: GabaritConfig.tagFamilyId,
            tagSizeMm: tagSizeMm
        )
    }

    /// Détecter les AprilTags dans un CVPixelBuffer (format kCVPixelFormatType_420YpCbCr8BiPlanarFullRange).
    /// Le plan 0 est le plan Y (luminance) — utilisé pour la détection.
    func detect(pixelBuffer: CVPixelBuffer,
                intrinsics: CameraIntrinsics) -> [TagDetection] {

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let yPlane = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return [] }

        let width     = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height    = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let rowStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)

        let raw = bridge.detect(
            inYData: yPlane.assumingMemoryBound(to: UInt8.self),
            rowStride: rowStride, width: width, height: height,
            fx: intrinsics.fx, fy: intrinsics.fy,
            cx: intrinsics.cx, cy: intrinsics.cy
        )

        return raw.map { d in
            let c = d.corners.map { CGFloat($0.floatValue) }
            let corners: [CGPoint] = stride(from: 0, to: 8, by: 2).map {
                CGPoint(x: c[$0], y: c[$0+1])
            }
            return TagDetection(
                tagId:            d.tagId,
                corners:          corners,
                rvec:             SIMD3(d.rvec[0].floatValue, d.rvec[1].floatValue, d.rvec[2].floatValue),
                tvec:             SIMD3(d.tvec[0].floatValue, d.tvec[1].floatValue, d.tvec[2].floatValue),
                reprojectionError: d.reprojectionError,
                azimuthDeg:       d.azimuthDeg,
                elevationDeg:     d.elevationDeg,
                distanceMm:       d.distanceMm
            )
        }
    }
}
