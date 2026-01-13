import CoreGraphics
import Foundation

/// Generates masks for Tahoe window corners using Apple's continuous curvature approach.
/// Based on reverse-engineered constants from iOS UIBezierPath(roundedRect:cornerRadius:).
/// See: https://www.paintcodeapp.com/news/code-for-ios-7-rounded-rectangles
struct ContinuousCurve {

    // MARK: - Tahoe Bezier Constants (measured from actual windows)
    // These define control points relative to corner radius.
    // Measured: curve extends ~1.29x radius along each edge (not 1.528 like iOS 7)

    private static let ext: CGFloat = 1.29    // Curve extent along edge (measured from Finder)

    // First bezier: edge -> diagonal entry
    private static let b1cp1: CGFloat = 1.08849323  // Control point 1
    private static let b1cp2: CGFloat = 0.86840689  // Control point 2
    private static let b1end: CGFloat = 0.66993427  // End point (along edge)
    private static let b1endPerp: CGFloat = 0.06549600  // End point (perpendicular)

    // Transition line
    private static let line: CGFloat = 0.63149399
    private static let linePerp: CGFloat = 0.07491100

    // Second bezier: diagonal through corner
    private static let b2cp1: CGFloat = 0.37282392
    private static let b2cp1Perp: CGFloat = 0.16906013
    private static let b2cp2: CGFloat = 0.16906013
    private static let b2cp2Perp: CGFloat = 0.37282392
    private static let b2end: CGFloat = 0.07491100
    private static let b2endPerp: CGFloat = 0.63149399

    // Third bezier: corner -> exit edge
    private static let b3cp1Perp: CGFloat = 0.86840689
    private static let b3cp2Perp: CGFloat = 1.08849323
    // b3end is (0, ext) along exit edge

    /// Creates an inverse mask - covers everything OUTSIDE the content safe zone.
    /// Uses screen coordinates (origin at top-left, Y increases downward).
    static func inverseMask(
        size: CGSize,
        menuBarHeight: CGFloat,
        cornerRadius: CGFloat
    ) -> CGPath {
        let path = CGMutablePath()
        path.addRect(CGRect(origin: .zero, size: size))
        path.addPath(contentAreaPath(
            size: size,
            menuBarHeight: menuBarHeight,
            cornerRadius: cornerRadius
        ))
        return path
    }

    /// Creates an inverse mask for CGContext coordinates (origin at bottom-left, Y increases upward).
    /// Builds the mask directly: menubar strip at top + four curved corners.
    static func inverseMaskFlipped(
        size: CGSize,
        menuBarHeight: CGFloat,
        cornerRadius: CGFloat
    ) -> CGPath {
        let path = CGMutablePath()

        // In CGContext: y=0 is bottom, y=height is top
        // Menubar is at TOP of screen, so in CGContext it's at y=(height-menuBarHeight) to y=height
        let menubarY = size.height - menuBarHeight

        // 1. Menubar strip (full width at top)
        path.addRect(CGRect(x: 0, y: menubarY, width: size.width, height: menuBarHeight))

        // 2. Four corner regions with continuous curvature
        let maxRadius = min(size.width, size.height - menuBarHeight) / 2 / ext
        let r = min(cornerRadius, maxRadius)

        // Top-left corner (at x=0, y=menubarY)
        path.addPath(cornerPathCG(corner: .topLeft, x: 0, y: menubarY, radius: r))
        // Top-right corner (at x=width, y=menubarY)
        path.addPath(cornerPathCG(corner: .topRight, x: size.width, y: menubarY, radius: r))
        // Bottom-left corner (at x=0, y=0)
        path.addPath(cornerPathCG(corner: .bottomLeft, x: 0, y: 0, radius: r))
        // Bottom-right corner (at x=width, y=0)
        path.addPath(cornerPathCG(corner: .bottomRight, x: size.width, y: 0, radius: r))

        return path
    }

