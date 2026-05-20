import SwiftUI
import SwiftData

/// v1.56 — Browse all Memory records + ad-hoc Scribe retrieval query.
/// Permet à Mehdi d'inspecter ce que Scribe sait, et de tester les requêtes de similarité.
struct MemoryBrowserView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Memory.createdAt, order: .reverse) private var allMemories: [Memory]

    @State private var typeFilter: String = ""
    @State private var searchText: String = ""
    @State private var retrievalQuery: String = ""
    @State private var retrievalResults: [(Memory, Double)] = []
    @State private var isRetrieving: Bool = false

    private var availableTypes: [String] {
        Array(Set(allMemories.map(\.type))).sorted()
    }

    private var filtered: [Memory] {
        var items = allMemories
        if !typeFilter.isEmpty {
            items = items.filter { $0.type == typeFilter }
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            items = items.filter {
                $0.name.lowercased().contains(q) ||
                $0.summary.lowercased().contains(q) ||
                $0.content.lowercased().contains(q)
            }
        }
        return items
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            retrievalBar
            Divider()
            if !retrievalResults.isEmpty {
                retrievalResultsView
                Divider()
            }
            mainList
        }
        .navigationTitle("Memory")
    }

    private var header: some View {
        HStack(spacing: IRISTokens.spacing16) {
            Image(systemName: "books.vertical")
                .foregroundStyle(IRISTokens.irisAccent)
                .font(.system(size: 18, weight: .light))
            Text("Memory browser")
                .font(.system(size: 18, weight: .light, design: .serif))
                .foregroundStyle(.primary)
            Text("\(allMemories.count) records")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()

            Picker("Type", selection: $typeFilter) {
                Text("All types").tag("")
                ForEach(availableTypes, id: \.self) { t in
                    Text(t).tag(t)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(maxWidth: 180)

            TextField("Search name/summary/content…", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(maxWidth: 240)
        }
        .padding(IRISTokens.spacing16)
    }

    private var retrievalBar: some View {
        HStack(spacing: IRISTokens.spacing8) {
            Image(systemName: "sparkle.magnifyingglass")
                .foregroundStyle(IRISTokens.aquaTint)
            TextField("Ad-hoc retrieval query (Scribe NLEmbedding top-5)…", text: $retrievalQuery)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .onSubmit(runRetrieval)
            Button("Retrieve") { runRetrieval() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(IRISTokens.aquaTint)
                .disabled(retrievalQuery.trimmingCharacters(in: .whitespaces).isEmpty || isRetrieving)
            if !retrievalResults.isEmpty {
                Button("Clear") {
                    retrievalResults = []
                    retrievalQuery = ""
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(IRISTokens.spacing8)
        .background(.thinMaterial)
    }

    private var retrievalResultsView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                Text("TOP \(retrievalResults.count) RÉSULTATS SIMILARITÉ")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 2)
                ForEach(Array(retrievalResults.enumerated()), id: \.offset) { idx, item in
                    memoryRow(item.0, score: item.1, rank: idx + 1)
                }
            }
            .padding(IRISTokens.spacing8)
        }
        .frame(maxHeight: 220)
        .background(IRISTokens.aquaTint.opacity(0.05))
    }

    private var mainList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                if filtered.isEmpty {
                    Text("Aucune mémoire correspondante.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(IRISTokens.spacing24)
                } else {
                    ForEach(filtered) { memory in
                        memoryRow(memory, score: nil, rank: nil)
                    }
                }
            }
            .padding(IRISTokens.spacing8)
        }
    }

    private func memoryRow(_ memory: Memory, score: Double?, rank: Int?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if let rank {
                    Text("#\(rank)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(IRISTokens.aquaTint)
                }
                Text(memory.type)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(typeColor(memory.type))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(typeColor(memory.type).opacity(0.15))
                    .clipShape(Capsule())
                Text(memory.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Spacer()
                if let scope = memory.projectScope {
                    Text(scope)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(IRISTokens.irisAccent)
                }
                if let score {
                    Text(String(format: "%.3f", score))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(IRISTokens.goldAccent)
                }
                Text(memory.createdAt, format: .dateTime.day().month().hour().minute())
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            if !memory.summary.isEmpty {
                Text(memory.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4).padding(.horizontal, IRISTokens.spacing8)
        .background(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusSmall).fill(.thinMaterial))
    }

    private func typeColor(_ type: String) -> Color {
        switch type {
        case "conversation": return IRISTokens.irisAccent
        case "user", "feedback": return IRISTokens.aquaTint
        case "project", "reference": return IRISTokens.goldAccent
        default: return .secondary
        }
    }

    // MARK: — Retrieval

    private func runRetrieval() {
        let query = retrievalQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !isRetrieving else { return }
        isRetrieving = true

        let context = modelContext
        Task { @MainActor in
            let results = await Scribe.retrieve(
                query: query,
                topK: 5,
                type: nil,
                projectScope: nil,
                in: context
            )
            retrievalResults = results
            isRetrieving = false
        }
    }
}

#Preview {
    MemoryBrowserView()
        .frame(width: 900, height: 700)
}
