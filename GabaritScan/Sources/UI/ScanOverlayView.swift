import UIKit
import simd

// MARK: - Polycam-style minimal overlay
// - Thin teal rectangle around detected AprilTag
// - Faint bounding volume hint when locked
// - No colored corners, no crosshairs, no PractiCal HUD

final class ScanOverlayView: UIView {

    // Public state
    var displayTransform: CGAffineTransform = .identity
    var imageSize: CGSize = CGSize(width: 1920, height: 1440)
    var tagDetections: [TagDetection] = []
    var isTracking: Bool = true
    var isTagLocked: Bool = false
    var detPerSec: Double = 0.0

    // Polycam color palette
    private let tealColor = UIColor(red: 0.0, green: 0.898, blue: 0.816, alpha: 1.0)
    private let tealFaint  = UIColor(red: 0.0, green: 0.898, blue: 0.816, alpha: 0.25)

    // Legacy compatibility — kept but ignored in drawing
    var showCrosshairs: Bool = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(
        detections: [TagDetection],
        transform: CGAffineTransform,
        imgSize: CGSize,
        tracking: Bool,
        locked: Bool,
        fps: Double
    ) {
        self.tagDetections    = detections
        self.displayTransform = transform
        self.imageSize        = imgSize
        self.isTracking       = tracking
        self.isTagLocked      = locked
        self.detPerSec        = fps
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        for det in tagDetections {
            drawPolycamTagOutline(ctx, det: det)
        }

        // If locked and no current detection, draw a subtle capture-zone hint
        if isTagLocked && tagDetections.isEmpty {
            drawLockedZoneHint(ctx)
        }
    }

    // MARK: - Coordinate projection (ARKit displayTransform)

    private func toScreen(_ pt: CGPoint) -> CGPoint {
        guard imageSize.width > 0, imageSize.height > 0 else { return pt }
        let norm = CGPoint(x: pt.x / imageSize.width, y: pt.y / imageSize.height)
        let screenNorm = norm.applying(displayTransform)
        return CGPoint(x: screenNorm.x * bounds.width, y: screenNorm.y * bounds.height)
    }

    // MARK: - Polycam thin teal rectangle outline

    private func drawPolycamTagOutline(_ ctx: CGContext, det: TagDetection) {
        guard det.corners.count == 4 else { return }

        let pts = det.corners.map { toScreen($0) }

        // Thin teal rectangle — 1.5pt, no corner dots, no crosshairs
        ctx.setStrokeColor(tealColor.cgColor)
        ctx.setLineWidth(1.5)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        ctx.move(to: pts[0])
        ctx.addLine(to: pts[1])
        ctx.addLine(to: pts[2])
        ctx.addLine(to: pts[3])
        ctx.closePath()
        ctx.strokePath()

        // Small "◎ Repère" label above the tag
        let cx = pts.map(\.x).reduce(0, +) / 4.0
        let cy = pts.map(\.y).reduce(0, +) / 4.0 - 22.0

        let label = (isTagLocked ? "🔒 Repère fixé" : "◎ Repère") as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: tealColor
        ]
        let sz = label.size(withAttributes: attrs)
        label.draw(at: CGPoint(x: cx - sz.width / 2.0, y: cy - sz.height / 2.0), withAttributes: attrs)
    }

    // MARK: - Faint bounding volume when tag is locked but off-screen

    private func drawLockedZoneHint(_ ctx: CGContext) {
        // Draw a subtle rounded rectangle in the center to suggest the capture zone
        let w: CGFloat = bounds.width * 0.55
        let h: CGFloat = bounds.height * 0.45
        let originX = bounds.midX - w / 2.0
        let originY = bounds.midY - h / 2.0
        let rect = CGRect(x: originX, y: originY, width: w, height: h)

        let path = UIBezierPath(roundedRect: rect, cornerRadius: 12)
        ctx.setStrokeColor(tealFaint.cgColor)
        ctx.setLineWidth(1.5)
        ctx.setLineDash(phase: 0, lengths: [8, 5])
        ctx.addPath(path.cgPath)
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])
    }
}
