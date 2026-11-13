import Foundation
import simd
import Combine
import UIKit

// MARK: - MotionState

enum MotionState {
    case idle
    case scanning
    case tooFast
    case complete
}

/// ViewModel gérant le verrouillage spatial fixe de l'AprilTag et l'auto-capture
@MainActor
final class ScanViewModel: ObservableObject {

    @Published private(set) var state = ScanState()
    @Published var capturedCount: Int = 0
    @Published var isTagLocked: Bool = false
    @Published var motionState: MotionState = .idle

    let targetPhotoCount: Int = 30

    var intrinsics: CameraIntrinsics = .defaultIPhone12ProMax

    // Repère spatial fixe de l'AprilTag dans le monde ARKit
    public private(set) var lockedTagWorldTransform: simd_float4x4? = nil

    // Points 3D accumulés depuis le tracking optique ARKit
    public private(set) var accumulatedPoints: [SIMD3<Float>] = []
    private var pointSpatialIndex = Set<Int64>()

    // Gestion du déplacement pour l'auto-capture
    private var lastCapturedPosition: SIMD3<Float>? = nil
    private var lastCapturedRotation: simd_quatf? = nil
    private var lastCaptureTimestamp: TimeInterval = 0

    // Seuils auto-capture
    private let minDistanceMeters: Float = 0.06
    private let minAngleDegrees: Float   = 8.0
    private let minTimeInterval: TimeInterval = 0.4

    // Seuils vitesse pour MotionState
    private let tooFastThreshold: Float   = 0.8  // m/s
    private let notMovingThreshold: Float = 0.02 // m/s

    private let hapticGenerator = UIImpactFeedbackGenerator(style: .heavy)

    var onPhotoCaptured: (() -> Void)?
    var onScanCompleted: (() -> Void)?
    var onTagLockedFirstTime: ((simd_float4x4) -> Void)?

    // Computed progress 0.0 … 1.0
    var scanProgressPercent: Double {
        guard targetPhotoCount > 0 else { return 0 }
        return min(Double(capturedCount) / Double(targetPhotoCount), 1.0)
    }

    init() {
        hapticGenerator.prepare()
    }

    func unlockTag() {
        lockedTagWorldTransform = nil
        isTagLocked = false
        lastCapturedPosition = nil
        lastCapturedRotation = nil
        motionState = .idle
        print("🔄 Repère AprilTag déverrouillé")
    }

