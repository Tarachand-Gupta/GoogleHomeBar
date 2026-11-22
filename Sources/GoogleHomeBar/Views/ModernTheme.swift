import AppKit
import SwiftUI

/// Color-scheme-aware design tokens for the Modern smart-home UI (Light & Dark modes).
struct ModernPalette {
    let colorScheme: ColorScheme

    var isDark: Bool { colorScheme == .dark }

    /// Primary cobalt accent matching the smart-home controls.
    var accent: Color {
        isDark
            ? Color(red: 0.185, green: 0.565, blue: 0.980)
            : Color(red: 0.055, green: 0.420, blue: 0.785)
    }

    var accentDeep: Color {
        isDark
            ? Color(red: 0.115, green: 0.445, blue: 0.875)
            : Color(red: 0.035, green: 0.340, blue: 0.675)
    }

    var accentGradient: LinearGradient {
        LinearGradient(
            colors: [accent, accentDeep],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Signature crimson CTA for turning off active climate/fan devices.
    var danger: Color {
        isDark
            ? Color(red: 0.860, green: 0.195, blue: 0.165)
            : Color(red: 0.690, green: 0.078, blue: 0.072)
    }

    var dangerDeep: Color {
        isDark
            ? Color(red: 0.720, green: 0.130, blue: 0.115)
            : Color(red: 0.560, green: 0.050, blue: 0.050)
    }

    /// Main background canvas.
    var canvas: Color {
        isDark
            ? Color(red: 0.067, green: 0.078, blue: 0.098)
            : Color(red: 0.945, green: 0.956, blue: 0.975)
    }

    /// Elevated card surface (slightly translucent to complement Liquid Glass chrome).
    var card: Color {
        isDark
            ? Color(red: 0.118, green: 0.134, blue: 0.168)
            : Color.white
    }

    /// Subtle raised surface for pills, segmented tracks, and icon medallions.
    var surfaceSubtle: Color {
        isDark
            ? Color(red: 0.160, green: 0.180, blue: 0.222)
            : Color(red: 0.916, green: 0.929, blue: 0.952)
    }

    /// Specular glass hairline rim.
    var border: Color {
        isDark
            ? Color.white.opacity(0.11)
            : Color.black.opacity(0.07)
    }

    var glassRimHighlight: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(isDark ? 0.24 : 0.85),
                Color.white.opacity(isDark ? 0.05 : 0.25),
                Color.black.opacity(isDark ? 0.20 : 0.06),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Soft card drop shadow.
    var cardShadow: Color {
        isDark
            ? Color.black.opacity(0.42)
            : Color(red: 0.08, green: 0.12, blue: 0.22).opacity(0.075)
    }

    /// Floating navigation dock backdrop (fallback for macOS 14–15).
    var dockBackground: Color {
        isDark
            ? Color(red: 0.125, green: 0.145, blue: 0.184).opacity(0.84)
            : Color.white.opacity(0.84)
    }

    var dockShadow: Color {
        isDark
            ? Color.black.opacity(0.55)
            : Color(red: 0.07, green: 0.12, blue: 0.22).opacity(0.16)
    }

    /// Primary & secondary ink.
    var textPrimary: Color {
        isDark
            ? Color(red: 0.955, green: 0.965, blue: 0.985)
            : Color(red: 0.105, green: 0.125, blue: 0.165)
    }

    var textSecondary: Color {
        isDark
            ? Color(red: 0.625, green: 0.670, blue: 0.745)
            : Color(red: 0.435, green: 0.475, blue: 0.545)
    }

    var textMuted: Color {
        isDark
            ? Color(red: 0.455, green: 0.500, blue: 0.580)
            : Color(red: 0.595, green: 0.630, blue: 0.695)
    }

    /// Dial track, ticks, and sculpted center dome.
    var dialTrack: Color {
        isDark
            ? Color.white.opacity(0.11)
            : Color(red: 0.845, green: 0.865, blue: 0.900)
    }

    var dialTick: Color {
        isDark
            ? Color.white.opacity(0.22)
            : Color.black.opacity(0.18)
    }

    var domeTop: Color {
        isDark
            ? Color(red: 0.175, green: 0.198, blue: 0.245)
            : Color.white
    }

    var domeBottom: Color {
        isDark
            ? Color(red: 0.115, green: 0.130, blue: 0.165)
            : Color(red: 0.925, green: 0.938, blue: 0.960)
    }

    var domeShadow: Color {
        isDark
            ? Color.black.opacity(0.58)
            : Color(red: 0.10, green: 0.15, blue: 0.25).opacity(0.16)
    }

    /// Featured climate hero card atmospheric gradient.
    var heroGradientColors: [Color] {
        isDark
            ? [
                Color(red: 0.115, green: 0.215, blue: 0.340),
                Color(red: 0.088, green: 0.150, blue: 0.240),
                Color(red: 0.125, green: 0.180, blue: 0.275),
            ]
            : [
                Color(red: 0.720, green: 0.815, blue: 0.915),
                Color(red: 0.605, green: 0.725, blue: 0.855),
                Color(red: 0.785, green: 0.850, blue: 0.925),
            ]
    }

    var heroStripFill: Color {
        isDark
            ? Color(red: 0.085, green: 0.105, blue: 0.145).opacity(0.82)
            : Color.white.opacity(0.84)
    }

    var toggleOffTrack: Color {
        isDark
            ? Color(red: 0.225, green: 0.250, blue: 0.300)
            : Color(red: 0.845, green: 0.865, blue: 0.895)
    }

    var divider: Color {
        isDark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.07)
    }
}

// MARK: - macOS 26+ Liquid Glass Primitives (with Frosted Glass Fallback on macOS 14–15)

/// Native macOS 26+ Liquid Glass surface modifier with frosted material + specular rim fallback.
struct LiquidGlassSurfaceModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color?
    let interactive: Bool
    let clearStyle: Bool
    let shadowRadius: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let palette = ModernPalette(colorScheme: colorScheme)
        if #available(macOS 26.0, *) {
            let base: Glass = clearStyle ? .clear : .regular
            let tinted = tint != nil ? base.tint(tint) : base
            let configured = interactive ? tinted.interactive() : tinted
            content
                .glassEffect(configured, in: shape)
                .shadow(
                    color: shadowRadius > 0 ? palette.cardShadow : .clear,
                    radius: shadowRadius,
                    y: shadowRadius > 0 ? max(2, shadowRadius * 0.35) : 0
                )
        } else {
            content
                .background {
                    shape
                        .fill(.ultraThinMaterial)
                        .overlay {
                            if let tint {
                                shape.fill(tint.opacity(clearStyle ? 0.22 : 0.32))
                            }
                        }
                }
                .overlay(
                    shape
                        .strokeBorder(palette.glassRimHighlight, lineWidth: 1)
                )
                .shadow(
                    color: shadowRadius > 0 ? palette.cardShadow : .clear,
                    radius: shadowRadius,
                    y: shadowRadius > 0 ? max(2, shadowRadius * 0.35) : 0
                )
        }
    }
}

