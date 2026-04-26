import SwiftUI

struct OverlayView: View {
    @ObservedObject var viewModel: OverlayViewModel

    // Calculated from recording pill content:
    // 15 bars × 2.5 + 14 gaps × 2 = 65.5 (waveform)
    // + padding .horizontal 14 = 93.5
    // + 2 buttons × 24 = 141.5
    // + outer padding .horizontal 6 = 153.5
    private let pillWidth: CGFloat = 153.5

    private var contentHeight: CGFloat {
        let pillHeight: CGFloat = 38
        let cardHeight: CGFloat = viewModel.showPartialText ? 80 : 0
        let cardSpacing: CGFloat = viewModel.showPartialText ? 6 : 0
        let micExtra: CGFloat = viewModel.micNotificationText != nil ? 30 : 0
        let networkExtra: CGFloat = viewModel.networkWarningText != nil ? 30 : 0
        return pillHeight + cardHeight + cardSpacing + micExtra + networkExtra
    }

    var body: some View {
        VStack(spacing: 6) {
            if let text = viewModel.networkWarningText {
                networkWarningBanner(text: text)
            }

            if let text = viewModel.micNotificationText {
                micNotificationBanner(text: text)
            }

            if viewModel.isThinking {
                thinkingPill
            } else {
                recordingPill
            }

            if viewModel.showPartialText {
                partialTextCard
            }
        }
        .frame(width: 420, height: contentHeight)
    }

    // MARK: - Mic Notification Banner

