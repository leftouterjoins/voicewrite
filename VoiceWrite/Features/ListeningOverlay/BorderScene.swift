import SpriteKit

class BorderScene: SKScene {
    // 4 edge trapezoids - meet at 45° mitered corners
    private var topEdge: SKShapeNode!
    private var bottomEdge: SKShapeNode!
    private var leftEdge: SKShapeNode!
    private var rightEdge: SKShapeNode!

    // Audio level - updated from audio callback
    var audioLevel: CGFloat = 0 {
        didSet { targetLevel = audioLevel }
    }

    // Smoothed level for fast tweening
    private var currentLevel: CGFloat = 0
    private var targetLevel: CGFloat = 0
    private var lastUpdateTime: TimeInterval = 0

    private var borderColor: NSColor {
        let useCustom = UserDefaults.standard.bool(forKey: "useCustomColor")
        if useCustom {
            let r = UserDefaults.standard.double(forKey: "customColorRed")
            let g = UserDefaults.standard.double(forKey: "customColorGreen")
            let b = UserDefaults.standard.double(forKey: "customColorBlue")
            return NSColor(red: r, green: g, blue: b, alpha: 0.6)
        }
        // Default: adapt to dark/light mode
        let isDarkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDarkMode
            ? NSColor.white.withAlphaComponent(0.13)
            : NSColor.black.withAlphaComponent(0.13)
    }

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        setupEdges()
    }

    private func setupEdges() {
        topEdge = SKShapeNode()
        bottomEdge = SKShapeNode()
        leftEdge = SKShapeNode()
        rightEdge = SKShapeNode()

        for edge in [topEdge!, bottomEdge!, leftEdge!, rightEdge!] {
            edge.strokeColor = .clear
            edge.lineWidth = 0
            addChild(edge)
        }

        updateEdgePaths(thickness: 3)
    }

    private func updateEdgePaths(thickness: CGFloat) {
        let w = size.width
        let h = size.height
        let t = thickness
        let color = borderColor

        // Top trapezoid
        let topPath = CGMutablePath()
        topPath.move(to: CGPoint(x: 0, y: h))
        topPath.addLine(to: CGPoint(x: w, y: h))
        topPath.addLine(to: CGPoint(x: w - t, y: h - t))
        topPath.addLine(to: CGPoint(x: t, y: h - t))
        topPath.closeSubpath()
        topEdge.path = topPath
        topEdge.fillColor = color

        // Bottom trapezoid
        let bottomPath = CGMutablePath()
        bottomPath.move(to: CGPoint(x: 0, y: 0))
        bottomPath.addLine(to: CGPoint(x: w, y: 0))
        bottomPath.addLine(to: CGPoint(x: w - t, y: t))
        bottomPath.addLine(to: CGPoint(x: t, y: t))
        bottomPath.closeSubpath()
        bottomEdge.path = bottomPath
        bottomEdge.fillColor = color

        // Left trapezoid
        let leftPath = CGMutablePath()
        leftPath.move(to: CGPoint(x: 0, y: 0))
        leftPath.addLine(to: CGPoint(x: 0, y: h))
        leftPath.addLine(to: CGPoint(x: t, y: h - t))
        leftPath.addLine(to: CGPoint(x: t, y: t))
        leftPath.closeSubpath()
        leftEdge.path = leftPath
        leftEdge.fillColor = color

        // Right trapezoid
        let rightPath = CGMutablePath()
        rightPath.move(to: CGPoint(x: w, y: 0))
        rightPath.addLine(to: CGPoint(x: w, y: h))
        rightPath.addLine(to: CGPoint(x: w - t, y: h - t))
        rightPath.addLine(to: CGPoint(x: w - t, y: t))
        rightPath.closeSubpath()
        rightEdge.path = rightPath
        rightEdge.fillColor = color
    }

    // Called every frame (60/120fps)
    override func update(_ currentTime: TimeInterval) {
        // Frame-rate independent tweening
        let deltaTime = lastUpdateTime == 0 ? 0.008 : currentTime - lastUpdateTime
        lastUpdateTime = currentTime

        // Fast tween: ~30ms to reach target (snappy but smooth)
        let speed: CGFloat = 25.0
        currentLevel += (targetLevel - currentLevel) * min(1.0, speed * deltaTime)

        // Map level to thickness: 3px to 100px
        let minThickness: CGFloat = 3
        let maxThickness: CGFloat = 100
        let thickness = minThickness + currentLevel * (maxThickness - minThickness)

        updateEdgePaths(thickness: thickness)
    }
}