    private enum CornerCG { case topLeft, topRight, bottomLeft, bottomRight }

    /// Create a corner path in CGContext coordinates
    private static func cornerPathCG(corner: CornerCG, x: CGFloat, y: CGFloat, radius r: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let e = r * ext

        switch corner {
        case .topLeft:
            // Triangle from corner (0,y) along top edge to (e,y), curves down to (0,y-e), back to corner
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: e, y: y))
            // Bezier 1
            path.addCurve(
                to: CGPoint(x: b1end * r, y: y - b1endPerp * r),
                control1: CGPoint(x: b1cp1 * r, y: y),
                control2: CGPoint(x: b1cp2 * r, y: y)
            )
            path.addLine(to: CGPoint(x: line * r, y: y - linePerp * r))
            // Bezier 2
            path.addCurve(
                to: CGPoint(x: b2end * r, y: y - b2endPerp * r),
                control1: CGPoint(x: b2cp1 * r, y: y - b2cp1Perp * r),
                control2: CGPoint(x: b2cp2 * r, y: y - b2cp2Perp * r)
            )
            // Bezier 3
            path.addCurve(
                to: CGPoint(x: 0, y: y - e),
                control1: CGPoint(x: 0, y: y - b3cp1Perp * r),
                control2: CGPoint(x: 0, y: y - b3cp2Perp * r)
            )
            path.closeSubpath()