/// Groups nearby Liquid Glass controls in a native `GlassEffectContainer` on macOS 26+.
struct LiquidGlassGroup<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    init(spacing: CGFloat = 10, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }
}

extension View {
    func liquidGlassSurface<S: InsettableShape>(
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = false,
        clearStyle: Bool = false,
        shadowRadius: CGFloat = 0
    ) -> some View {
        modifier(
            LiquidGlassSurfaceModifier(
                shape: shape,
                tint: tint,
                interactive: interactive,
                clearStyle: clearStyle,
                shadowRadius: shadowRadius
            )
        )
    }

    @ViewBuilder
    func liquidGlassID<ID: Hashable & Sendable>(_ id: ID, in namespace: Namespace.ID) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffectID(id, in: namespace)
        } else {
            self
        }
    }
}

/// Tactile macOS 26 / iOS 26 Liquid Glass click feedback: spring rebound + luminous specular flash on press.
struct LiquidGlassPressStyle<S: InsettableShape>: ButtonStyle {
    let shape: S
    let pressScale: CGFloat
    let flashOpacity: Double

    init(shape: S, pressScale: CGFloat = 0.94, flashOpacity: Double = 0.22) {
        self.shape = shape
        self.pressScale = pressScale
        self.flashOpacity = flashOpacity
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(configuration.isPressed ? flashOpacity : 0),
                                Color.white.opacity(configuration.isPressed ? flashOpacity * 0.35 : 0),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .allowsHitTesting(false)
            }
            .overlay {
                shape
                    .strokeBorder(
                        Color.white.opacity(configuration.isPressed ? 0.55 : 0),
                        lineWidth: 1.25
                    )
                    .allowsHitTesting(false)
            }
            .brightness(configuration.isPressed ? 0.035 : 0)
            .scaleEffect(configuration.isPressed ? pressScale : 1.0)
            .animation(
                .spring(response: 0.24, dampingFraction: 0.62),
                value: configuration.isPressed
            )
    }
}

