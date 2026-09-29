import SwiftUI

/// The app's mark (Docs/Brand/SpacedHabits-Mark*.svg), drawn as shapes so widgets need no asset catalog: a
/// check whose stroke breaks into spaced dots, the last one accented. Uses the on-dark colors in dark mode.
public struct BrandMark: View {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public var body: some View {
        let dark = colorScheme == .dark
        ZStack {
            BrandMarkShape(part: .ink).fill(Color(hex: dark ? "#F3EFE6" : "#1C2A25"))
            BrandMarkShape(part: .accent).fill(Color(hex: dark ? "#F07A4E" : "#E2683C"))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// One color's worth of the mark, in the SVGs' 96×96 viewBox (origin 4, -4) scaled to fit the rect.
private struct BrandMarkShape: Shape {
    enum Part { case ink, accent }

    let part: Part

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch part {
        case .ink:
            var check = Path()
            check.move(to: CGPoint(x: 18, y: 50))
            check.addLine(to: CGPoint(x: 38, y: 70))
            check.addLine(to: CGPoint(x: 44.96, y: 62.46))
            path.addPath(check.strokedPath(StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round)))
            path.addPath(dot(at: CGPoint(x: 54.8, y: 51.8)))
            path.addPath(dot(at: CGPoint(x: 68.03, y: 37.47)))
        case .accent:
            path.addPath(dot(at: CGPoint(x: 86, y: 18)))
        }
        let scale = min(rect.width, rect.height) / 96
        let transform = CGAffineTransform(translationX: rect.midX - 48 * scale, y: rect.midY - 48 * scale)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -4, y: 4)
        return path.applying(transform)
    }

    private func dot(at center: CGPoint) -> Path {
        Path(ellipseIn: CGRect(x: center.x - 5.5, y: center.y - 5.5, width: 11, height: 11))
    }
}