    private func micNotificationBanner(text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "mic.fill")
                .font(.system(size: 9))
            Text("当前使用 \(text) 麦克风")
                .font(.system(size: 11, weight: .medium, design: .rounded))
        }
        .foregroundColor(.white.opacity(0.78))
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(
            ZStack {
                Capsule()
                    .fill(Color(red: 20/255, green: 20/255, blue: 30/255).opacity(0.55))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.18), Color.clear],
                            startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.3)
                        )
                    )
                Capsule()
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
            }
        )
        .shadow(color: .black.opacity(0.32), radius: 10, y: 4)
        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        .transition(.opacity)
    }

    // MARK: - Network Warning Banner

    private func networkWarningBanner(text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9))
            Text(text)
                .font(.system(size: 11, weight: .medium, design: .rounded))
        }
        .foregroundColor(Color(red: 1, green: 196/255, blue: 107/255))
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(
            ZStack {
                Capsule()
                    .fill(Color(red: 60/255, green: 32/255, blue: 8/255).opacity(0.55))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 1, green: 200/255, blue: 120/255).opacity(0.24), Color.clear],
                            startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.3)
                        )
                    )
                Capsule()
                    .strokeBorder(Color(red: 1, green: 180/255, blue: 80/255).opacity(0.36), lineWidth: 0.5)
            }
        )
        .shadow(color: .black.opacity(0.32), radius: 10, y: 4)
        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        .transition(.opacity)
    }

    // MARK: - Recording Pill (Liquid Glass)

    private var recordingPill: some View {
        HStack(spacing: 0) {
            // Cancel button
            Button(action: { viewModel.onCancel?() }) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.14))
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.32), Color.clear],
                                startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.4)
                            )
                        )
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.clear, Color.black.opacity(0.18)],
                                startPoint: UnitPoint(x: 0.5, y: 0.5), endPoint: .bottom
                            )
                        )
                    Circle()
                        .strokeBorder(Color.white.opacity(0.32), lineWidth: 0.5)
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white.opacity(0.95))
                }
                .frame(width: 24, height: 24)
                .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
            }
            .buttonStyle(.plain)

            // Waveform
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<viewModel.levelHistory.count, id: \.self) { i in
                    WaveformBar(
                        level: viewModel.levelHistory[i],
                        index: i,
                        total: viewModel.levelHistory.count
                    )
                }
            }
            .frame(height: 22)
            .padding(.horizontal, 14)

            // Confirm button
            Button(action: { viewModel.onConfirm?() }) {
                ZStack {
                    Circle()
                        .fill(Color(red: 80/255, green: 220/255, blue: 140/255).opacity(0.34))
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.3), Color.clear],
                                startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.4)
                            )
                        )
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.clear, Color(red: 0, green: 40/255, blue: 15/255).opacity(0.2)],
                                startPoint: UnitPoint(x: 0.5, y: 0.5), endPoint: .bottom
                            )
                        )
                    Circle()
                        .strokeBorder(Color(red: 180/255, green: 1, blue: 210/255).opacity(0.4), lineWidth: 0.5)
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white.opacity(0.95))
                }
                .frame(width: 24, height: 24)
                .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                .shadow(color: Color(red: 80/255, green: 220/255, blue: 140/255).opacity(0.28), radius: 7)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .frame(height: 38)
        .background(pillGlassBackground)
        .clipShape(Capsule())
        .overlay(
            PillShimmerLayer()
                .clipShape(Capsule())
                .allowsHitTesting(false)
        )
        .overlay(pillTopHighlight, alignment: .top)
    }

    // MARK: - Pill Glass Background (7-layer)

    private var pillGlassBackground: some View {
        ZStack {
            // Layer 1: Dark scrim
            Capsule()
                .fill(Color(red: 20/255, green: 20/255, blue: 30/255).opacity(0.42))
            // Layer 2: Material blur
            Capsule()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .opacity(0.6)
            // Layer 3: Prismatic tint (155°)
            Capsule()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.18), location: 0),
                            .init(color: Color.white.opacity(0.06), location: 0.35),
                            .init(color: Color(red: 200/255, green: 210/255, blue: 1).opacity(0.05), location: 0.65),
                            .init(color: Color(red: 1, green: 200/255, blue: 230/255).opacity(0.06), location: 1)
                        ],
                        startPoint: UnitPoint(x: 0.2, y: 0),
                        endPoint: UnitPoint(x: 0.8, y: 1)
                    )
                )
            // Layer 5a: Inner top sheen
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.38), Color.clear],
                        startPoint: .top,
                        endPoint: UnitPoint(x: 0.5, y: 0.3)
                    )
                )
            // Layer 5b: Inner bottom dark edge
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.22)],
                        startPoint: UnitPoint(x: 0.5, y: 0.7),
                        endPoint: .bottom
                    )
                )
            // Layer 6: Outer hairline ring
            Capsule()
                .strokeBorder(Color.white.opacity(0.24), lineWidth: 0.5)
        }
    }

    // MARK: - Pill Top Mirror Highlight

    private var pillTopHighlight: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: Color.white.opacity(0.55), location: 0.3),
                        .init(color: Color.white.opacity(0.92), location: 0.5),
                        .init(color: Color.white.opacity(0.55), location: 0.7),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
            .padding(.horizontal, 16)
            .allowsHitTesting(false)
    }

    // MARK: - Thinking Pill (Rainbow Halo)

    private var thinkingPill: some View {
        ZStack {
            // Rotating rainbow halo (visible through 2px padding gap)
            ThinkingRainbowHalo()

            // Inner dark fill
            Capsule()
                .fill(Color(red: 20/255, green: 20/255, blue: 30/255).opacity(0.7))
                .padding(2)

            // Inner glass
            Capsule()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .opacity(0.4)
                .padding(2)

            // Inner prismatic tint
            Capsule()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.12), location: 0),
                            .init(color: Color.white.opacity(0.03), location: 0.5),
                            .init(color: Color(red: 200/255, green: 210/255, blue: 1).opacity(0.04), location: 1)
                        ],
                        startPoint: UnitPoint(x: 0.2, y: 0),
                        endPoint: UnitPoint(x: 0.8, y: 1)
                    )
                )
                .padding(2)

            // Inner top sheen
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.22), Color.clear],
                        startPoint: .top,
                        endPoint: UnitPoint(x: 0.5, y: 0.3)
                    )
                )
                .padding(2)

            // Border
            Capsule()
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5)
                .padding(2)

            // Content
            HStack(spacing: 8) {
                Text("Optimizing")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.95))
                    .tracking(0.7)
                BounceDots()
            }
        }
        .frame(width: pillWidth, height: 38)
        .clipShape(Capsule())
        .overlay(pillTopHighlight, alignment: .top)
    }

    // MARK: - Partial Text Card

    private var partialTextCard: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                if viewModel.partialText.isEmpty {
                    Text("正在聆听…")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)
                } else {
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(viewModel.partialText)
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(.white.opacity(0.92))
                            .tracking(0.13)
                            .fixedSize(horizontal: false, vertical: true)
                            .id("partialBottom")
                        BlinkingCursor()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .onChange(of: viewModel.partialText) { _ in
                proxy.scrollTo("partialBottom", anchor: .bottom)
            }
        }
        .frame(height: 52)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(textCardGlassBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(textCardTopHighlight, alignment: .top)
    }

    // MARK: - Text Card Glass Background

    private var textCardGlassBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 20/255, green: 20/255, blue: 30/255).opacity(0.42))
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .opacity(0.6)
            // Prismatic tint (160°)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.13), location: 0),
                            .init(color: Color.white.opacity(0.04), location: 0.5),
                            .init(color: Color(red: 180/255, green: 200/255, blue: 1).opacity(0.06), location: 1)
                        ],
                        startPoint: UnitPoint(x: 0.2, y: 0),
                        endPoint: UnitPoint(x: 0.8, y: 1)
                    )
                )
            // Prismatic glaze (corner-to-corner)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color(red: 200/255, green: 180/255, blue: 1).opacity(0.09), location: 0),
                            .init(color: .clear, location: 0.4),
                            .init(color: .clear, location: 0.6),
                            .init(color: Color(red: 1, green: 200/255, blue: 220/255).opacity(0.07), location: 1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            // Inner top sheen
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.3), Color.clear],
                        startPoint: .top,
                        endPoint: UnitPoint(x: 0.5, y: 0.3)
                    )
                )
            // Inner bottom dark edge
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.15)],
                        startPoint: UnitPoint(x: 0.5, y: 0.7),
                        endPoint: .bottom
                    )
                )
            // Hairline border
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
        }
    }

    private var textCardTopHighlight: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: Color.white.opacity(0.5), location: 0.3),
                        .init(color: Color.white.opacity(0.78), location: 0.5),
                        .init(color: Color.white.opacity(0.5), location: 0.7),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
            .padding(.horizontal, 22)
            .allowsHitTesting(false)
    }
}