extension ButtonStyle where Self == LiquidGlassPressStyle<Capsule> {
    static var liquidGlassCapsule: LiquidGlassPressStyle<Capsule> {
        LiquidGlassPressStyle(shape: Capsule(), pressScale: 0.94)
    }
}

extension ButtonStyle where Self == LiquidGlassPressStyle<Circle> {
    static var liquidGlassCircle: LiquidGlassPressStyle<Circle> {
        LiquidGlassPressStyle(shape: Circle(), pressScale: 0.90)
    }
}

// MARK: - Tactile Switch & Slider Controls

/// Visual capsule switch track ("Off" / "On" label inside track) reusable by standalone toggles and full-row toggle buttons.
struct ModernPillSwitchTrack: View {
    let isOn: Bool
    let isDisabled: Bool
    let accentColor: Color?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = ModernPalette(colorScheme: colorScheme)
        let activeFill = accentColor ?? palette.accent

        ZStack {
            Capsule()
                .fill(isOn ? activeFill : palette.toggleOffTrack)
                .frame(width: 58, height: 26)
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(isOn ? 0.25 : 0.12), lineWidth: 0.75)
                )

            HStack(spacing: 0) {
                if isOn {
                    Text("On")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .padding(.leading, 10)

                    Spacer(minLength: 2)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 20, height: 20)
                        .shadow(color: Color.black.opacity(0.20), radius: 2.5, y: 1)
                        .padding(.trailing, 3)
                } else {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 20, height: 20)
                        .shadow(color: Color.black.opacity(0.18), radius: 2.5, y: 1)
                        .padding(.leading, 3)

                    Spacer(minLength: 2)

                    Text("Off")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(palette.isDark ? Color.white.opacity(0.75) : palette.textSecondary)
                        .padding(.trailing, 9)
                }
            }
            .frame(width: 58, height: 26)
        }
        .animation(.spring(response: 0.26, dampingFraction: 0.76), value: isOn)
        .opacity(isDisabled ? 0.5 : 1.0)
    }
}

/// Custom tactile On/Off capsule toggle with glass click bounce.
struct ModernPillToggle: View {
    let isOn: Bool
    let isDisabled: Bool
    let accentColor: Color?
    let onToggle: (Bool) -> Void

    init(
        isOn: Bool,
        isDisabled: Bool = false,
        accentColor: Color? = nil,
        onToggle: @escaping (Bool) -> Void
    ) {
        self.isOn = isOn
        self.isDisabled = isDisabled
        self.accentColor = accentColor
        self.onToggle = onToggle
    }

    var body: some View {
        Button {
            guard !isDisabled else { return }
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            onToggle(!isOn)
        } label: {
            ModernPillSwitchTrack(isOn: isOn, isDisabled: isDisabled, accentColor: accentColor)
                .contentShape(Capsule())
        }
        .buttonStyle(LiquidGlassPressStyle(shape: Capsule(), pressScale: 0.92, flashOpacity: 0.16))
        .disabled(isDisabled)
        .accessibilityLabel(isOn ? "On" : "Off")
        .accessibilityHint("Toggle power")
    }
}

