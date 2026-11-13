import UIKit
import simd

/// Vue de superposition Core Graphics avec projection correcte en orientation portrait
final class ScanOverlayView: UIView {

    private var state: ScanState?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(state: ScanState) {
        self.state = state
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(),
              let s = state else { return }

        // 1. Coins et axes de chaque tag détecté
        for det in s.tagDetections {
            drawCorners(ctx, det: det, state: s)
            drawAxes(ctx, det: det, state: s)
        }

        // 2. Flèche directionnelle
        if let next = s.nextGuideTarget, let cur = s.cameraInTagFrame {
            drawArrow(ctx, currentAz: cur.azimuthDeg, targetAz: next.azimuthDeg,
                      currentEl: cur.elevationDeg,  targetEl: next.elevationDeg)
        }
    }

    // MARK: - Transformation Coordonnées Caméra (Paysage capteur) -> Écran (Portrait)

    private func cameraPointToScreen(_ pt: CGPoint, state: ScanState) -> CGPoint {
        let fw = max(state.frameSize.width, 1)
        let fh = max(state.frameSize.height, 1)

        // En mode portrait, le capteur iOS est orienté avec fw en hauteur et fh en largeur
        let scale = max(bounds.width / fh, bounds.height / fw)
        let displayW = fh * scale
        let displayH = fw * scale
        let offsetX = (bounds.width - displayW) / 2.0
        let offsetY = (bounds.height - displayH) / 2.0

        // Rotation 90° dans le sens horaire : (x, y) capteur -> (y, fw - x) ou (fh - y, x)
        let screenX = (pt.y) * scale + offsetX
        let screenY = (pt.x) * scale + offsetY

        return CGPoint(x: screenX, y: screenY)
    }

    // MARK: - Coins

    private func drawCorners(_ ctx: CGContext, det: TagDetection, state: ScanState) {
        ctx.setStrokeColor(UIColor.yellow.cgColor)
        ctx.setLineWidth(3.5)

        let pts = det.corners.map { cameraPointToScreen($0, state: state) }
        guard pts.count == 4 else { return }

        ctx.move(to: pts[0])
        for i in 1..<4 {
            ctx.addLine(to: pts[i])
        }
        ctx.closePath()
        ctx.strokePath()

        // ID du tag au centre
        let cx = pts.map(\.x).reduce(0, +) / 4
        let cy = pts.map(\.y).reduce(0, +) / 4
        let label = "ID:\(det.tagId)" as NSString
        label.draw(at: CGPoint(x: cx - 18, y: cy - 9),
                   withAttributes: [
                    .foregroundColor: UIColor.yellow,
                    .font: UIFont.boldSystemFont(ofSize: 15),
                    .backgroundColor: UIColor.black.withAlphaComponent(0.4)
                   ])
    }

    // MARK: - Axes 3D projetés

    private func drawAxes(_ ctx: CGContext, det: TagDetection, state: ScanState) {
        let axisLen: Float = Float(GabaritConfig.tagSizeMm) * 0.4
        let pts3D: [(Float,Float,Float)] = [(0,0,0), (axisLen,0,0), (0,axisLen,0), (0,0,axisLen)]
        let R = rodriguesMatrix(det.rvec)
        let t = det.tvec

        let center = det.corners.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x/4, y: $0.y + $1.y/4) }
        let centerScreen = cameraPointToScreen(center, state: state)

        // Projection simplifiée pour visualisation
        let projected = pts3D.map { p -> CGPoint in
            let rx = R[0]*p.0 + R[1]*p.1 + R[2]*p.2 + t.x
            let ry = R[3]*p.0 + R[4]*p.1 + R[5]*p.2 + t.y
            let rz = max(R[6]*p.0 + R[7]*p.1 + R[8]*p.2 + t.z, 1)

            let px = CGFloat(2870.0 * rx / rz)
            let py = CGFloat(2870.0 * ry / rz)
            // Décalage relatif à l'écran
            return CGPoint(x: centerScreen.x + py * 0.15, y: centerScreen.y + px * 0.15)
        }

        let colors: [UIColor] = [.red, .green, .cyan]
        let labels = ["X", "Y", "Z"]

        for i in 1...3 {
            ctx.setStrokeColor(colors[i-1].cgColor)
            ctx.setLineWidth(4.0)
            ctx.move(to: centerScreen)
            ctx.addLine(to: projected[i])
            ctx.strokePath()

            (labels[i-1] as NSString).draw(
                at: CGPoint(x: projected[i].x + 4, y: projected[i].y - 8),
                withAttributes: [.foregroundColor: colors[i-1],
                                 .font: UIFont.boldSystemFont(ofSize: 14)])
        }
    }

    // MARK: - Flèche directionnelle

    private func drawArrow(_ ctx: CGContext,
                           currentAz: Float, targetAz: Float,
                           currentEl: Float, targetEl: Float) {
        var dAz = targetAz - currentAz
        while dAz >  180 { dAz -= 360 }
        while dAz < -180 { dAz += 360 }
        let dEl = targetEl - currentEl

        guard abs(dAz) > 10 || abs(dEl) > 8 else { return }

        let angle = CGFloat(atan2f(-dEl, dAz))
        let radius = bounds.width * 0.38
        let cx = bounds.midX
        let cy = bounds.midY

        let startX = cx + cos(angle) * (radius - 50)
        let startY = cy + sin(angle) * (radius - 50)
        let endX   = cx + cos(angle) * (radius + 20)
        let endY   = cy + sin(angle) * (radius + 20)

        ctx.setStrokeColor(UIColor(red: 1.0, green: 0.45, blue: 0.0, alpha: 0.95).cgColor)
        ctx.setLineWidth(8)
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: startX, y: startY))
        ctx.addLine(to: CGPoint(x: endX, y: endY))
        ctx.strokePath()

        // Tête de flèche
        let headSize: CGFloat = 22
        let a1 = angle + 2.4
        let a2 = angle - 2.4
        ctx.setFillColor(UIColor(red: 1.0, green: 0.45, blue: 0.0, alpha: 0.95).cgColor)
        ctx.move(to: CGPoint(x: endX, y: endY))
        ctx.addLine(to: CGPoint(x: endX + cos(a1)*headSize, y: endY + sin(a1)*headSize))
        ctx.addLine(to: CGPoint(x: endX + cos(a2)*headSize, y: endY + sin(a2)*headSize))
        ctx.closePath()
        ctx.fillPath()
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
