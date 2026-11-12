import Foundation
import simd

// MARK: - Paramètres configurables du gabarit

struct GabaritConfig {
    /// Taille réelle du tag AprilTag (côté externe), en mm
    static var tagSizeMm: Float = 80.0

    /// Dimension maximale du gabarit (pour le calcul de distance guide), en mm
    static var objectMaxDimMm: Float = 300.0

    /// Type de surface : matte, glossy, metallic
    static var surfaceFinish: String = "matte"

    /// Nombre de vues orbitales à capturer
    static var numGuideViews: Int = 24

    /// Famille AprilTag (0 = tag36h11)
    static var tagFamilyId: Int = 0
}

// MARK: - Détection AprilTag

struct TagDetection {
    let tagId: Int
    /// Coins détectés en pixels (4 × CGPoint)
    let corners: [CGPoint]
    /// Vecteur de Rodrigues (rotation tag→caméra)
    let rvec: SIMD3<Float>
    /// Translation tag→caméra en mm
    let tvec: SIMD3<Float>
    /// Erreur de reprojection moyenne (pixels)
    let reprojectionError: Float
    /// Position sphérique de la caméra dans le repère du tag
    let azimuthDeg: Float
    let elevationDeg: Float
    let distanceMm: Float
}

// MARK: - Pose ARKit

struct ARKitPose {
    /// Matrice 4×4 position/orientation du téléphone dans le monde ARKit
    let transform: simd_float4x4
    let isTracking: Bool
    /// Magnitude de vitesse estimée (m/s) — pour détecter la stabilité
    let velocityMagnitude: Float
}

// MARK: - Position caméra dans le repère sphérique du tag

struct CameraPositionInTagFrame {
    let azimuthDeg: Float
    let elevationDeg: Float
    let distanceMm: Float
}

// MARK: - Cible de vue guide

struct GuideViewTarget {
    let viewIndex: Int
    let azimuthDeg: Float
    let elevationDeg: Float
    let distanceMm: Float
}

// MARK: - Qualité du frame

struct FrameQuality {
    let trackingLost: Bool
    let tagVisible: Bool
    let tagPoseGood: Bool
    let isStable: Bool
    let isBlurry: Bool        // Phase 2 : variance Laplacien
    let hasReflection: Bool   // Phase 2 : détection reflets

    var isGoodEnoughForCapture: Bool {
        !trackingLost && tagVisible && tagPoseGood && isStable && !isBlurry
    }
}

// MARK: - État global du scan

struct ScanState {
    var tagDetections: [TagDetection] = []
    var arkitPose: ARKitPose? = nil
    var frameQuality: FrameQuality = FrameQuality(
        trackingLost: false, tagVisible: false, tagPoseGood: false,
        isStable: true, isBlurry: false, hasReflection: false
    )
    var cameraInTagFrame: CameraPositionInTagFrame? = nil
    var nextGuideTarget: GuideViewTarget? = nil
    var capturedCount: Int = 0
    var totalGuideViews: Int = GabaritConfig.numGuideViews
    var guideMessage: String = "Pointez le tag AprilTag"
    var frameSize: CGSize = .zero
}

// MARK: - Intrinsèques caméra

struct CameraIntrinsics {
    var fx: Float
    var fy: Float
    var cx: Float
    var cy: Float
    var distCoeffs: [Float] = Array(repeating: 0, count: 5)

    /// Valeurs approchées iPhone 12 Pro Max (caméra principale, 12 MP)
    /// À remplacer par AVCameraCalibrationData après Phase 1
    static var defaultIPhone12ProMax: CameraIntrinsics {
        CameraIntrinsics(fx: 2870, fy: 2870, cx: 2016, cy: 1512)
    }
}
