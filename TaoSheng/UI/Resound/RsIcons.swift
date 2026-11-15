import SwiftUI

// MARK: - 原版图标（SkillVisuals.kt）：圆角方块底 + 自绘线条

enum RsIconTint {
    static let light: [String: Color] = [
        "meeting": Color(hex: "DCE6F2"),
        "sunset": Color(hex: "FCE3CF"),
        "calendar_week": Color(hex: "E6E1F3"),
        "review": Color(hex: "F8DCD3"),
        "timeline": Color(hex: "EDE5D6"),
        "mic": Color(hex: "F7E6BF"),
        "heart": Color(hex: "F6D9E1"),
        "bulb": Color(hex: "D7EEE4"),
        "chat": Color(hex: "E2ECD8"),
        "star": Color(hex: "FBE9C6"),
        "people": Color(hex: "F6D9E1"),
        "device": Color(hex: "DCE6F2"),
        "wave": Color(hex: "E2ECD8"),
        "pin": Color(hex: "FCE3CF"),
        "sparkle": Color(hex: "E6E1F3"),
        "grid": Color(hex: "EDE5D6"),
        "send": Color(hex: "D7EEE4"),
        "cloud": Color(hex: "DCE6F2"),
        "sun": Color(hex: "FBE9C6"),
        "info": Color(hex: "EDE5D6"),
        "lines": Color(hex: "F8DCD3"),
    ]

    static let ink: [String: Color] = [
        "meeting": Color(hex: "4F6E92"),
        "sunset": Color(hex: "E0782E"),
        "calendar_week": Color(hex: "6E5FA6"),
        "review": Color(hex: "C8624A"),
        "timeline": Color(hex: "8C7652"),
        "mic": Color(hex: "B98A1C"),
        "heart": Color(hex: "C25A78"),
        "bulb": Color(hex: "3F8F6F"),
        "chat": Color(hex: "66864A"),
        "star": Color(hex: "D08A16"),
        "people": Color(hex: "C25A78"),
        "device": Color(hex: "4F6E92"),
        "wave": Color(hex: "66864A"),
        "pin": Color(hex: "E0782E"),
        "sparkle": Color(hex: "6E5FA6"),
        "grid": Color(hex: "8C7652"),
        "send": Color(hex: "3F8F6F"),
        "cloud": Color(hex: "4F6E92"),
        "sun": Color(hex: "D08A16"),
        "info": Color(hex: "8C7652"),
        "lines": Color(hex: "C8624A"),
    ]

    static func bg(_ icon: String) -> Color { light[icon] ?? light["star"]! }
    static func fg(_ icon: String) -> Color { ink[icon] ?? ink["star"]! }
}

/// 技能/设置图标：圆角方块底（半径 30%），中间是 50% 尺寸的线条画
struct RsSkillIcon: View {
    let icon: String
    var size: CGFloat = 44

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(RsIconTint.bg(icon))
            .frame(width: size, height: size)
            .overlay(
                RsGlyph(icon: icon, ink: RsIconTint.fg(icon))
                    .frame(width: size * 0.5, height: size * 0.5)
            )
    }
}

/// 只要线条（不带底色），给设置页顶部状态徽章之类用
struct RsGlyphBadge: View {
    let icon: String
    var color: Color
    var size: CGFloat = 28

    var body: some View {
        Circle()
            .fill(color.opacity(0.16))
            .frame(width: size, height: size)
            .overlay(RsGlyph(icon: icon, ink: color).frame(width: size * 0.54, height: size * 0.54))
    }
}

struct RsGlyph: View {
    let icon: String
    let ink: Color

    var body: some View {
        Canvas { ctx, size in
            draw(ctx: &ctx, size: size)
        }
    }

    private func draw(ctx: inout GraphicsContext, size s: CGSize) {
        let W = s.width, H = s.height
        let w = min(W, H) * 0.1
        let style = StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round)

