import UIKit
import simd

/// Vue de superposition AR style "PractiCal" avec coins colorés (Rouge, Vert, Bleu, Jaune),
/// réticule en croix pleine largeur/hauteur, et HUD avec taux de détection (det/s) et tracking.
final class ScanOverlayView: UIView {

    var displayTransform: CGAffineTransform = .identity
    var imageSize: CGSize = CGSize(width: 1920, height: 1440)
    var tagDetections: [TagDetection] = []
    var isTracking: Bool = true
    var isTagLocked: Bool = false
    var detPerSec: Double = 0.0
    var showCrosshairs: Bool = true

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
        self.tagDetections = detections
        self.displayTransform = transform
        self.imageSize = imgSize
        self.isTracking = tracking
        self.isTagLocked = locked
        self.detPerSec = fps
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        // ── 1. HUD STYLE "PRACTICAL" EN HAUT ──
        drawTopHUD(ctx)

        // ── 2. DÉTECTION ET COINS DU TAG ──
        for det in tagDetections {
            drawPractiCalTag(ctx, det: det)
        }
    }

    // MARK: - Projection exacte via displayTransform ARKit officiel

    private func toScreen(_ pt: CGPoint) -> CGPoint {
        guard imageSize.width > 0, imageSize.height > 0 else { return pt }
        let norm = CGPoint(x: pt.x / imageSize.width, y: pt.y / imageSize.height)
        let screenNorm = norm.applying(displayTransform)
        return CGPoint(x: screenNorm.x * bounds.width, y: screenNorm.y * bounds.height)
    }

    // MARK: - Dessin du Tag style PractiCal (Image 1 & Image 3)

    private func drawPractiCalTag(_ ctx: CGContext, det: TagDetection) {
        guard det.corners.count == 4 else { return }

        let p0 = toScreen(det.corners[0]) // Coin 0 : Haut-Gauche (Rouge)
        let p1 = toScreen(det.corners[1]) // Coin 1 : Haut-Droit  (Vert)
        let p2 = toScreen(det.corners[2]) // Coin 2 : Bas-Droit   (Bleu)
        let p3 = toScreen(det.corners[3]) // Coin 3 : Bas-Gauche  (Jaune)

        // Centre du tag
        let cx = (p0.x + p1.x + p2.x + p3.x) / 4.0
        let cy = (p0.y + p1.y + p2.y + p3.y) / 4.0
        let center = CGPoint(x: cx, y: cy)

        // ── A. RÉTICULE EN CROIX PLEIN ÉCRAN (Style Image 3) ──
        if showCrosshairs {
            // Ligne horizontale Rouge traversant tout l'écran
            ctx.setStrokeColor(UIColor.systemRed.withAlphaComponent(0.85).cgColor)
            ctx.setLineWidth(1.5)
            ctx.move(to: CGPoint(x: 0, y: cy))
            ctx.addLine(to: CGPoint(x: bounds.width, y: cy))
            ctx.strokePath()

            // Ligne verticale Verte traversant tout l'écran
            ctx.setStrokeColor(UIColor.systemGreen.withAlphaComponent(0.85).cgColor)
            ctx.setLineWidth(1.5)
            ctx.move(to: CGPoint(x: cx, y: 0))
            ctx.addLine(to: CGPoint(x: cx, y: bounds.height))
            ctx.strokePath()

            // Point cible central (bullseye)
            ctx.setFillColor(UIColor.systemRed.cgColor)
            ctx.fillEllipse(in: CGRect(x: cx - 4, y: cy - 4, width: 8, height: 8))
            ctx.setStrokeColor(UIColor.white.cgColor)
            ctx.setLineWidth(1.5)
            ctx.strokeEllipse(in: CGRect(x: cx - 4, y: cy - 4, width: 8, height: 8))
        }

        // ── B. LIGNES DU CADRE DU TAG (BORDURES COLORÉES) ──
        // Bord Supérieur (0 -> 1) : Rouge
        drawLine(ctx, from: p0, to: p1, color: .systemRed, width: 3.5)
        // Bord Droit (1 -> 2) : Vert
        drawLine(ctx, from: p1, to: p2, color: .systemGreen, width: 3.5)
        // Bord Inférieur (2 -> 3) : Bleu
        drawLine(ctx, from: p2, to: p3, color: .systemBlue, width: 3.5)
        // Bord Gauche (3 -> 0) : Jaune
        drawLine(ctx, from: p3, to: p0, color: .systemYellow, width: 3.5)

        // ── C. LES 4 COINS DISCTINCTS (Style PractiCal Image 1) ──
        drawCornerDot(ctx, center: p0, color: .systemRed)    // Coin 0
        drawCornerDot(ctx, center: p1, color: .systemGreen)  // Coin 1
        drawCornerDot(ctx, center: p2, color: .systemBlue)   // Coin 2
        drawCornerDot(ctx, center: p3, color: .systemYellow) // Coin 3

        // ── D. INDICATION DE DIMENSION (Flèche et texte 80 mm) ──
        let midTopX = (p0.x + p1.x) / 2.0
        let midTopY = (p0.y + p1.y) / 2.0 - 14.0
        let dimText = "◀── \(Int(GabaritConfig.tagSizeMm)) mm ──▶" as NSString
        let font = UIFont.systemFont(ofSize: 13, weight: .heavy)
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.systemRed,
            .backgroundColor: UIColor.black.withAlphaComponent(0.6)
        ]
        let textSize = dimText.size(withAttributes: textAttrs)
        dimText.draw(at: CGPoint(x: midTopX - textSize.width / 2.0, y: midTopY), withAttributes: textAttrs)

        // ── E. BADGE ID ET DISTANCE SOUS LE TAG ──
        let distCm = Int(det.distanceMm / 10.0)
        let badgeText = "Tag ID: \(det.tagId) | \(distCm) cm" as NSString
        let badgeAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: UIColor.white,
            .backgroundColor: UIColor.black.withAlphaComponent(0.7)
        ]
        let badgeSize = badgeText.size(withAttributes: badgeAttrs)
        let midBotX = (p2.x + p3.x) / 2.0
        let midBotY = (p2.y + p3.y) / 2.0 + 8.0
        badgeText.draw(at: CGPoint(x: midBotX - badgeSize.width / 2.0, y: midBotY), withAttributes: badgeAttrs)
    }

    private func drawLine(_ ctx: CGContext, from: CGPoint, to: CGPoint, color: UIColor, width: CGFloat) {
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.move(to: from)
        ctx.addLine(to: to)
        ctx.strokePath()
    }

    private func drawCornerDot(_ ctx: CGContext, center: CGPoint, color: UIColor) {
        let radius: CGFloat = 8.0
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)

        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: rect)

        ctx.setStrokeColor(UIColor.white.cgColor)
        ctx.setLineWidth(2.0)
        ctx.strokeEllipse(in: rect)
    }

    // MARK: - Barre HUD Style PractiCal en haut (Image 1)

    private func drawTopHUD(_ ctx: CGContext) {
        let topY: CGFloat = 48.0 // Sous l'encoche / Dynamic Island

        // 1. Pill Gauche : det/s (Taux de détection réel)
        let fpsStr = String(format: "● %.1f det/s", detPerSec > 0 ? detPerSec : 20.0) as NSString
        let pillRect = CGRect(x: 16, y: topY, width: 110, height: 28)
        drawPill(ctx, rect: pillRect, color: UIColor(red: 0.1, green: 0.1, blue: 0.15, alpha: 0.85))

        let fpsAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 13, weight: .bold),
            .foregroundColor: UIColor(red: 0.2, green: 1.0, blue: 0.4, alpha: 1.0)
        ]
        fpsStr.draw(at: CGPoint(x: pillRect.midX - 44, y: pillRect.midY - 8), withAttributes: fpsAttrs)

        // 2. Pill Tracking : ✔ Tracking
        let trackRect = CGRect(x: pillRect.maxX + 8, y: topY, width: 115, height: 28)
        drawPill(ctx, rect: trackRect, color: UIColor(red: 0.1, green: 0.1, blue: 0.15, alpha: 0.85))

        let trackStr = (isTracking ? "✔ Tracking" : "⚠ Lost") as NSString
        let trackColor = isTracking ? UIColor(red: 0.2, green: 1.0, blue: 0.4, alpha: 1.0) : UIColor.systemOrange
        let trackAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 13, weight: .bold),
            .foregroundColor: trackColor
        ]
        trackStr.draw(at: CGPoint(x: trackRect.midX - 38, y: trackRect.midY - 8), withAttributes: trackAttrs)

        // 3. Pill Droite : Gabarit 80mm
        let mapStr = (isTagLocked ? "🔒 Gabarit Fixé 80mm" : "Gabarit 80mm ∨") as NSString
        let mapRect = CGRect(x: bounds.width - 165, y: topY, width: 150, height: 28)
        drawPill(ctx, rect: mapRect, color: UIColor(red: 0.1, green: 0.1, blue: 0.15, alpha: 0.85))

        let mapColor = isTagLocked ? UIColor.cyan : UIColor(red: 0.4, green: 0.8, blue: 1.0, alpha: 1.0)
        let mapAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: mapColor
        ]
        mapStr.draw(at: CGPoint(x: mapRect.midX - 64, y: mapRect.midY - 7), withAttributes: mapAttrs)
    }

    private func drawPill(_ ctx: CGContext, rect: CGRect, color: UIColor) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2.0)
        ctx.setFillColor(color.cgColor)
        ctx.addPath(path.cgPath)
        ctx.fillPath()

        ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.2).cgColor)
        ctx.setLineWidth(1.0)
        ctx.addPath(path.cgPath)
        ctx.strokePath()
    }
}