    func addFeaturePoints(_ points: [SIMD3<Float>]) {
        for pt in points {
            let kx = Int64(round(pt.x * 250.0))
            let ky = Int64(round(pt.y * 250.0))
            let kz = Int64(round(pt.z * 250.0))
            let key = (kx & 0x1FFFFF) | ((ky & 0x1FFFFF) << 21) | ((kz & 0x1FFFFF) << 42)
            if !pointSpatialIndex.contains(key) {
                pointSpatialIndex.insert(key)
                accumulatedPoints.append(pt)
            }
        }
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

        // ── 1. VERROUILLAGE UNIQUE DE L'APRILTAG ──
        if let firstTag = tagDetections.first {
            let R = rodriguesMatrix(firstTag.rvec)
            let t = firstTag.tvec / 1000.0

            let tagToCamera = simd_float4x4(
                SIMD4( R[0], -R[3], -R[6], 0),
                SIMD4(-R[1],  R[4],  R[7], 0),
                SIMD4(-R[2],  R[5],  R[8], 0),
                SIMD4(  t.x,  -t.y,  -t.z, 1)
            )

            let calculatedTagWorld = matrix_multiply(cameraTransform, tagToCamera)

            if lockedTagWorldTransform == nil {
                lockedTagWorldTransform = calculatedTagWorld
                isTagLocked = true
                print("🔒 AprilTag FIXÉ dans l'espace !")

                // Vibration d'ancrage — heavy impact only (no AudioServices)
                hapticGenerator.impactOccurred()
                onTagLockedFirstTime?(calculatedTagWorld)
            }
        }

        // ── 2. POSITION CAMÉRA DANS LE REPÈRE DU TAG ──
        var cameraInTagFrame: CameraPositionInTagFrame? = nil
        if let tagWorld = lockedTagWorldTransform {
            let worldToTag = tagWorld.inverse
            let camInTagMat = matrix_multiply(worldToTag, cameraTransform)
            let tx = camInTagMat.columns.3.x
            let ty = camInTagMat.columns.3.y
            let tz = camInTagMat.columns.3.z
            let dist = sqrt(tx*tx + ty*ty + tz*tz) * 1000.0
            let azimuth = atan2(tx, tz) * 180.0 / .pi
            let elevation = atan2(-ty, sqrt(tx*tx + tz*tz)) * 180.0 / .pi
            cameraInTagFrame = CameraPositionInTagFrame(azimuthDeg: azimuth, elevationDeg: elevation, distanceMm: dist)
        }

        // ── 3. MISE À JOUR MOTION STATE ──
        if capturedCount >= targetPhotoCount {
            motionState = .complete
        } else if !isTagLocked {
            motionState = .idle
        } else if cameraVelocity > tooFastThreshold {
            motionState = .tooFast
        } else if cameraVelocity < notMovingThreshold && lastCapturedPosition != nil {
            motionState = .idle
        } else {
            motionState = .scanning
        }

        // ── 4. AUTO-CAPTURE ──
        var shouldCapture = false

        if isTagLocked {
            if lastCapturedPosition == nil {
                shouldCapture = true
            } else if let lastPos = lastCapturedPosition, let lastRot = lastCapturedRotation {
                let distance = simd_distance(currentPos, lastPos)
                let angleDiff = rotationAngleDifference(currentRot, lastRot)
                let timeElapsed = now - lastCaptureTimestamp

                if (distance >= minDistanceMeters || angleDiff >= minAngleDegrees) &&
                   timeElapsed >= minTimeInterval &&
                   cameraVelocity < 1.2 {
                    shouldCapture = true
                }
            }
        }

        if shouldCapture && capturedCount < targetPhotoCount {
            triggerCapture(pos: currentPos, rot: currentRot, timestamp: now)
        }

        // ── 5. MESSAGE GUIDAGE ──
        let message: String
        if capturedCount >= targetPhotoCount {
            message = "Scan complet ! Appuyez sur Terminer"
        } else if isTagLocked {
            message = "Tournez lentement autour de l'objet"
        } else {
            message = "Pointez l'AprilTag pour verrouiller le repère"
        }

        state = ScanState(
            tagDetections:    tagDetections,
            arkitPose:        ARKitPose(transform: cameraTransform, isTracking: true, velocityMagnitude: cameraVelocity),
            frameQuality:     FrameQuality(trackingLost: false, tagVisible: isTagLocked, tagPoseGood: true,
                                           isStable: cameraVelocity < 0.35, isBlurry: false, hasReflection: false),
            cameraInTagFrame: cameraInTagFrame,
            nextGuideTarget:  nil,
            capturedCount:    capturedCount,
            totalGuideViews:  targetPhotoCount,
            guideMessage:     message,
            frameSize:        frameSize
        )
    }

    func onManualCapture() {
        let now = ProcessInfo.processInfo.systemUptime
        let pos = lastCapturedPosition ?? SIMD3<Float>(0, 0, 0)
        let rot = lastCapturedRotation ?? simd_quaternion(matrix_identity_float4x4)
        triggerCapture(pos: pos, rot: rot, timestamp: now)
    }

    private func triggerCapture(pos: SIMD3<Float>, rot: simd_quatf, timestamp: TimeInterval) {
        capturedCount += 1
        lastCapturedPosition = pos
        lastCapturedRotation = rot
        lastCaptureTimestamp = timestamp

        // Heavy haptic only — no AudioServices sound
        hapticGenerator.impactOccurred()

        onPhotoCaptured?()

        if capturedCount >= targetPhotoCount {
            print("🎉 Scan complet (\(capturedCount) photos) !")
            motionState = .complete
            onScanCompleted?()
        }
    }

    private func rotationAngleDifference(_ q1: simd_quatf, _ q2: simd_quatf) -> Float {
        let dot = abs(simd_dot(q1, q2))
        let clamped = min(max(dot, -1.0), 1.0)
        let angleRad = 2.0 * acos(clamped)
        return angleRad * 180.0 / .pi
    }

    private func rodriguesMatrix(_ r: SIMD3<Float>) -> [Float] {
        let angle = sqrt(r.x*r.x + r.y*r.y + r.z*r.z)
        guard angle > 1e-6 else { return [1,0,0, 0,1,0, 0,0,1] }
        let ax = r.x/angle, ay = r.y/angle, az = r.z/angle
        let c = cos(angle), s = sin(angle), t = 1-c
        return [
            t*ax*ax+c,    t*ax*ay-s*az, t*ax*az+s*ay,
            t*ax*ay+s*az, t*ay*ay+c,    t*ay*az-s*ax,
            t*ax*az-s*ay, t*ay*az+s*ax, t*az*az+c
        ]
    }
}
