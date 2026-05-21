import SwiftUI
import AppKit

struct AboutView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                .resizable()
                .frame(width: 96, height: 96)

            VStack(spacing: 4) {
                Text("nvEnvy")
                    .font(.system(size: 24, weight: .semibold))
                Text("Version \(version) (\(build))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("A fast, keyboard-driven note-taking app for macOS.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Divider()

            VStack(spacing: 6) {
                Text("Made by Kendall from [lunt.co](https://lunt.co)")
                    .font(.callout)
                    .multilineTextAlignment(.center)

                Text("Descended from [Notational Velocity](http://notational.net) by Zachary Schneirov.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Built with")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("• [Sparkle](https://sparkle-project.org) — auto-update")
                Text("• [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) — global hotkeys")
                Text("• [Yams](https://github.com/jpsim/Yams) — YAML parsing")
                Text("• [swift-markdown](https://github.com/apple/swift-markdown) — Markdown rendering")
            }
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                Button("Website") { open("https://nvenvy.app") }
                Button("GitHub") { open("https://github.com/kenm47/nvEnvy") }
                Button("Privacy") { open("https://nvenvy.app/privacy") }
            }
            .controlSize(.small)

            Text("© 2026 Kendall Miller · MIT License")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(width: 380)
    }

    private func open(_ url: String) {
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }
}
