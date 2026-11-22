import AppKit
import GoogleHomeBarCore
import SwiftUI

struct GoogleHomeTabView: View {
    @Bindable var coordinator: AppCoordinator
    let isDetachedHost: Bool

    var body: some View {
        if !isDetachedHost && coordinator.isDetachedWindowOpen {
            detachedPlaceholder
        } else if coordinator.webController.authState == .signedOut {
            GoogleSignInGateView(coordinator: coordinator, isDetachedHost: isDetachedHost)
        } else {
            VStack(spacing: 0) {
                webToolbar
                Divider()

                if coordinator.webController.isLoading {
                    ProgressView(value: coordinator.webController.estimatedProgress)
                        .progressViewStyle(.linear)
                        .tint(.accentColor)
                        .frame(height: 2)
                }

                if coordinator.webController.isOnGoogleSignIn {
                    signInHintBanner
                }

                if let error = coordinator.webController.lastError {
                    errorBanner(error)
                }

                PersistentWebViewHost(
                    webView: coordinator.webController.webView,
                    zoom: coordinator.settings.webPageZoom,
                    priority: isDetachedHost ? .visibleDetachedWindow : .visiblePopover
                )
                .transaction { $0.animation = nil }
                .onAppear {
                    coordinator.webController.loadIfNeeded()
                }
            }
        }
    }

    private var webToolbar: some View {
        HStack(spacing: 6) {
            Button {
                coordinator.webController.navigate(to: .home)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "house.fill")
                        .font(.system(size: 10))
                    Text("Home")
                        .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(
                    coordinator.webController.activeSection == .home
                        ? Color.accentColor.opacity(0.15)
                        : Color.primary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 5)
                )
                .foregroundStyle(
                    coordinator.webController.activeSection == .home
                        ? Color.accentColor
                        : Color.secondary
                )
                .contentShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .help("Go to home.google.com")

            Text(coordinator.webController.pageTitle)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            HStack(spacing: 4) {
                Button {
                    coordinator.webController.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(!coordinator.webController.canGoBack)
                .accessibilityLabel("Back")
                .help("Back")

                Button {
                    coordinator.webController.goForward()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(!coordinator.webController.canGoForward)
                .accessibilityLabel("Forward")
                .help("Forward")

                Divider()
                    .frame(height: 12)
                    .padding(.horizontal, 2)

                Button {
                    let next = max(0.65, coordinator.settings.webPageZoom - 0.05)
                    coordinator.settings.webPageZoom = next
                    coordinator.webController.setZoom(next)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.system(size: 11))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Zoom Out")
                .help("Zoom Out")

                Text("\(Int((coordinator.settings.webPageZoom * 100).rounded()))%")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(width: 30)

                Button {
                    let next = min(1.25, coordinator.settings.webPageZoom + 0.05)
                    coordinator.settings.webPageZoom = next
                    coordinator.webController.setZoom(next)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 11))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Zoom In")
                .help("Zoom In")

                Divider()
                    .frame(height: 12)
                    .padding(.horizontal, 2)

                Button {
                    coordinator.webController.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Reload")
                .help("Reload Page")

                Button {
                    coordinator.webController.openInDefaultBrowser()
                } label: {
                    Image(systemName: "safari")
                        .font(.system(size: 11))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Open in Browser")
                .help("Open in Browser")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.025))
    }

    private var signInHintBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "key.slash")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text("Local Passkeys aren't allowed in macOS WebViews — use Password or \"Try another way\".")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            if !isDetachedHost {
                Button("Open Window") {
                    coordinator.openDetachedWindow()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.08))
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .lineLimit(2)
            Spacer()
            Button("Retry") {
                coordinator.webController.reload()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
    }

    private var detachedPlaceholder: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "macwindow.on.rectangle")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Google Home is open in its own window")
                .font(.headline)
            Text("Close the window or bring it back here anytime.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
            HStack(spacing: 8) {
                Button("Focus Window") {
                    coordinator.openDetachedWindow()
                }
                .buttonStyle(.borderedProminent)
                Button("Return to Menu Bar") {
                    coordinator.closeDetachedWindow()
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        }
        .padding(24)
    }
}
