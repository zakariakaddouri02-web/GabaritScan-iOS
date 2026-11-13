import Foundation
import simd
import Combine
import UIKit

/// ViewModel principal avec Auto-Capture intelligente et déclenchement automatique
@MainActor
final class ScanViewModel: ObservableObject {

    @Published private(set) var state = ScanState()
    @Published var isAutoCaptureEnabled: Bool = true

    var intrinsics: CameraIntrinsics = .defaultIPhone12ProMax

    private let orbitGuide = OrbitGuide()
    private var capturedIndices = Set<Int>()

    // Gestion de l'Auto-Capture
    private var lastAutoCaptureTime: TimeInterval = 0
    private let autoCaptureCooldown: TimeInterval = 1.0 // 1 seconde minimum entre chaque photo
    private let hapticFeedback = UIImpactFeedbackGenerator(style: .medium)

    var onPhotoCaptured: (() -> Void)?
    var onScanCompleted: (() -> Void)?

    init() {
        hapticFeedback.prepare()
    }

    // MARK: - Appelé à chaque frame

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

        // ── AUTO-CAPTURE INTELLIGENTE ──
        if isAutoCaptureEnabled, let pos = cameraPos, quality.isGoodEnoughForCapture {
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastAutoCaptureTime > autoCaptureCooldown {
                if let closestIdx = orbitGuide.closestViewIndex(to: pos), !capturedIndices.contains(closestIdx) {
                    triggerCapture(index: closestIdx)
                    lastAutoCaptureTime = now
                }
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
            triggerCapture(index: idx)
        }
    }

    private func triggerCapture(index: Int) {
        capturedIndices.insert(index)
        hapticFeedback.impactOccurred()
        onPhotoCaptured?()

        if capturedIndices.count >= GabaritConfig.numGuideViews {
            onScanCompleted?()
        }
    }

    // MARK: - Qualité

    private func computeQuality(pose: ARKitPose?,
                                detections: [TagDetection]) -> FrameQuality {
        let tagVisible = !detections.isEmpty
        let trackingOk = tagVisible || (pose?.isTracking ?? false)

        return FrameQuality(
            trackingLost:  !trackingOk,
            tagVisible:    tagVisible,
            tagPoseGood:   detections.first.map { $0.reprojectionError < 3.0 } ?? false,
            // Stable si vitesse < 0.12 m/s
            isStable:      pose.map { $0.velocityMagnitude < 0.12 } ?? true,
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
            return "🔍 Pointez vers l'AprilTag pour caler le repère"
        }
        if !q.isStable {
            return "🛑 Ne bougez plus — capture en cours..."
        }
        guard let next else {
            return "🎉 Scan terminé ! Tapez 'Générer 3D' pour visualiser."
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
            return "\(header)\n📸 Stabilisez pour capturer automatiquement !"
        } else {
            return "\(header)\n\(directions)"
        }
    }
}
