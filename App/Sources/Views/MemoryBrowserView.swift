import SwiftUI
import SwiftData
import AppKit

/// v1.56 — Browse all Memory records + ad-hoc Scribe retrieval query.
/// v1.64 — Delete memory record with confirmation (NSAlert).
/// v1.84 — Tag filter Picker.
/// v1.167 — Export filtered memories to Markdown (home dir).
/// v1.177 — Pin/unpin memory via "pinned" tag, pinned rows sort to top.
/// v1.182 — Pinned-only filter toggle (filters to tag pinned).
/// v1.194 — Type stats footer with count + circle color per type.
/// Permet à Mehdi d'inspecter ce que Scribe sait, et de tester les requêtes de similarité.
struct MemoryBrowserView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Memory.createdAt, order: .reverse) private var allMemories: [Memory]

    @State private var typeFilter: String = ""
    @State private var searchText: String = ""
    @State private var tagFilter: String = ""  // v1.84
    @State private var pinnedOnly: Bool = false  // v1.182
    @State private var retrievalQuery: String = ""
    @State private var retrievalResults: [(Memory, Double)] = []
    @State private var isRetrieving: Bool = false
    @State private var exportStatus: String?  // v1.167

    private var availableTypes: [String] {
        Array(Set(allMemories.map(\.type))).sorted()
    }

    // v1.194 — Type stats: count per memory type, sorted desc
    private var typeStats: [(type: String, count: Int)] {
        var dict: [String: Int] = [:]
        for m in allMemories {
            dict[m.type, default: 0] += 1
        }
        return dict.map { (type: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    private var filtered: [Memory] {
        var items = allMemories
        if !typeFilter.isEmpty {
            items = items.filter { $0.type == typeFilter }
        }
        if !tagFilter.isEmpty {
            let tag = tagFilter.lowercased()
            items = items.filter { $0.tagsCSV.lowercased().contains(tag) }
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            items = items.filter {
                $0.name.lowercased().contains(q) ||
                $0.summary.lowercased().contains(q) ||
                $0.content.lowercased().contains(q)
            }
        }
        if pinnedOnly {
            items = items.filter { isPinned($0) }
        }
        return items.sorted { lhs, rhs in
            if isPinned(lhs) != isPinned(rhs) {
                return isPinned(lhs)
            } else {
                return lhs.createdAt > rhs.createdAt
            }
        }
    }

    // MARK: — v1.177 Pin/Unpin

    private func isPinned(_ memory: Memory) -> Bool {
        let tags = memory.tagsCSV
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return tags.contains("pinned")
    }

    private func togglePin(_ memory: Memory) {
        var tags = memory.tagsCSV
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if let idx = tags.firstIndex(of: "pinned") {
            tags.remove(at: idx)
        } else {
            tags.insert("pinned", at: 0)
        }
        memory.tagsCSV = tags.joined(separator: ", ")
        try? modelContext.save()
    }

    /// v1.84 — Liste des tags uniques (split CSV) pour suggestions
    private var availableTags: [String] {
        var tags = Set<String>()
        for m in allMemories {
            let parts = m.tagsCSV.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            for p in parts where !p.isEmpty { tags.insert(p) }
        }
        return Array(tags).sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            tagCloud
            Divider()
            retrievalBar
            Divider()
            if !retrievalResults.isEmpty {
                retrievalResultsView
                Divider()
            }
            mainList
            Divider()
            typeStatsFooter
        }
        .navigationTitle("Memory")
    }

    // v1.194 — Type stats footer: circle color + count per type
    private var typeStatsFooter: some View {
        HStack(spacing: IRISTokens.spacing16) {
            Text("PAR TYPE")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(.secondary)
            ForEach(Array(typeStats.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 4) {
                    Circle()
                        .fill(typeColor(item.type))
                        .frame(width: 6, height: 6)
                    Text(item.type)
                        .font(.system(size: 10))
                        .foregroundStyle(.primary)
                    Text("\(item.count)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("\(allMemories.count) total")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(IRISTokens.aquaTint)
        }
        .padding(.horizontal, IRISTokens.spacing16)
        .padding(.vertical, IRISTokens.spacing8)
        .background(.thinMaterial)
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

            // v1.167 — Export filtered memories to Markdown
            Button {
                exportAllMemories()
            } label: {
                Label("Export MD", systemImage: "square.and.arrow.up")
                    .font(.system(size: 11))
            }
            .controlSize(.small)
            .help("Export toutes les memories filtrées en Markdown")

            if let status = exportStatus {
                Text(status)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(status.hasPrefix("✅") ? .green : .red)
                    .lineLimit(1)
            }

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

            // v1.84 — Tag filter Picker
            Picker("Tag", selection: $tagFilter) {
                Text("All tags").tag("")
                ForEach(availableTags, id: \.self) { t in
                    Text(t).tag(t)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(maxWidth: 140)

            // v1.182 — Pinned-only filter toggle
            Button {
                pinnedOnly.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: pinnedOnly ? "pin.fill" : "pin")
                    Text("Pinned").font(.system(size: 11))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(pinnedOnly ? IRISTokens.goldAccent : .secondary)
            .help(pinnedOnly ? "Désactiver le filtre pinned" : "Afficher uniquement les memories pinned (tag 'pinned')")

            TextField("Search name/summary/content…", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(maxWidth: 240)
        }
        .padding(IRISTokens.spacing16)
    }

    // v1.165 — Tag cloud row (capsules avec count, toggle tagFilter au click)
    private var tagCloud: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("TAGS")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(availableTags, id: \.self) { tag in
                        let count = allMemories.filter {
                            $0.tagsCSV.lowercased().contains(tag.lowercased())
                        }.count
                        let isSelected = tagFilter == tag
                        Button {
                            tagFilter = isSelected ? "" : tag
                        } label: {
                            HStack(spacing: 4) {
                                Text(tag)
                                    .font(.system(size: 11, weight: .medium))
                                Text("\(count)")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(
                                    isSelected
                                        ? IRISTokens.aquaTint
                                        : Color.secondary.opacity(0.10)
                                )
                            )
                            .foregroundStyle(isSelected ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, IRISTokens.spacing16)
            }
        }
        .padding(.top, 4)
        .padding(.bottom, IRISTokens.spacing8)
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
                // v1.177 — Pin/unpin toggle
                Button {
                    togglePin(memory)
                } label: {
                    Image(systemName: isPinned(memory) ? "pin.fill" : "pin")
                        .font(.system(size: 9))
                        .foregroundStyle(isPinned(memory) ? IRISTokens.goldAccent : .secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help(isPinned(memory) ? "Unpin (retire le tag pinned)" : "Pin to top (ajoute le tag pinned)")
                // v1.64 — Delete with confirmation
                Button {
                    confirmDelete(memory: memory)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 9))
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Supprimer cette memory (confirmation requise)")
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

    // MARK: — v1.167 Export Markdown

    private func exportAllMemories() {
        var md = "# IRIS Memories Export\n_\(filtered.count) records · \(Date().formatted(date: .abbreviated, time: .shortened))_\n\n---\n\n"
        for memory in filtered {
            md += "## \(memory.type) · \(memory.name)\n\n"
            if !memory.summary.isEmpty {
                md += "**Summary:** \(memory.summary)\n\n"
            }
            if let scope = memory.projectScope {
                md += "**Scope:** \(scope)\n\n"
            }
            md += "**Created:** \(memory.createdAt.formatted(.dateTime.day().month().year().hour().minute()))\n\n"
            if !memory.tagsCSV.isEmpty {
                md += "**Tags:** \(memory.tagsCSV)\n\n"
            }
            md += "```\n\(memory.content)\n```\n\n---\n\n"
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        let safeStamp = isoFormatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("iris-memories-\(safeStamp).md")

        do {
            try md.write(to: url, atomically: true, encoding: .utf8)
            exportStatus = "✅ → \(url.lastPathComponent)"
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                exportStatus = nil
            }
        } catch {
            exportStatus = "⚠️ \(error.localizedDescription)"
        }
    }

    // MARK: — v1.64 Delete

    private func confirmDelete(memory: Memory) {
        let alert = NSAlert()
        alert.messageText = "Supprimer cette memory ?"
        alert.informativeText = """
        \(memory.type) · \(memory.name)
        \(memory.summary.isEmpty ? String(memory.content.prefix(120)) : memory.summary)

        Action irréversible. Si memory factory (seedée depuis ~/.claude/projects/.../memory/),
        elle sera re-seedée au prochain launch IRIS.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Supprimer")
        alert.addButton(withTitle: "Annuler")
        if alert.runModal() == .alertFirstButtonReturn {
            modelContext.delete(memory)
            try? modelContext.save()
            // Si présent dans retrievalResults, le retirer
            retrievalResults.removeAll { $0.0.id == memory.id }
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
