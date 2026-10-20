import SwiftUI

private let productionCenterFill: Color = /* MUSIC_CENTER_FILL */
private let closedTopRadius: CGFloat = /* CLOSED_TOP_RADIUS */

private struct PaintSpecimen: View {
    let centerFill: Color
    let progress: Double
    var closedHeight: CGFloat?

    private func music(height: CGFloat) -> some View {
        HStack {
            Color.red.frame(width: max(0, height - 12), height: max(0, height - 12))
            Rectangle().fill(centerFill).frame(width: 185 - closedTopRadius)
            HStack { Color.cyan.frame(width: 50).mask(Color.white.frame(width: 16, height: 12)) }
                .frame(width: max(0, height - 12), height: max(0, height - 12))
        }.frame(height: height)
    }

    var body: some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading) {
                if let closedHeight {
                    music(height: closedHeight)
                } else {
                    ZStack(alignment: .top) {
                        HStack(spacing: 0) {
                            Color.clear.frame(maxWidth: .infinity)
                            Rectangle().fill(.clear).frame(width: 185).mask(NotchShape())
                            Color.clear.frame(maxWidth: .infinity)
                        }.frame(height: 32).opacity(progress)
                        music(height: 32).opacity(1 - progress)
                    }
                }
            }.zIndex(2)
            if closedHeight == nil {
                VStack {
                    Color.orange.frame(width: 400, height: 160)
                        .scaleEffect(x: 1.3, y: 1.4).rotationEffect(.degrees(92))
                        .blur(radius: 40).opacity(0.5).frame(width: 500, height: 160)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .scaleEffect(0.8 + 0.2 * progress, anchor: .top).opacity(progress).zIndex(1)
            }
        }
        .frame(width: closedHeight == nil ? 500 : nil, height: closedHeight == nil ? 220 : nil, alignment: .top)
        .padding(.horizontal, closedHeight == nil ? 19 : 14)
        .padding([.horizontal, .bottom], closedHeight == nil ? 12 : 0)
        .background(.black)
        .clipShape(NotchShape(topCornerRadius: closedHeight == nil ? 19 : 6, bottomCornerRadius: closedHeight == nil ? 24 : 14))
        .overlay(alignment: .top) {
            Rectangle().fill(.black).frame(height: 1).padding(.horizontal, closedHeight == nil ? 19 : 6)
        }
        .padding(.bottom, closedHeight == 0 ? 10 : 0).padding(.bottom, 8)
        .frame(maxWidth: 640, maxHeight: 280, alignment: .top)
        .compositingGroup().preferredColorScheme(.dark)
    }
}

@main
private struct NotchMusicSpacerPaintRegression {
    @MainActor
    private static func render(_ view: PaintSpecimen) -> (size: CGSize, pixels: [UInt8]) {
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: 640, height: 280)
        renderer.scale = 1
        let image = renderer.cgImage!
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        CGContext(data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            .draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return (CGSize(width: image.width, height: image.height), pixels)
    }

    @MainActor
    static func main() {
        var failures: [String] = []
        for progress in [0.25, 0.5, 0.75] {
            let actual = render(PaintSpecimen(centerFill: productionCenterFill, progress: progress))
            let reference = render(PaintSpecimen(centerFill: .clear, progress: progress))
            let darkened = stride(from: 0, to: actual.pixels.count, by: 4).filter { i in
                (0..<3).contains { Int(actual.pixels[i + $0]) + 1 < Int(reference.pixels[i + $0]) }
            }.count
            if actual.size != reference.size || actual.pixels != reference.pixels {
                failures.append("Explicit crossfade at \(progress) has \(darkened) darkened pixels over the incoming backdrop")
            }
        }
        for height in [CGFloat(32), 0] {
            let actual = render(PaintSpecimen(centerFill: productionCenterFill, progress: 0, closedHeight: height))
            let baseline = render(PaintSpecimen(centerFill: .black, progress: 0, closedHeight: height))
            if actual.size != baseline.size || actual.pixels != baseline.pixels {
                failures.append("Closed mini at height \(height) changed its size or pixels")
            }
        }
        failures.forEach { print($0) }
        guard failures.isEmpty else { exit(1) }
        print("Music spacer rendered paint regressions passed at explicit crossfade progress and closed heights 32/0")
    }
}
