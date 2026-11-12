import Foundation
import simd

/// Guide de trajectoire orbitale — même logique que l'Android OrbitGuide.kt
/// 24 vues réparties sur 4 couronnes d'élévation autour du gabarit.
final class OrbitGuide {

    let numViews: Int
    let tagSizeMm: Float
    private(set) var views: [GuideViewTarget] = []

    // Tolérances angulaires pour considérer une vue comme "couverte"
    private let azimuthTolerance: Float  = 18.0
    private let elevationTolerance: Float = 15.0

    init(numViews: Int = GabaritConfig.numGuideViews,
         tagSizeMm: Float = GabaritConfig.tagSizeMm) {
        self.numViews  = numViews
        self.tagSizeMm = tagSizeMm
        self.views = buildViews()
    }

    // MARK: - API publique

    /// Index de la vue guide la plus proche de la position actuelle, dans les tolérances.
    func closestViewIndex(to pos: CameraPositionInTagFrame) -> Int? {
        var bestIdx: Int? = nil
        var bestDist: Float = .greatestFiniteMagnitude

        for view in views {
            let dAz = angularDiff(pos.azimuthDeg, view.azimuthDeg)
            let dEl = abs(pos.elevationDeg - view.elevationDeg)
            guard dAz < azimuthTolerance && dEl < elevationTolerance else { continue }
            let dist = sqrt(dAz*dAz + dEl*dEl)
            if dist < bestDist {
                bestDist = dist
                bestIdx  = view.viewIndex
            }
        }
        return bestIdx
    }

    /// Prochaine vue non capturée la plus proche de la position actuelle.
    func nextTarget(from currentPos: CameraPositionInTagFrame?,
                    captured: Set<Int>) -> GuideViewTarget? {
        let remaining = views.filter { !captured.contains($0.viewIndex) }
        guard !remaining.isEmpty else { return nil }
        guard let pos = currentPos else { return remaining.first }

        return remaining.min { a, b in
            let dAzA = angularDiffPositive(from: pos.azimuthDeg, to: a.azimuthDeg)
            let dElA = abs(pos.elevationDeg - a.elevationDeg)
            let dAzB = angularDiffPositive(from: pos.azimuthDeg, to: b.azimuthDeg)
            let dElB = abs(pos.elevationDeg - b.elevationDeg)
            return (dAzA + dElA * 3) < (dAzB + dElB * 3)
        }
    }

    // MARK: - Construction des vues

    private func buildViews() -> [GuideViewTarget] {
        // (élévation en degrés, nombre de vues sur cette couronne)
        let tiers: [(Float, Int)] = [(10, 8), (40, 8), (70, 6), (85, 2)]
        var result: [GuideViewTarget] = []
        var idx = 0

        for (elevation, count) in tiers {
            for i in 0..<count {
                let azimuth  = Float(360 / count * i)
                let distance = recommendedDistance(elevationDeg: elevation)
                result.append(GuideViewTarget(viewIndex: idx, azimuthDeg: azimuth,
                                              elevationDeg: elevation, distanceMm: distance))
                idx += 1
            }
        }
        return Array(result.prefix(numViews))
    }

    /// Distance recommandée pour que le tag occupe ~15 % de la hauteur image.
    /// Hypothèse : image 3024 px de haut, fx ≈ 2870 (iPhone 12 Pro Max principal).
    private func recommendedDistance(elevationDeg: Float) -> Float {
        let baseDistance = tagSizeMm * 2870 / (3024 * 0.15)  // ≈ 503 mm pour 80 mm
        let cosel = max(cos(elevationDeg * .pi / 180), 0.3)
        return baseDistance / cosel
    }

    // MARK: - Utilitaires

    private func angularDiff(_ a: Float, _ b: Float) -> Float {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return d > 180 ? 360 - d : d
    }

    private func angularDiffPositive(from: Float, to: Float) -> Float {
        var d = (to - from).truncatingRemainder(dividingBy: 360)
        if d < 0 { d += 360 }
        return d
    }
}
