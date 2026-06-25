//
//  WelcomeView.swift
//  Gojo
//
//  Created by Richard Kunkli on 2024. 09. 26..
//

import SwiftUI

/// Sunset accent palette for the onboarding flow: dark / gray forward, warmed
/// by a classic sunset spread of blue (high), orange (mid) and red (low). Used
/// for the background glows, the aperture aura and accents.
extension Color {
    static let sunsetSky    = Color(red: 0.30, green: 0.46, blue: 0.95)  // sky blue
    static let sunsetMauve  = Color(red: 0.66, green: 0.42, blue: 0.72)  // violet bridge
    static let sunsetPeach  = Color(red: 1.00, green: 0.55, blue: 0.20)  // orange
    static let sunsetCoral  = Color(red: 0.93, green: 0.27, blue: 0.30)  // red
    static let sunsetButton = Color(red: 0.94, green: 0.43, blue: 0.43)  // coral (CTA/accent)
    static let onboardingControl = Color(red: 0.62, green: 0.61, blue: 0.66).opacity(0.85)  // soft translucent slate (buttons)
}

/// Simple translucent + blurred square button for the onboarding flow.
struct GlassButtonStyle: ButtonStyle {
    private let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 22)
            .padding(.vertical, 9)
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay { shape.fill(Color.onboardingControl.opacity(0.22)) }
                    .overlay { shape.strokeBorder(Color.white.opacity(0.22), lineWidth: 1) }
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct WelcomeView: View {
    var onGetStarted: (() -> Void)? = nil

    /// Drives the aperture: 0 = closed (a thin slit), 1 = fully open.
    @State private var aperture: Double = 0
    /// Mark overshoot/settle after the aperture opens.
    @State private var settle: Double = 0
    /// Bloom flash at the moment the aperture snaps open.
    @State private var bloom: Double = 0
    /// Staggered settle for the wordmark/tagline and the call-to-action.
    @State private var textIn = false
    @State private var ctaIn = false

    var body: some View {
        ZStack {
            // Gray, gently living backdrop with mild sunset accents.
            SunsetBackground()

            // Warm sunset bloom radiating from the aperture as it snaps open.
            RadialGradient(
                colors: [
                    Color.sunsetPeach.opacity(0.30),
                    Color.sunsetCoral.opacity(0.16),
                    .clear,
                ],
                center: .center, startRadius: 0, endRadius: 220
            )
            .scaleEffect(0.5 + bloom * 0.8)
            .opacity(bloom)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)

            // Welcome content, revealed through the eye-shaped aperture.
            content
                .mask(ApertureShape(progress: aperture))

            // Warm iris rim tracing the opening, fading as it completes.
            ApertureShape(progress: aperture)
                .stroke(Color.sunsetPeach.opacity(0.45), lineWidth: 1.5)
                .blur(radius: 3)
                .opacity((1 - aperture) * 0.9)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onAppear(perform: runIntro)
    }

    private var content: some View {
        VStack(spacing: 4) {
            MarkHero(settle: settle)
                .frame(width: 180, height: 180)

            VStack(spacing: 6) {
                Text("WELCOME TO")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .tracking(4)
                    .foregroundStyle(.secondary)

                Text("Gojo")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Your notch, reimagined.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .opacity(textIn ? 1 : 0)
            .offset(y: textIn ? 0 : 10)
            .padding(.bottom, 28)

            Button {
                onGetStarted?()
            } label: {
                Text("Get started")
            }
            .buttonStyle(GlassButtonStyle())
            .opacity(ctaIn ? 1 : 0)
            .offset(y: ctaIn ? 0 : 10)
        }
    }

    private func runIntro() {
        withAnimation(.spring(response: 1.15, dampingFraction: 0.78)) {
            aperture = 1
        }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.5).delay(0.45)) {
            settle = 1
        }
        withAnimation(.easeOut(duration: 0.3).delay(0.4)) { bloom = 1 }
        withAnimation(.easeIn(duration: 0.7).delay(0.7)) { bloom = 0 }
        withAnimation(.easeOut(duration: 0.45).delay(0.9)) { textIn = true }
        withAnimation(.easeOut(duration: 0.45).delay(1.1)) { ctaIn = true }
    }
}

/// The Gojo mark (neutral dark) with a breathing coral accent halo and a
/// periodic specular sheen — keeps the hero alive at rest.
struct MarkHero: View {
    /// 0 → 1 entrance progress (spring-driven, may overshoot past 1).
    var settle: Double

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let breathe = 1 + 0.022 * sin(t * 1.0)
            let sweep = t.truncatingRemainder(dividingBy: 5.0) / 5.0  // 0..1

