import Foundation
import simd
import Combine

/// ViewModel principal — même logique que ScanViewModel.kt (Android)
/// Coordonne ARKit + AprilTag + OrbitGuide → ScanState publié via @Published
@MainActor
final class ScanViewModel: ObservableObject {

    @Published private(set) var state = ScanState()

    // Intrinsèques caméra (mis à jour depuis AVCaptureDevice)
    var intrinsics: CameraIntrinsics = .defaultIPhone12ProMax

    private let orbitGuide = OrbitGuide()
    private var capturedIndices = Set<Int>()

    // MARK: - Appelé par ScanViewController à chaque frame

    func onFrameProcessed(
        arkitPose: ARKitPose?,
        tagDetections: [TagDetection],
        frameSize: CGSize
    ) {
        let quality = computeQuality(pose: arkitPose, detections: tagDetections)

        // Position sphérique courante de la caméra dans le repère du tag
        let cameraPos: CameraPositionInTagFrame? = tagDetections.first.map {
            CameraPositionInTagFrame(
                azimuthDeg:   $0.azimuthDeg,
                elevationDeg: $0.elevationDeg,
                distanceMm:   $0.distanceMm
            )
        }

        // Marquer la vue guide la plus proche comme couverte
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
        // Phase 2 : déclencher AVCapturePhotoOutput
        if let idx = state.nextGuideTarget?.viewIndex {
            capturedIndices.insert(idx)
        }
    }

    // MARK: - Qualité

    private func computeQuality(pose: ARKitPose?,
                                detections: [TagDetection]) -> FrameQuality {
        FrameQuality(
            trackingLost:  pose == nil || !(pose?.isTracking ?? false),
            tagVisible:    !detections.isEmpty,
            tagPoseGood:   detections.first.map { $0.reprojectionError < 2.0 } ?? false,
            isStable:      pose.map { $0.velocityMagnitude < 0.05 } ?? true,
            isBlurry:      false,   // Phase 2 : variance Laplacien sur plan Y
            hasReflection: false    // Phase 2
        )
    }

    // MARK: - Message guide

    private func buildGuideMessage(
        _ q: FrameQuality,
        detections: [TagDetection],
        next: GuideViewTarget?,
        current: CameraPositionInTagFrame?
    ) -> String {
        if q.trackingLost  { return "⚠️ Tracking perdu — Pointez vers le tag" }
        if !q.tagVisible   { return "🔍 Montrez le tag AprilTag dans le cadre" }
        if !q.isStable     { return "🛑 Restez stable — bougez plus lentement" }
        if !q.tagPoseGood  { return "⚠️ Pose du tag imprécise — rapprochez-vous" }
        guard let next else { return "✅ Scan terminé ! Exportez la session." }

        var dAz = next.azimuthDeg - (current?.azimuthDeg ?? 0)
        while dAz >  180 { dAz -= 360 }
        while dAz < -180 { dAz += 360 }
        let dEl = next.elevationDeg - (current?.elevationDeg ?? 0)

        let h = abs(dAz) > 15 ? (dAz > 0 ? "→ Déplacez-vous vers la droite" : "← vers la gauche") : ""
        let v = abs(dEl) > 10 ? (dEl > 0 ? "↑ Montez légèrement" : "↓ Descendez") : ""
        let arrow = [h, v].filter { !$0.isEmpty }.joined(separator: "\n")

        let header = "📷 Vue \(next.viewIndex + 1)/\(GabaritConfig.numGuideViews)"
        return arrow.isEmpty ? "\(header)\n✅ Bonne position ! Capturez." : "\(header)\n\(arrow)"
    }
}