        case .topRight:
            path.move(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x - e, y: y))
            path.addCurve(
                to: CGPoint(x: x - b1end * r, y: y - b1endPerp * r),
                control1: CGPoint(x: x - b1cp1 * r, y: y),
                control2: CGPoint(x: x - b1cp2 * r, y: y)
            )
            path.addLine(to: CGPoint(x: x - line * r, y: y - linePerp * r))
            path.addCurve(
                to: CGPoint(x: x - b2end * r, y: y - b2endPerp * r),
                control1: CGPoint(x: x - b2cp1 * r, y: y - b2cp1Perp * r),
                control2: CGPoint(x: x - b2cp2 * r, y: y - b2cp2Perp * r)
            )
            path.addCurve(
                to: CGPoint(x: x, y: y - e),
                control1: CGPoint(x: x, y: y - b3cp1Perp * r),
                control2: CGPoint(x: x, y: y - b3cp2Perp * r)
            )
            path.closeSubpath()

        case .bottomLeft:
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 0, y: e))
            path.addCurve(
                to: CGPoint(x: b1endPerp * r, y: b1end * r),
                control1: CGPoint(x: 0, y: b1cp1 * r),
                control2: CGPoint(x: 0, y: b1cp2 * r)
            )
            path.addLine(to: CGPoint(x: linePerp * r, y: line * r))
            path.addCurve(
                to: CGPoint(x: b2endPerp * r, y: b2end * r),
                control1: CGPoint(x: b2cp1Perp * r, y: b2cp1 * r),
                control2: CGPoint(x: b2cp2Perp * r, y: b2cp2 * r)
            )
            path.addCurve(
                to: CGPoint(x: e, y: 0),
                control1: CGPoint(x: b3cp1Perp * r, y: 0),
                control2: CGPoint(x: b3cp2Perp * r, y: 0)
            )
            path.closeSubpath()

        case .bottomRight:
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: e))
            path.addCurve(
                to: CGPoint(x: x - b1endPerp * r, y: b1end * r),
                control1: CGPoint(x: x, y: b1cp1 * r),
                control2: CGPoint(x: x, y: b1cp2 * r)
            )
            path.addLine(to: CGPoint(x: x - linePerp * r, y: line * r))
            path.addCurve(
                to: CGPoint(x: x - b2endPerp * r, y: b2end * r),
                control1: CGPoint(x: x - b2cp1Perp * r, y: b2cp1 * r),
                control2: CGPoint(x: x - b2cp2Perp * r, y: b2cp2 * r)
            )
            path.addCurve(
                to: CGPoint(x: x - e, y: 0),
                control1: CGPoint(x: x - b3cp1Perp * r, y: 0),
                control2: CGPoint(x: x - b3cp2Perp * r, y: 0)
            )
            path.closeSubpath()
        }

        return path
    }

    /// Creates the rounded rectangle content area path (screen coordinates, origin top-left).
    private static func contentAreaPath(
        size: CGSize,
        menuBarHeight: CGFloat,
        cornerRadius: CGFloat
    ) -> CGPath {
        let path = CGMutablePath()

        let rect = CGRect(
            x: 0,
            y: menuBarHeight,
            width: size.width,
            height: size.height - menuBarHeight
        )

        // Clamp radius to fit within bounds
        let maxRadius = min(rect.width, rect.height) / 2 / ext
        let r = min(cornerRadius, maxRadius)
        let e = r * ext  // How far curve extends along each edge

        // Start at top-left, after the corner curve
        path.move(to: CGPoint(x: rect.minX + e, y: rect.minY))

        // Top edge -> top-right corner
        path.addLine(to: CGPoint(x: rect.maxX - e, y: rect.minY))
        addCorner(to: path, at: rect.maxX, rect.minY, radius: r, rotation: .topRight)

        // Right edge -> bottom-right corner
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - e))
        addCorner(to: path, at: rect.maxX, rect.maxY, radius: r, rotation: .bottomRight)

        // Bottom edge -> bottom-left corner
        path.addLine(to: CGPoint(x: rect.minX + e, y: rect.maxY))
        addCorner(to: path, at: rect.minX, rect.maxY, radius: r, rotation: .bottomLeft)

        // Left edge -> top-left corner
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + e))
        addCorner(to: path, at: rect.minX, rect.minY, radius: r, rotation: .topLeft)

        path.closeSubpath()
        return path
    }

    private enum Rotation { case topRight, bottomRight, bottomLeft, topLeft }

    /// Add a continuous corner following Apple's exact bezier pattern
    private static func addCorner(
        to path: CGMutablePath,
        at cx: CGFloat, _ cy: CGFloat,
        radius r: CGFloat,
        rotation: Rotation
    ) {
        // Transform coordinates based on which corner we're at
        // This allows us to define the corner path once and rotate it
        let (sx, sy, swap) = transform(for: rotation)

        func pt(_ along: CGFloat, _ perp: CGFloat) -> CGPoint {
            let a = along * r
            let p = perp * r
            if swap {
                return CGPoint(x: cx + sy * p, y: cy + sx * a)
            } else {
                return CGPoint(x: cx + sx * a, y: cy + sy * p)
            }
        }

        // Bezier 1: From edge toward diagonal
        path.addCurve(
            to: pt(b1end, b1endPerp),
            control1: pt(b1cp1, 0),
            control2: pt(b1cp2, 0)
        )

        // Short transition line
        path.addLine(to: pt(line, linePerp))

        // Bezier 2: Diagonal through the corner
        path.addCurve(
            to: pt(b2end, b2endPerp),
            control1: pt(b2cp1, b2cp1Perp),
            control2: pt(b2cp2, b2cp2Perp)
        )

        // Bezier 3: From corner to exit edge
        path.addCurve(
            to: pt(0, ext),
            control1: pt(0, b3cp1Perp),
            control2: pt(0, b3cp2Perp)
        )
    }

    /// Returns (signX, signY, swapAxes) for transforming corner coordinates
    private static func transform(for rotation: Rotation) -> (CGFloat, CGFloat, Bool) {
        switch rotation {
        case .topRight:    return (-1, 1, false)   // -x, +y, no swap (coming from left, going down)
        case .bottomRight: return (-1, -1, true)   // swap axes for 90° rotation
        case .bottomLeft:  return (1, -1, false)   // +x, -y
        case .topLeft:     return (1, 1, true)     // swap axes
        }
    }
}
