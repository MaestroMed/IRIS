import SwiftUI
import SwiftData
import AppKit

/// v1.45 — Vue affichée dans le menu bar macOS via MenuBarExtra scene.
/// Compteurs live + actions rapides accessibles même quand fenêtre principale fermée.
struct MenuBarStatusView: View {
    @Environment(IRISAppState.self) private var appState  // v1.98
    @Query(sort: \Signal.emittedAt, order: .reverse) private var allSignals: [Signal]
    @Query private var allDrafts: [Draft]

    var body: some View {
        let signals24h = allSignals.filter { $0.emittedAt > Date().addingTimeInterval(-86400) }.count
        let pendingDrafts = allDrafts.filter { $0.status == "pending" }.count
        let criticalSignals = allSignals.filter {
            $0.emittedAt > Date().addingTimeInterval(-86400) && $0.importance == 5
        }.count

        VStack(alignment: .leading) {
            Text("IRIS")
                .font(.system(size: 13, weight: .semibold, design: .serif))
                .padding(.bottom, 4)

            Divider()

            menuRow(icon: "eye.circle", label: "Signaux 24h", value: "\(signals24h)", color: .secondary)
            if criticalSignals > 0 {
                menuRow(icon: "exclamationmark.triangle.fill", label: "Critical 24h", value: "\(criticalSignals)", color: .red)
            }
            menuRow(icon: "pencil.and.scribble", label: "Drafts pending", value: "\(pendingDrafts)", color: pendingDrafts > 0 ? .orange : .secondary)

            // v1.98 — Cost session display (rouge si limit dépassée)
            let costColor: Color = appState.costLimitTriggered ? .red :
                                   (appState.sessionCostUSD > 0.5 ? .orange : .secondary)
            menuRow(
                icon: "dollarsign.circle",
                label: "Cost session",
                value: "$\(String(format: "%.4f", appState.sessionCostUSD))",
                color: costColor
            )

            Divider()

            Button("Ouvrir IRIS") {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first(where: { $0.canBecomeKey }) {
                    window.makeKeyAndOrderFront(nil)
                }
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Button("Settings…") {
                NSApplication.openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("Quitter IRIS") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(IRISTokens.spacing8)
        .frame(width: 240)
    }

    private func menuRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11))
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
    }
}
