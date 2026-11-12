import UIKit
import simd

/// Vue de superposition — équivalent iOS de ScanOverlayView.kt
/// Dessin Core Graphics :
///   - Axes 3D AprilTag (X=rouge, Y=vert, Z=bleu)
///   - Contour des coins du tag
///   - Flèche directionnelle vers la vue suivante
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

    // MARK: - Draw

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(),
              let s = state else { return }

        let scaleX = bounds.width  / max(s.frameSize.width,  1)
        let scaleY = bounds.height / max(s.frameSize.height, 1)

        // 1. Coins et axes de chaque tag détecté
        for det in s.tagDetections {
            drawCorners(ctx, det: det, sx: scaleX, sy: scaleY)
            drawAxes(ctx, det: det, sx: scaleX, sy: scaleY, state: s)
        }

        // 2. Flèche directionnelle
        if let next = s.nextGuideTarget, let cur = s.cameraInTagFrame {
            drawArrow(ctx, currentAz: cur.azimuthDeg, targetAz: next.azimuthDeg,
                      currentEl: cur.elevationDeg,  targetEl: next.elevationDeg)
        }
    }

    // MARK: - Coins

    private func drawCorners(_ ctx: CGContext, det: TagDetection,
                             sx: CGFloat, sy: CGFloat) {
        ctx.setStrokeColor(UIColor.yellow.cgColor)
        ctx.setLineWidth(3)
        let pts = det.corners.map { CGPoint(x: $0.x * sx, y: $0.y * sy) }
        for i in 0..<4 {
            ctx.move(to: pts[i])
            ctx.addLine(to: pts[(i+1)%4])
        }
        ctx.strokePath()

        // ID du tag
        let cx = pts.map(\.x).reduce(0,+) / 4
        let cy = pts.map(\.y).reduce(0,+) / 4
        let label = "ID:\(det.tagId)" as NSString
        label.draw(at: CGPoint(x: cx - 20, y: cy),
                   withAttributes: [.foregroundColor: UIColor.yellow,
                                    .font: UIFont.boldSystemFont(ofSize: 14)])
    }

    // MARK: - Axes 3D projetés

    private func drawAxes(_ ctx: CGContext, det: TagDetection,
                          sx: CGFloat, sy: CGFloat, state: ScanState) {
        let axisLen: Float = Float(GabaritConfig.tagSizeMm) / 2

        let pts3D: [(Float,Float,Float)] = [(0,0,0),(axisLen,0,0),(0,axisLen,0),(0,0,axisLen)]
        let R = rodriguesMatrix(det.rvec)
        let t = det.tvec

        let projected = pts3D.map { p -> CGPoint in
            let rx = R[0]*p.0 + R[1]*p.1 + R[2]*p.2 + t.x
            let ry = R[3]*p.0 + R[4]*p.1 + R[5]*p.2 + t.y
            let rz = max(R[6]*p.0 + R[7]*p.1 + R[8]*p.2 + t.z, 1)
            let fx: Float = 2870 * Float(sx) / Float(max(state.frameSize.width, 1))
            let fy: Float = 2870 * Float(sy) / Float(max(state.frameSize.height, 1))
            let u = CGFloat(fx * rx/rz) + bounds.width/2
            let v = CGFloat(fy * ry/rz) + bounds.height/2
            return CGPoint(x: u, y: v)
        }

        let colors: [UIColor] = [.red, .green, .blue]
        let labels  = ["X","Y","Z"]
        for i in 1...3 {
            ctx.setStrokeColor(colors[i-1].cgColor)
            ctx.setLineWidth(5)
            ctx.move(to: projected[0])
            ctx.addLine(to: projected[i])
            ctx.strokePath()
            (labels[i-1] as NSString).draw(
                at: CGPoint(x: projected[i].x + 6, y: projected[i].y),
                withAttributes: [.foregroundColor: colors[i-1],
                                 .font: UIFont.boldSystemFont(ofSize: 13)])
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

        let angle  = CGFloat(atan2f(-dEl, dAz))
        let radius = bounds.width * 0.38
        let cx     = bounds.midX
        let cy     = bounds.midY

        let startX = cx + cos(angle) * radius * 0.7
        let startY = cy + sin(angle) * radius * 0.7
        let endX   = cx + cos(angle) * (radius + 70)
        let endY   = cy + sin(angle) * (radius + 70)

        ctx.setStrokeColor(UIColor(red: 1, green: 0.4, blue: 0, alpha: 0.9).cgColor)
        ctx.setLineWidth(8)
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: startX, y: startY))
        ctx.addLine(to: CGPoint(x: endX, y: endY))
        ctx.strokePath()

        // Tête de flèche
        let headSize: CGFloat = 24
        let a1 = angle + 2.5
        let a2 = angle - 2.5
        ctx.setFillColor(UIColor(red: 1, green: 0.4, blue: 0, alpha: 0.9).cgColor)
        ctx.move(to: CGPoint(x: endX, y: endY))
        ctx.addLine(to: CGPoint(x: endX + cos(a1)*headSize, y: endY + sin(a1)*headSize))
        ctx.addLine(to: CGPoint(x: endX + cos(a2)*headSize, y: endY + sin(a2)*headSize))
        ctx.closePath()
        ctx.fillPath()
    }

    // MARK: - Rodrigues → Matrice 3×3

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