            ZStack {
                // The mark (neutral), with a sheen sweeping across it.
                mark
                    .foregroundStyle(.primary)
                    .overlay {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [.clear, .white.opacity(0.55), .clear],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .frame(width: 55)
                            .rotationEffect(.degrees(20))
                            .offset(x: CGFloat(sweep * 2 - 1) * 130)
                            .mask(mark)
                            .blendMode(.plusLighter)
                            .opacity(min(settle, 1))
                    }
                    .scaleEffect(breathe * (0.7 + 0.3 * settle))
            }
        }
    }

    private var mark: some View {
        Image("gojo-mark")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 100, height: 100)
    }
}

/// A dark, gray frosted backdrop (the system HUD material) with mild, slowly
/// drifting sunset-toned blobs — blue, orange and red — so the flow feels alive
/// without overwhelming the gray. Shared across the onboarding screens.
struct SunsetBackground: View {
    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)

            // Soft light-blue horizon glow across the center.
            GeometryReader { geo in
                RadialGradient(
                    colors: [Color(red: 0.62, green: 0.78, blue: 0.95).opacity(0.20), .clear],
                    center: .center, startRadius: 0, endRadius: geo.size.width * 0.62
                )
                .frame(width: geo.size.width, height: geo.size.height)
                .scaleEffect(x: 1.0, y: 0.34, anchor: .center)
                .blur(radius: 36)
                .blendMode(.plusLighter)
            }

            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                GeometryReader { geo in
                    ZStack {
                        blob(.sunsetSky, at: CGPoint(x: 0.28, y: 0.24),
                             speed: 0.05, wobble: 1.0, radius: 300, opacity: 0.16, geo: geo, t: t)
                        blob(.sunsetPeach, at: CGPoint(x: 0.70, y: 0.74),
                             speed: 0.045, wobble: 1.3, radius: 320, opacity: 0.18, geo: geo, t: t)
                        blob(.sunsetCoral, at: CGPoint(x: 0.66, y: 0.30),
                             speed: 0.05, wobble: 0.8, radius: 240, opacity: 0.13, geo: geo, t: t)
                    }
                    .blendMode(.plusLighter)
                }
            }
        }
        .ignoresSafeArea()
    }

    private func blob(_ color: Color, at base: CGPoint, speed: Double, wobble: Double,
                      radius: CGFloat, opacity: Double, geo: GeometryProxy, t: Double) -> some View {
        let dx = CGFloat(sin(t * speed)) * geo.size.width * 0.14
        let dy = CGFloat(cos(t * speed * wobble)) * geo.size.height * 0.12
        return RadialGradient(
            colors: [color.opacity(opacity), .clear],
            center: .center, startRadius: 0, endRadius: radius
        )
        .frame(width: radius * 2, height: radius * 2)
        .position(x: geo.size.width * base.x + dx, y: geo.size.height * base.y + dy)
        .blur(radius: 50)
    }
}

/// An eye / camera-aperture opening that grows from a thin horizontal slit
/// (`progress` 0) into the full frame (`progress` 1). At low progress the
/// opening is an almond peaked at the center and tapering to points at the
/// edges; as it completes, the edges relax so the shape fills the rectangle.
struct ApertureShape: Shape {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let p = max(0, min(1, progress))
        let midY = rect.midY
        let samples = 48

        var top: [CGPoint] = []
        var bottom: [CGPoint] = []
        for i in 0...samples {
            let t = Double(i) / Double(samples)
            let x = rect.minX + CGFloat(t) * rect.width
            // Bell curve: 1 at the center, 0 at the edges.
            let bell = sin(Double.pi * t)
            // Interpolate from almond (bell) toward a flat full-height profile.
            let factor = bell * (1 - p) + p
            let halfH = (rect.height / 2) * CGFloat(p) * CGFloat(factor)
            top.append(CGPoint(x: x, y: midY - halfH))
            bottom.append(CGPoint(x: x, y: midY + halfH))
        }

        var path = Path()
        path.move(to: top[0])
        for pt in top.dropFirst() { path.addLine(to: pt) }
        for pt in bottom.reversed() { path.addLine(to: pt) }
        path.closeSubpath()
        return path
    }
}

#Preview {
    WelcomeView()
        .frame(width: 400, height: 600)
}
