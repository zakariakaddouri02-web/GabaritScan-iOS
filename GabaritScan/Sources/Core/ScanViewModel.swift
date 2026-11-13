import Foundation
import simd
import Combine
import UIKit
import AudioToolbox

/// ViewModel avec Auto-Capture fluide basée sur le déplacement (comme Polycam)
@MainActor
final class ScanViewModel: ObservableObject {

    @Published private(set) var state = ScanState()
    @Published var capturedCount: Int = 0
    let targetPhotoCount: Int = 30

    var intrinsics: CameraIntrinsics = .defaultIPhone12ProMax

    // Gestion du déplacement pour l'auto-capture
    private var lastCapturedPosition: SIMD3<Float>? = nil
    private var lastCapturedRotation: simd_quatf? = nil
    private var lastCaptureTimestamp: TimeInterval = 0

    // Seuils de déclenchement (déplacement de 8 cm OU rotation de 12°)
    private let minDistanceMeters: Float = 0.07 // 7 cm
    private let minAngleDegrees: Float   = 10.0 // 10 degrés
    private let minTimeInterval: TimeInterval = 0.6 // 0.6 seconde entre photos

    private let hapticGenerator = UIImpactFeedbackGenerator(style: .heavy)

    var onPhotoCaptured: (() -> Void)?
    var onScanCompleted: (() -> Void)?

    init() {
        hapticGenerator.prepare()
    }

    // MARK: - Traitement de chaque frame

    func onFrameProcessed(
        cameraTransform: simd_float4x4,
        cameraVelocity: Float,
        tagDetections: [TagDetection],
        frameSize: CGSize
    ) {
        let currentPos = SIMD3<Float>(cameraTransform.columns.3.x, cameraTransform.columns.3.y, cameraTransform.columns.3.z)
        let currentRot = simd_quaternion(cameraTransform)
        let now = ProcessInfo.processInfo.systemUptime

        // ── AUTO-CAPTURE BASÉE SUR LE DÉPLACEMENT ──
        var shouldCapture = false

        if lastCapturedPosition == nil {
            // Première photo automatique dès que l'AprilTag est détecté
            if !tagDetections.isEmpty {
                shouldCapture = true
            }
        } else if let lastPos = lastCapturedPosition, let lastRot = lastCapturedRotation {
            let distance = simd_distance(currentPos, lastPos)
            let angleDiff = rotationAngleDifference(currentRot, lastRot)
            let timeElapsed = now - lastCaptureTimestamp

            // Déclencher si on a bougé de 7 cm OU tourné de 10° (et pas trop de flou de mouvement)
            if (distance >= minDistanceMeters || angleDiff >= minAngleDegrees) &&
               timeElapsed >= minTimeInterval &&
               cameraVelocity < 0.35 {
                shouldCapture = true
            }
        }

        if shouldCapture {
            triggerCapture(pos: currentPos, rot: currentRot, timestamp: now)
        }

        let tagVisible = !tagDetections.isEmpty
        let message: String
        if capturedCount >= targetPhotoCount {
            message = "🎉 Capture terminée (\(capturedCount) photos) ! Appuyez sur 'Générer 3D'"
        } else if tagVisible {
            message = "📸 Tournez autour de l'objet... (\(capturedCount)/\(targetPhotoCount))"
        } else {
            message = "🔍 Pointez vers l'AprilTag pour caler le gabarit"
        }

        state = ScanState(
            tagDetections:    tagDetections,
            arkitPose:        ARKitPose(transform: cameraTransform, isTracking: true, velocityMagnitude: cameraVelocity),
            frameQuality:     FrameQuality(trackingLost: false, tagVisible: tagVisible, tagPoseGood: true, isStable: cameraVelocity < 0.25, isBlurry: false, hasReflection: false),
            cameraInTagFrame: tagDetections.first.map { CameraPositionInTagFrame(azimuthDeg: $0.azimuthDeg, elevationDeg: $0.elevationDeg, distanceMm: $0.distanceMm) },
            nextGuideTarget:  nil,
            capturedCount:    capturedCount,
            totalGuideViews:  targetPhotoCount,
            guideMessage:     message,
            frameSize:        frameSize
        )
    }

    func onManualCapture() {
        guard let lastPos = lastCapturedPosition, let lastRot = lastCapturedRotation else {
            triggerCapture(pos: SIMD3<Float>(0,0,0), rot: simd_quaternion(matrix_identity_float4x4), timestamp: ProcessInfo.processInfo.systemUptime)
            return
        }
        triggerCapture(pos: lastPos, rot: lastRot, timestamp: ProcessInfo.processInfo.systemUptime)
    }

    private func triggerCapture(pos: SIMD3<Float>, rot: simd_quatf, timestamp: TimeInterval) {
        capturedCount += 1
        lastCapturedPosition = pos
        lastCapturedRotation = rot
        lastCaptureTimestamp = timestamp

        // VIBRATION FORTE ET DIRECTE
        AudioServicesPlaySystemSound(1519) // Vibration haptique Peek
        hapticGenerator.impactOccurred()

        onPhotoCaptured?()

        if capturedCount >= targetPhotoCount {
            onScanCompleted?()
        }
    }

    private func rotationAngleDifference(_ q1: simd_quatf, _ q2: simd_quatf) -> Float {
        let dot = abs(simd_dot(q1, q2))
        let clamped = min(max(dot, -1.0), 1.0)
        let angleRad = 2.0 * acos(clamped)
        return angleRad * 180.0 / .pi
    }
}
