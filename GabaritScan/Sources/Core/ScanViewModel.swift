import Foundation
import simd
import Combine

/// ViewModel principal
@MainActor
final class ScanViewModel: ObservableObject {

    @Published private(set) var state = ScanState()

    var intrinsics: CameraIntrinsics = .defaultIPhone12ProMax

    private let orbitGuide = OrbitGuide()
    private var capturedIndices = Set<Int>()

    // MARK: - Appelé à chaque frame ARKit

    func onFrameProcessed(
        arkitPose: ARKitPose?,
        tagDetections: [TagDetection],
        frameSize: CGSize
    ) {
        let quality = computeQuality(pose: arkitPose, detections: tagDetections)

        let cameraPos: CameraPositionInTagFrame? = tagDetections.first.map {
            CameraPositionInTagFrame(
                azimuthDeg:   $0.azimuthDeg,
                elevationDeg: $0.elevationDeg,
                distanceMm:   $0.distanceMm
            )
        }

        // Marquer la vue guide la plus proche comme couverte si la qualité est bonne
        if let pos = cameraPos, quality.isGoodEnoughForCapture {
            if let idx = orbitGuide.closestViewIndex(to: pos) {
                capturedIndices.insert(idx)
            }
        }

        let nextTarget = orbitGuide.nextTarget(from: cameraPos, captured: capturedIndices)

        state = ScanState(
            tagDetections:    tagDetections,
            arkitPose:        arkitPose,
            frameQuality:     quality,
            cameraInTagFrame: cameraPos,
            nextGuideTarget:  nextTarget,
            capturedCount:    capturedIndices.count,
            totalGuideViews:  GabaritConfig.numGuideViews,
            guideMessage:     buildGuideMessage(quality, detections: tagDetections,
                                                next: nextTarget, current: cameraPos),
            frameSize:        frameSize
        )
    }

    func onManualCapture() {
        if let idx = state.nextGuideTarget?.viewIndex {
            capturedIndices.insert(idx)
            // Forcer la mise à jour immédiate
            let nextTarget = orbitGuide.nextTarget(from: state.cameraInTagFrame, captured: capturedIndices)
            state.capturedCount = capturedIndices.count
            state.nextGuideTarget = nextTarget
            state.guideMessage = buildGuideMessage(state.frameQuality, detections: state.tagDetections,
                                                   next: nextTarget, current: state.cameraInTagFrame)
        }
    }

    // MARK: - Qualité (le tag visible suffit pour assurer le tracking)

    private func computeQuality(pose: ARKitPose?,
                                detections: [TagDetection]) -> FrameQuality {
        let tagVisible = !detections.isEmpty
        // Si le tag est visible, le tracking n'est PAS perdu même si ARKit initialise encore
        let trackingOk = tagVisible || (pose?.isTracking ?? false)

        return FrameQuality(
            trackingLost:  !trackingOk,
            tagVisible:    tagVisible,
            tagPoseGood:   detections.first.map { $0.reprojectionError < 3.0 } ?? false,
            isStable:      pose.map { $0.velocityMagnitude < 0.15 } ?? true,
            isBlurry:      false,
            hasReflection: false
        )
    }

    // MARK: - Message guide

    private func buildGuideMessage(
        _ q: FrameQuality,
        detections: [TagDetection],
        next: GuideViewTarget?,
        current: CameraPositionInTagFrame?
    ) -> String {
        if !q.tagVisible && q.trackingLost {
            return "🔍 Pointez la caméra vers le tag AprilTag"
        }
        if !q.isStable {
            return "🛑 Restez stable — bougez plus lentement"
        }
        guard let next else {
            return "🎉 Scan terminé ! 24/24 vues capturées."
        }

        var dAz = next.azimuthDeg - (current?.azimuthDeg ?? 0)
        while dAz >  180 { dAz -= 360 }
        while dAz < -180 { dAz += 360 }
        let dEl = next.elevationDeg - (current?.elevationDeg ?? 0)

        let h = abs(dAz) > 12 ? (dAz > 0 ? "Tournez vers la droite →" : "← Tournez vers la gauche") : ""
        let v = abs(dEl) > 8 ? (dEl > 0 ? "↑ Montez légèrement" : "↓ Descendez légèrement") : ""
        let directions = [h, v].filter { !$0.isEmpty }.joined(separator: "\n")

        let header = "📷 Vue \(next.viewIndex + 1)/\(GabaritConfig.numGuideViews)"
        if directions.isEmpty {
            return "\(header)\n✅ Parfait ! Appuyez sur le bouton blanc"
        } else {
            return "\(header)\n\(directions)"
        }
    }
}
