import SwiftUI

// IRIS v0.0.2 — inspector droit. Zone vide avec section "Détails".
// v0.0.5+ — affichera la fiche d'un agent : status runtime, mémoires récentes, events I/O, coût LLM.

struct InspectorView: View {
    @Environment(IRISAppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: IRISTokens.spacing16) {
                sectionHeader("Détails")

                inspectorBody
                    .padding(IRISTokens.spacing16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusMedium, style: .continuous)
                            .fill(IRISTokens.cardSurface.opacity(0.5))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusMedium, style: .continuous)
                            .strokeBorder(IRISTokens.irisAccent.opacity(0.08), lineWidth: 0.5)
                    )

                Spacer(minLength: 0)
            }
            .padding(IRISTokens.spacing16)
        }
        .scrollContentBackground(.hidden)
        .background(
            ZStack {
                Rectangle().fill(.regularMaterial)
                IRISTokens.skyBackground.opacity(0.18)
            }
            .ignoresSafeArea()
        )
        .navigationSplitViewColumnWidth(
            min: IRISTokens.inspectorMinWidth,
            ideal: IRISTokens.inspectorIdealWidth,
            max: IRISTokens.inspectorMaxWidth
        )
    }

    @ViewBuilder
    private var inspectorBody: some View {
        switch appState.selection {
        case .some(.agent(let agent)):
            agentDetails(agent.descriptor)
        case .some(.system(let dest)):
            systemDetails(dest)
        case .none:
            placeholderEmpty
        }
    }

    private var placeholderEmpty: some View {
        VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            Text("Aucune sélection")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
            Text("Sélectionne un agent dans le sidebar pour voir ses détails ici.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func agentDetails(_ descriptor: AgentDescriptor) -> some View {
        VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            HStack(spacing: IRISTokens.spacing8) {
                Image(systemName: descriptor.symbol)
                    .foregroundStyle(IRISTokens.irisAccent)
                Text(descriptor.displayName)
                    .font(.system(size: 14, weight: .semibold))
            }

            Text(descriptor.alias)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Divider()
                .padding(.vertical, IRISTokens.spacing4)

            Text(descriptor.tagline)
                .font(.system(size: 12))
                .foregroundStyle(.primary.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)

            Text("Status, événements I/O, coût LLM — v0.0.5+")
                .font(IRISTokens.monoFont)
                .foregroundStyle(.secondary)
                .padding(.top, IRISTokens.spacing8)
        }
    }

    private func systemDetails(_ destination: SystemDestination) -> some View {
        VStack(alignment: .leading, spacing: IRISTokens.spacing8) {
            HStack(spacing: IRISTokens.spacing8) {
                Image(systemName: destination.symbol)
                    .foregroundStyle(.secondary)
                Text(destination.displayName)
                    .font(.system(size: 14, weight: .semibold))
            }

            Text("Panel système — v0.0.3")
                .font(IRISTokens.monoFont)
                .foregroundStyle(.secondary)
                .padding(.top, IRISTokens.spacing4)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.4)
            .foregroundStyle(.secondary)
            .padding(.horizontal, IRISTokens.spacing4)
    }
}

#Preview {
    InspectorView()
        .environment(IRISAppState())
        .frame(width: 320, height: 600)
}
