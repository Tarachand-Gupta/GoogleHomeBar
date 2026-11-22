import AppKit
import SwiftUI

/// Custom native Sign-In gate shown whenever the user is signed out.
/// Never exposes Google's marketing landing page (`home.google.com/welcome`):
/// clicking "Sign in with Google" goes directly to `accounts.google.com/ServiceLogin?continue=https://home.google.com/`
/// and automatically returns to the native Devices dashboard as soon as login finishes.
struct GoogleSignInGateView: View {
    @Bindable var coordinator: AppCoordinator
    let isDetachedHost: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = ModernPalette(colorScheme: colorScheme)

        if coordinator.webController.isInteractiveSignInActive {
            interactiveSignInWebFlow(palette: palette)
        } else {
            nativeSignInCard(palette: palette)
        }
    }

    private func nativeSignInCard(palette: ModernPalette) -> some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(palette.accent.opacity(palette.isDark ? 0.22 : 0.14))
                        .frame(width: 82, height: 82)
                        .blur(radius: 10)

                    RoundedRectangle(cornerRadius: 22)
                        .fill(palette.accentGradient)
                        .frame(width: 66, height: 66)
                        .overlay(
                            RoundedRectangle(cornerRadius: 22)
                                .strokeBorder(Color.white.opacity(0.32), lineWidth: 1)
                        )
                        .shadow(color: palette.accent.opacity(0.35), radius: 12, y: 5)

                    Image(systemName: "house.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color.white)
                }

                VStack(spacing: 6) {
                    Text("Sign in to Google Home")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(palette.textPrimary)

                    Text("Connect directly to your Google account to control lights, climate, fans, and smart devices from your menu bar.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 310)
                }

                Button {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                    coordinator.webController.beginInteractiveSignIn()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.badge.key.fill")
                            .font(.system(size: 13.5, weight: .semibold))
                        Text("Sign in with Google")
                            .font(.system(size: 13.5, weight: .bold))
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 11)
                    .background(palette.accentGradient, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.28), lineWidth: 0.8))
                    .shadow(color: palette.accent.opacity(0.38), radius: 10, y: 4)
                    .contentShape(Capsule())
                }
                .buttonStyle(.liquidGlassCapsule)
                .padding(.top, 2)

                HStack(spacing: 6) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.accent)
                    Text("Direct Google session · Zero API keys or third-party servers")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.textMuted)
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 30)
            .frame(maxWidth: 400)
            .background(
                coordinator.settings.uiStyle == .modern ? palette.card : Color.clear,
                in: RoundedRectangle(cornerRadius: 24)
            )
            .modifier(SignInCardGlassModifier(isModern: coordinator.settings.uiStyle == .modern, palette: palette))
            .padding(.horizontal, 20)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func interactiveSignInWebFlow(palette: ModernPalette) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                    coordinator.webController.cancelInteractiveSignIn()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .bold))
                        Text("Back")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .liquidGlassSurface(in: Capsule(), interactive: true)
                    .contentShape(Capsule())
                }
                .buttonStyle(.liquidGlassCapsule)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Google Sign-In")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text("You'll return to Devices automatically after signing in.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                if !isDetachedHost {
                    Button("Larger Window") {
                        coordinator.openDetachedWindow()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(palette.canvas)

            Divider()

            if coordinator.webController.isLoading {
                ProgressView(value: coordinator.webController.estimatedProgress)
                    .progressViewStyle(.linear)
                    .tint(palette.accent)
                    .frame(height: 2)
            }

            HStack(spacing: 7) {
                Image(systemName: "key.slash")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                Text("Use Password or \"Try another way\" (macOS WebViews do not support local Passkeys).")
                    .font(.caption2)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(palette.accent.opacity(palette.isDark ? 0.16 : 0.08))

            PersistentWebViewHost(
                webView: coordinator.webController.webView,
                zoom: max(coordinator.settings.webPageZoom, 0.90),
                priority: isDetachedHost ? .visibleDetachedWindow : .visiblePopover
            )
            .transaction { $0.animation = nil }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SignInCardGlassModifier: ViewModifier {
    let isModern: Bool
    let palette: ModernPalette

    func body(content: Content) -> some View {
        if isModern {
            content
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(palette.glassRimHighlight, lineWidth: 1)
                )
                .shadow(color: palette.cardShadow, radius: 14, y: 6)
        } else {
            content
                .liquidGlassSurface(in: RoundedRectangle(cornerRadius: 24), shadowRadius: 10)
        }
    }
}