        func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) {
            var p = Path()
            p.move(to: CGPoint(x: W * x1, y: H * y1))
            p.addLine(to: CGPoint(x: W * x2, y: H * y2))
            ctx.stroke(p, with: .color(ink), style: style)
        }
        func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) {
            ctx.stroke(Path(ellipseIn: CGRect(x: W * cx - W * r, y: H * cy - H * r,
                                              width: W * r * 2, height: H * r * 2)),
                       with: .color(ink), lineWidth: w)
        }
        func rect(_ x: CGFloat, _ y: CGFloat, _ rw: CGFloat, _ rh: CGFloat, _ radius: CGFloat) {
            let r = CGRect(x: W * x, y: H * y, width: W * rw, height: H * rh)
            ctx.stroke(Path(roundedRect: r, cornerRadius: W * radius), with: .color(ink), lineWidth: w)
        }
        func arc(_ cx: CGFloat, _ cy: CGFloat, _ rw: CGFloat, _ rh: CGFloat, _ start: Double, _ end: Double) {
            var p = Path()
            p.addArc(center: CGPoint(x: W * cx + W * rw / 2, y: H * cy + H * rh / 2),
                     radius: min(W * rw, H * rh) / 2,
                     startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
            ctx.stroke(p, with: .color(ink), style: style)
        }

        switch icon {
        case "meeting":
            circle(0.34, 0.3, 0.16)
            circle(0.72, 0.36, 0.13)
            arc(0.06, 0.58, 0.56, 0.6, 180, 360)
            arc(0.52, 0.62, 0.42, 0.5, 200, 340)
        case "bulb":
            arc(0.18, 0.04, 0.64, 0.64, 140, 40)
            line(0.36, 0.64, 0.36, 0.76)
            line(0.64, 0.64, 0.64, 0.76)
            line(0.36, 0.78, 0.64, 0.78)
            line(0.42, 0.94, 0.58, 0.94)
        case "chat":
            rect(0.06, 0.1, 0.88, 0.62, 0.2)
            line(0.3, 0.72, 0.22, 0.92)
            line(0.22, 0.92, 0.5, 0.72)
        case "mic":
            rect(0.34, 0.04, 0.32, 0.54, 0.16)
            arc(0.18, 0.3, 0.64, 0.46, 0, 180)
            line(0.5, 0.76, 0.5, 0.94)
        case "calendar_week":
            // 原版 calendar_week：圆角外框 + 顶部两道挂扣 + 内部两行小格
            rect(0.06, 0.14, 0.88, 0.8, 0.18)
            line(0.06, 0.36, 0.94, 0.36)
            line(0.3, 0.06, 0.3, 0.2)
            line(0.7, 0.06, 0.7, 0.2)
            for x in [0.28, 0.5, 0.72] {
                for y in [0.5, 0.68] {
                    ctx.fill(Path(ellipseIn: CGRect(x: W * x - w * 0.8, y: H * y - w * 0.8,
                                                    width: w * 1.6, height: w * 1.6)), with: .color(ink))
                }
            }
        case "review":
            rect(0.12, 0.1, 0.76, 0.8, 0.16)
            line(0.3, 0.36, 0.7, 0.36)
            line(0.3, 0.54, 0.7, 0.54)
            line(0.3, 0.72, 0.56, 0.72)
        case "heart":
            arc(0.06, 0.16, 0.46, 0.5, 150, 390)
            arc(0.48, 0.16, 0.46, 0.5, 150, 390)
            line(0.16, 0.4, 0.5, 0.92)
            line(0.84, 0.4, 0.5, 0.92)
        case "sunset":
            circle(0.5, 0.44, 0.2)
            for a in stride(from: 0.0, to: 360.0, by: 45.0) {
                let r = a * .pi / 180
                line(0.5 + CGFloat(cos(r)) * 0.3, 0.44 + CGFloat(sin(r)) * 0.3,
                     0.5 + CGFloat(cos(r)) * 0.42, 0.44 + CGFloat(sin(r)) * 0.42)
            }
            line(0.1, 0.84, 0.9, 0.84)
        case "timeline":
            line(0.24, 0.08, 0.24, 0.92)
            for (i, y) in [0.2, 0.5, 0.8].enumerated() {
                ctx.fill(Path(ellipseIn: CGRect(x: W * 0.24 - w * 1.1, y: H * y - w * 1.1,
                                                width: w * 2.2, height: w * 2.2)), with: .color(ink))
                line(0.44, y, i == 1 ? 0.78 : 0.92, y)
            }
        case "people":
            circle(0.32, 0.3, 0.14)
            circle(0.68, 0.34, 0.12)
            arc(0.06, 0.56, 0.5, 0.56, 180, 360)
            arc(0.5, 0.6, 0.4, 0.5, 200, 340)
        case "device":
            rect(0.24, 0.04, 0.52, 0.92, 0.14)
            line(0.42, 0.86, 0.58, 0.86)
        case "wave":
            for (i, h) in [0.3, 0.62, 0.9, 0.55, 0.28].enumerated() {
                let x = 0.12 + CGFloat(i) * 0.19
                line(x, 0.5 - h / 2, x, 0.5 + h / 2)
            }
        case "pin":
            var p = Path()
            p.move(to: CGPoint(x: W * 0.5, y: H * 0.94))
            p.addCurve(to: CGPoint(x: W * 0.5, y: H * 0.06),
                       control1: CGPoint(x: W * 0.02, y: H * 0.5),
                       control2: CGPoint(x: W * 0.14, y: H * 0.06))
            p.addCurve(to: CGPoint(x: W * 0.5, y: H * 0.94),
                       control1: CGPoint(x: W * 0.86, y: H * 0.06),
                       control2: CGPoint(x: W * 0.98, y: H * 0.5))
            ctx.stroke(p, with: .color(ink), style: style)
            circle(0.5, 0.38, 0.12)
        case "sparkle":
            line(0.5, 0.06, 0.5, 0.94)
            line(0.06, 0.5, 0.94, 0.5)
            line(0.2, 0.2, 0.8, 0.8)
            line(0.8, 0.2, 0.2, 0.8)
        case "grid":
            for (x, y) in [(0.08, 0.08), (0.56, 0.08), (0.08, 0.56), (0.56, 0.56)] {
                ctx.stroke(Path(roundedRect: CGRect(x: W * x, y: H * y, width: W * 0.36, height: H * 0.36),
                                cornerRadius: W * 0.08), with: .color(ink), lineWidth: w)
            }
        case "send":
            var p = Path()
            p.move(to: CGPoint(x: W * 0.06, y: H * 0.5))
            p.addLine(to: CGPoint(x: W * 0.94, y: H * 0.12))
            p.addLine(to: CGPoint(x: W * 0.62, y: H * 0.92))
            p.addLine(to: CGPoint(x: W * 0.48, y: H * 0.6))
            p.closeSubpath()
            ctx.stroke(p, with: .color(ink), style: style)
        case "cloud":
            arc(0.06, 0.34, 0.44, 0.5, 150, 20)
            arc(0.34, 0.18, 0.5, 0.6, 200, 10)
            line(0.18, 0.86, 0.82, 0.86)
        case "sun":
            circle(0.5, 0.5, 0.24)
            for i in 0..<8 {
                let a = Double(i) * 45 * .pi / 180
                let r1 = 0.34, r2 = 0.46
                let x1 = 0.5 + CGFloat(cos(a)) * r1, y1 = 0.5 + CGFloat(sin(a)) * r1
                let x2 = 0.5 + CGFloat(cos(a)) * r2, y2 = 0.5 + CGFloat(sin(a)) * r2
                line(x1, y1, x2, y2)
            }
        case "info":
            circle(0.5, 0.5, 0.44)
            line(0.5, 0.44, 0.5, 0.72)
            ctx.fill(Path(ellipseIn: CGRect(x: W * 0.5 - w * 0.6, y: H * 0.28 - w * 0.6,
                                            width: w * 1.2, height: w * 1.2)), with: .color(ink))
        case "lines":
            line(0.08, 0.24, 0.92, 0.24)
            line(0.08, 0.5, 0.92, 0.5)
            line(0.08, 0.76, 0.62, 0.76)
        case "check":
            var p = Path()
            p.move(to: CGPoint(x: W * 0.16, y: H * 0.54))
            p.addLine(to: CGPoint(x: W * 0.42, y: H * 0.8))
            p.addLine(to: CGPoint(x: W * 0.86, y: H * 0.24))
            ctx.stroke(p, with: .color(ink), style: style)
        default:
            star(&ctx, W: W, H: H, style: style)
        }
    }

    private func star(_ ctx: inout GraphicsContext, W: CGFloat, H: CGFloat, style: StrokeStyle) {
        var p = Path()
        for i in 0..<10 {
            let r = i % 2 == 0 ? W * 0.46 : W * 0.2
            let a = (-90.0 + Double(i) * 36.0) * .pi / 180
            let x = W * 0.5 + r * CGFloat(cos(a))
            let y = H * 0.54 + r * CGFloat(sin(a))
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        p.closeSubpath()
        ctx.stroke(p, with: .color(RsIconTint.fg("star")), style: style)
    }
}