/// Sleek horizontal progress slider with cobalt filled bar and pointer/icon thumb (no macOS ticks).
struct ModernTrackSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let accent: Color
    let isDisabled: Bool
    let thumbSymbol: String?
    let onEditingChanged: (Bool) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isDragging = false

    init(
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        accent: Color,
        isDisabled: Bool = false,
        thumbSymbol: String? = nil,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self._value = value
        self.range = range
        self.accent = accent
        self.isDisabled = isDisabled
        self.thumbSymbol = thumbSymbol
        self.onEditingChanged = onEditingChanged
    }

    private var fraction: Double {
        let span = max(range.upperBound - range.lowerBound, 0.0001)
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    var body: some View {
        let palette = ModernPalette(colorScheme: colorScheme)
        let thumbSize: CGFloat = thumbSymbol != nil ? 24 : 16
        let trackHeight: CGFloat = thumbSymbol != nil ? 10 : 5

        GeometryReader { geo in
            let usableWidth = max(geo.size.width - thumbSize, 1)
            let thumbX = thumbSize / 2 + CGFloat(fraction) * usableWidth

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(palette.surfaceSubtle)
                    .frame(height: trackHeight)

                Capsule()
                    .fill(accent)
                    .frame(width: max(trackHeight, thumbX), height: trackHeight)

                if let thumbSymbol {
                    Circle()
                        .fill(accent)
                        .frame(width: thumbSize, height: thumbSize)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white, lineWidth: 2)
                        )
                        .overlay(
                            Image(systemName: thumbSymbol)
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundStyle(Color.white)
                        )
                        .shadow(color: accent.opacity(0.35), radius: 5, y: 2)
                        .scaleEffect(isDragging ? 1.12 : 1.0)
                        .animation(.spring(response: 0.22, dampingFraction: 0.70), value: isDragging)
                        .position(x: thumbX, y: geo.size.height / 2)
                } else {
                    Circle()
                        .fill(Color.white)
                        .frame(width: thumbSize, height: thumbSize)
                        .overlay(
                            Circle()
                                .strokeBorder(accent, lineWidth: 2.5)
                        )
                        .shadow(color: Color.black.opacity(0.18), radius: 3, y: 1)
                        .scaleEffect(isDragging ? 1.15 : 1.0)
                        .animation(.spring(response: 0.22, dampingFraction: 0.70), value: isDragging)
                        .position(x: thumbX, y: geo.size.height / 2)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard !isDisabled else { return }
                        if !isDragging {
                            isDragging = true
                            onEditingChanged(true)
                        }
                        let raw = (drag.location.x - thumbSize / 2) / usableWidth
                        let clamped = min(max(raw, 0), 1)
                        value = range.lowerBound + Double(clamped) * (range.upperBound - range.lowerBound)
                    }
                    .onEnded { _ in
                        guard !isDisabled else { return }
                        isDragging = false
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: max(thumbSize + 6, 26))
        .opacity(isDisabled ? 0.5 : 1.0)
    }
}

// MARK: - Floating Liquid Glass Navigation Dock

/// Floating macOS 26+ Liquid Glass pill dock for the Modern menu bar experience.
struct ModernFloatingNavDock: View {
    @Binding var selectedTab: AppTab
    let castActiveCount: Int
    let onSelect: (AppTab) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var pillNamespace

    var body: some View {
        let palette = ModernPalette(colorScheme: colorScheme)

        LiquidGlassGroup(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(AppTab.allCases) { tab in
                    let isSelected = selectedTab == tab
                    Button {
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.80)) {
                            onSelect(tab)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 13.5, weight: .semibold))
                                if tab == .cast && castActiveCount > 0 && !isSelected {
                                    Circle()
                                        .fill(palette.accent)
                                        .frame(width: 6, height: 6)
                                        .offset(x: 3, y: -2)
                                }
                            }

                            if isSelected {
                                Text(tab.title)
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .lineLimit(1)
                                    .fixedSize()
                                    .transition(.opacity.combined(with: .scale(scale: 0.88)))
                            }
                        }
                        .foregroundStyle(isSelected ? Color.white : palette.textSecondary)
                        .padding(.horizontal, isSelected ? 14 : 12)
                        .frame(height: 36)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(palette.accentGradient)
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(Color.white.opacity(0.28), lineWidth: 0.8)
                                    )
                                    .matchedGeometryEffect(id: "activeDockPill", in: pillNamespace)
                                    .shadow(color: palette.accent.opacity(0.35), radius: 8, y: 3)
                            }
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(LiquidGlassPressStyle(shape: Capsule(), pressScale: 0.91))
                    .accessibilityLabel(tab.title)
                    .help(tab.title)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .liquidGlassSurface(in: Capsule(), interactive: true, shadowRadius: 14)
        }
    }
}

/// Syncs an NSWindow's native chrome appearance (titlebar/controls) with AppAppearanceMode.
struct WindowAppearanceSync: NSViewRepresentable {
    let appearance: NSAppearance?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.appearance = appearance
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if nsView.window?.appearance != appearance {
                nsView.window?.appearance = appearance
            }
        }
    }
}