// MARK: - Pill Shimmer Animation

struct PillShimmerLayer: View {
    @State private var offset: CGFloat = -8

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: Color(red: 1, green: 180/255, blue: 220/255).opacity(0.12), location: 0),
                .init(color: Color(red: 180/255, green: 220/255, blue: 1).opacity(0.06), location: 0.25),
                .init(color: .clear, location: 0.45),
                .init(color: .clear, location: 0.55),
                .init(color: Color(red: 220/255, green: 180/255, blue: 1).opacity(0.08), location: 0.75),
                .init(color: Color(red: 1, green: 200/255, blue: 180/255).opacity(0.10), location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .opacity(0.85)
        .offset(x: offset)
        .padding(.horizontal, -2)
        .onAppear {
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                offset = 8
            }
        }
    }
}

// MARK: - Thinking Rainbow Halo

struct ThinkingRainbowHalo: View {
    @State private var rotation: Double = 0

    var body: some View {
        AngularGradient(
            colors: [
                Color(red: 1, green: 94/255, blue: 138/255),
                Color(red: 1, green: 175/255, blue: 77/255),
                Color(red: 77/255, green: 1, blue: 156/255),
                Color(red: 77/255, green: 196/255, blue: 1),
                Color(red: 181/255, green: 77/255, blue: 1),
                Color(red: 1, green: 94/255, blue: 138/255)
            ],
            center: .center
        )
        .blur(radius: 16)
        .scaleEffect(2)
        .rotationEffect(.degrees(rotation))
        .onAppear {
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

// MARK: - Bounce Dots

struct BounceDots: View {
    @State private var active = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 4, height: 4)
                    .scaleEffect(active ? 1 : 0.6)
                    .opacity(active ? 1 : 0.4)
                    .animation(
                        .easeInOut(duration: 0.7)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.16),
                        value: active
                    )
            }
        }
        .onAppear { active = true }
    }
}

// MARK: - Waveform Bar

struct WaveformBar: View {
    let level: Float
    let index: Int
    let total: Int
    @State private var animatedHeight: CGFloat = 2

    var body: some View {
        Capsule()
            .fill(Color.white.opacity(0.75))
            .frame(width: 2.5, height: animatedHeight)
            .onChange(of: level) { newLevel in
                withAnimation(.interpolatingSpring(stiffness: 280, damping: 18)) {
                    let base: CGFloat = 2
                    let maxH: CGFloat = 12
                    animatedHeight = max(base, base + CGFloat(newLevel) * maxH)
                }
            }
    }
}

// MARK: - Blinking Cursor

struct BlinkingCursor: View {
    @State private var visible = true
    private let timer = Timer.publish(every: 0.55, on: .main, in: .common).autoconnect()

    var body: some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(Color.white.opacity(0.85))
            .frame(width: 2, height: 13)
            .opacity(visible ? 1 : 0)
            .onReceive(timer) { _ in
                withAnimation(.easeInOut(duration: 0.18)) { visible.toggle() }
            }
    }
}
