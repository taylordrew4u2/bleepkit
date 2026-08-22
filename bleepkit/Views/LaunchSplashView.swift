//
//  LaunchSplashView.swift
//  BleepKit
//

import SwiftUI

/// The cold-launch splash: an audio meter dances, collapses into the
/// app icon's white speech bubble, and the icon's grawlix stamps
/// inside — the final frame is the icon itself before it clears.
///
/// Purely decorative — the host disables hit-testing so the app is
/// usable underneath from the first frame, and the whole sequence is
/// hidden from assistive technologies. With Reduce Motion on, the
/// meter is skipped and the bubble simply appears and fades.
struct LaunchSplashView: View {
    /// Called after the outro completes so the host can remove the view.
    let onFinished: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Phase {
        /// Meter bars dancing to imaginary speech.
        case meter
        /// Bars collapsed into the empty speech bubble.
        case bubble
        /// Grawlix punched into the bubble — the app icon, recreated.
        case stamped
        /// Fading out over the app.
        case done
    }

    @State private var phase: Phase = .meter

    var body: some View {
        ZStack {
            Color.bleepLaunchBackground
                .ignoresSafeArea()
            switch phase {
            case .meter:
                meter
                    .transition(.opacity)
            case .bubble, .stamped, .done:
                iconBubble
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .opacity(phase == .done ? 0 : 1)
        .accessibilityHidden(true)
        .task { await run() }
    }

    // MARK: Scenes

    private var meter: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: Spacing.tight) {
                ForEach(0..<SplashMetrics.barCount, id: \.self) { index in
                    Capsule()
                        .fill(Color.bleepAccent)
                        .frame(
                            width: SplashMetrics.barWidth,
                            height: Self.meterHeight(bar: index, at: time)
                        )
                }
            }
        }
    }

    /// Layered sines read as speech on a level meter without needing
    /// randomness (which would fight snapshotting and Reduce Motion).
    private nonisolated static func meterHeight(bar index: Int, at time: TimeInterval) -> CGFloat {
        let wave = sin(time * 6.0 + Double(index) * 0.9) * 0.5
            + sin(time * 11.0 + Double(index) * 1.7) * 0.3
            + sin(time * 3.0 + Double(index) * 0.4) * 0.2
        let level = 0.25 + 0.75 * abs(wave)
        return SplashMetrics.barWidth
            + (SplashMetrics.meterHeight - SplashMetrics.barWidth) * level
    }

    /// The app icon, recreated live: white bubble, black grawlix.
    /// Body and tail are separate overlapping fills — a single path
    /// left a winding seam where the two met.
    private var iconBubble: some View {
        let bodyHeight = SplashMetrics.bubbleHeight * SpeechBubbleShape.bodyHeightFraction
        return RoundedRectangle(cornerRadius: bodyHeight * SpeechBubbleShape.cornerRadiusFraction)
            .fill(Color.bleepOnVideo)
            .frame(width: SplashMetrics.bubbleWidth, height: bodyHeight)
            .background(alignment: .bottom) {
                SpeechBubbleTail()
                    .fill(Color.bleepOnVideo)
                    .frame(
                        width: SplashMetrics.bubbleWidth,
                        height: SplashMetrics.bubbleHeight - bodyHeight
                    )
                    // Rooted well inside the body so the joint can't show.
                    .offset(y: SplashMetrics.bubbleHeight - bodyHeight)
            }
            .overlay {
                if phase == .stamped || phase == .done {
                    Text("!#@*")
                        .font(.bleepSplashGrawlix)
                        // The icon's black glyphs — same black as the
                        // backdrop the bubble floats on.
                        .foregroundStyle(Color.bleepLaunchBackground)
                        .transition(.scale(scale: 1.6).combined(with: .opacity))
                }
            }
    }

    // MARK: Sequence

    private func run() async {
        if reduceMotion {
            phase = .stamped
            try? await Task.sleep(for: .seconds(0.8))
            withAnimation(.easeOut(duration: 0.3)) { phase = .done }
            try? await Task.sleep(for: .seconds(0.3))
            onFinished()
            return
        }
        try? await Task.sleep(for: .seconds(0.9))
        withAnimation(.spring(duration: 0.35)) { phase = .bubble }
        try? await Task.sleep(for: .seconds(0.35))
        withAnimation(.spring(duration: 0.3, bounce: 0.45)) { phase = .stamped }
        try? await Task.sleep(for: .seconds(0.75))
        withAnimation(.easeOut(duration: 0.35)) { phase = .done }
        try? await Task.sleep(for: .seconds(0.35))
        onFinished()
    }
}

/// Proportions of the app icon's speech bubble, shared by the body and
/// tail so both stay traced to the same artwork.
enum SpeechBubbleShape {
    /// How much of the bubble frame's height the rounded body occupies;
    /// the tail hangs in the remainder.
    static let bodyHeightFraction: CGFloat = 0.82
    /// Body corner radius as a fraction of the body's height.
    static let cornerRadiusFraction: CGFloat = 0.22
}

/// The icon bubble's tail: a wedge rooted just past a third of the way
/// across, tapering to a tip that leans slightly left. Its root is
/// drawn above the frame, into the body, so no seam can show.
struct SpeechBubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        let overlap = rect.height * 0.5
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.34, y: rect.minY - overlap))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.385, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.48, y: rect.minY - overlap))
        path.closeSubpath()
        return path
    }
}
