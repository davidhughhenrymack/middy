import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

@main
struct MakeIcon {
    static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let scope = renderScope()
        for size in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = size * scale
                let image: CGImage
                if pixels == scope.width {
                    image = scope
                } else {
                    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                                            bytesPerRow: 0, space: scope.colorSpace!,
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                    context.interpolationQuality = .high
                    context.draw(scope, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
                    image = context.makeImage()!
                }
                let suffix = scale == 1 ? "" : "@2x"
                let url = directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
                let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString,
                                                                  1, nil)!
                CGImageDestinationAddImage(destination, image, nil)
                precondition(CGImageDestinationFinalize(destination), "Unable to write \(url.path)")
            }
        }
    }

    private static func renderScope() -> CGImage {
        let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let housing = CGRect(x: 116, y: 116, width: 792, height: 792)
        let screen = housing.insetBy(dx: 64, dy: 64)

        func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
            CGColor(red: r, green: g, blue: b, alpha: a)
        }

        let casePath = CGPath(roundedRect: housing, cornerWidth: 188, cornerHeight: 188, transform: nil)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -16), blur: 23, color: color(0, 0, 0, 0.56))
        context.setFillColor(color(0.055, 0.066, 0.06))
        context.addPath(casePath)
        context.fillPath()
        context.restoreGState()
        context.setLineWidth(7)
        context.setStrokeColor(color(0.21, 0.25, 0.22))
        context.addPath(casePath)
        context.strokePath()

        context.addPath(CGPath(roundedRect: screen, cornerWidth: 128, cornerHeight: 128, transform: nil))
        context.clip()
        let glow = CGGradient(colorsSpace: context.colorSpace, colors: [
            color(0.109, 0.21, 0.139), color(0.022, 0.052, 0.034), color(0.006, 0.013, 0.010)
        ] as CFArray, locations: [0, 0.73, 1])!
        context.drawRadialGradient(glow, startCenter: CGPoint(x: 483, y: 552), startRadius: 0,
                                   endCenter: CGPoint(x: 483, y: 552), endRadius: 468,
                                   options: [.drawsAfterEndLocation])

        context.setLineWidth(3)
        context.setStrokeColor(color(0, 0, 0, 0.21))
        for y in stride(from: 183, to: 841, by: 10) {
            context.move(to: CGPoint(x: 180, y: y))
            context.addLine(to: CGPoint(x: 844, y: y))
        }
        context.strokePath()

        let trace = CGMutablePath()
        trace.move(to: CGPoint(x: 270, y: 488))
        trace.addLine(to: CGPoint(x: 363, y: 491))
        trace.addLine(to: CGPoint(x: 400, y: 548))
        trace.addQuadCurve(to: CGPoint(x: 508, y: 550), control: CGPoint(x: 442, y: 556))
        trace.addLine(to: CGPoint(x: 540, y: 459))
        trace.addLine(to: CGPoint(x: 616, y: 458))
        trace.addLine(to: CGPoint(x: 648, y: 506))
        trace.addQuadCurve(to: CGPoint(x: 753, y: 504), control: CGPoint(x: 696, y: 510))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setShadow(offset: .zero, blur: 38, color: color(0.31, 1, 0.52))
        context.setLineWidth(30)
        context.setStrokeColor(color(0.35, 0.9, 0.52, 0.66))
        context.addPath(trace)
        context.strokePath()
        context.setShadow(offset: .zero, blur: 0)
        context.setLineWidth(12)
        context.setStrokeColor(color(0.73, 1, 0.79))
        context.addPath(trace)
        context.strokePath()
        return context.makeImage()!
    }

}
