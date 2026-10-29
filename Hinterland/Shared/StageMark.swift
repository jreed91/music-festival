import SwiftUI

/// Each stage's shape. Colour alone can't carry the stage — not for colour-blind eyes,
/// and not on the Lock Screen, where the system draws widgets in one colour — so every
/// stage also has a shape: Main is the radio tower's triangle, Miniland a firefly's dot,
/// Campfire a diamond, anything else a square.
struct StageShape: Shape {
    let stage: Stage

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch stage {
        case .main:
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        case .miniland:
            path.addEllipse(in: rect)
        case .campfire:
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.closeSubpath()
        case .other:
            path.addRect(rect)
        }
        return path
    }
}

/// The stage's shape in its colour, sized to sit beside a line of text.
struct StageGlyph: View {
    let stage: Stage
    var size: CGFloat = 10

    var body: some View {
        StageShape(stage: stage)
            .fill(stage.color)
            .frame(width: size, height: size)
    }
}
