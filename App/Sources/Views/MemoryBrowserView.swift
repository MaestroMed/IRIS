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
/// v1.198 — Sort by Picker (newest/oldest/type/name), pinned always on top.
/// v1.208 — Per-row copy content button with 2s checkmark feedback.
/// v1.215 — Pin all of currently-filtered type bulk action (gold pin.fill button).
/// v1.221 — Divider with "UNPINNED" label between pinned and unpinned groups in mainList.
/// v1.227 — Bulk add-tag to filtered memories.
/// v1.233 — Expandable rows with full content (chevron toggle, textSelection enabled).
/// v1.239 — Cmd+/ focus search TextField (hidden Button).
/// v1.251 — Search-text highlighting in memory rows (summary + expanded content).
/// v1.264 — Hide tag cloud toggle (@AppStorage memoryHideTagCloud).
/// v1.269 — Sort direction indicator icon next to Sort Picker.
/// v1.275 — Visual relevance bar (40px max) next to retrieval score.
/// v1.285 — Per-row "copy UUID" button (number.circle icon).
/// v1.291 — Regex search mode toggle (NSRegularExpression case-insensitive).
/// v1.300 — Duplicate memory names detection banner (gold triangle).
/// v1.306 — Jump-to-top floating button for memories list.
/// v1.312 — Date range filter Picker (all/7d/30d/90d) on memories.
/// Permet à Mehdi d'inspecter ce que Scribe sait, et de tester les requêtes de similarité.
enum MemorySortMode: String, CaseIterable { case newest, oldest, type, name }

struct MemoryBrowserView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Memory.createdAt, order: .reverse) private var allMemories: [Memory]

    @State private var typeFilter: String = ""
    @State private var searchText: String = ""
    @State private var regexMode: Bool = false  // v1.291
    @State private var tagFilter: String = ""  // v1.84
    @State private var dateRangeFilter: String = "all"  // v1.312
    @State private var pinnedOnly: Bool = false  // v1.182
    @State private var sortMode: MemorySortMode = .newest  // v1.198
    @State private var retrievalQuery: String = ""
    @State private var retrievalResults: [(Memory, Double)] = []
    @State private var isRetrieving: Bool = false
    @State private var exportStatus: String?  // v1.167
    @State private var copyStatus: [UUID: Bool] = [:]  // v1.208
    @State private var bulkTagInput: String = ""  // v1.227
    @State private var bulkTagStatus: String?  // v1.227
    @State private var expandedIds: Set<UUID> = []  // v1.233
    @FocusState private var searchFieldFocused: Bool  // v1.239
    @AppStorage("memoryHideTagCloud") private var hideTagCloud: Bool = false  // v1.264

    private var availableTypes: [String] {
        Array(Set(allMemories.map(\.type))).sorted()
    }

    // v1.300 — Duplicate memory names detection
    private var duplicateCounts: [String: Int] {
        var dict: [String: Int] = [:]
        for m in allMemories {
            dict[m.name, default: 0] += 1
        }
        return dict.filter { $0.value > 1 }
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
            if regexMode {
                // Try compile regex; if invalid, skip filter
                if let regex = try? NSRegularExpression(pattern: searchText, options: [.caseInsensitive]) {
                    items = items.filter { memory in
                        let combined = memory.name + " " + memory.summary + " " + memory.content
                        let range = NSRange(combined.startIndex..., in: combined)
                        return regex.firstMatch(in: combined, range: range) != nil
                    }
                }
            } else {
                let q = searchText.lowercased()
                items = items.filter {
                    $0.name.lowercased().contains(q) ||
                    $0.summary.lowercased().contains(q) ||
                    $0.content.lowercased().contains(q)
                }
            }
        }
        if pinnedOnly {
            items = items.filter { isPinned($0) }
        }
        let cutoff: Date? = {
            switch dateRangeFilter {
            case "7d": return Date().addingTimeInterval(-7 * 86400)
            case "30d": return Date().addingTimeInterval(-30 * 86400)
            case "90d": return Date().addingTimeInterval(-90 * 86400)
            default: return nil
            }
        }()
        if let cutoff {
            items = items.filter { $0.createdAt >= cutoff }
        }
        return items.sorted { lhs, rhs in
            if isPinned(lhs) != isPinned(rhs) { return isPinned(lhs) }
            switch sortMode {
            case .newest: return lhs.createdAt > rhs.createdAt
            case .oldest: return lhs.createdAt < rhs.createdAt
            case .type: return lhs.type < rhs.type
            case .name: return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
    }

    // MARK: — v1.269 Sort direction indicator

    private var sortIndicatorIcon: String {
        switch sortMode {
        case .newest: return "arrow.down"
        case .oldest: return "arrow.up"
        case .type, .name: return "textformat"
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

    // MARK: — v1.215 Bulk pin by type

    private func pinAllOfType(_ type: String) {
        guard !type.isEmpty else { return }
        for memory in allMemories where memory.type == type && !isPinned(memory) {
            var tags = memory.tagsCSV
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if !tags.contains("pinned") {
                tags.insert("pinned", at: 0)
            }
            memory.tagsCSV = tags.joined(separator: ", ")
        }
        try? modelContext.save()
    }

    // MARK: — v1.227 Bulk add-tag to filtered

    private func addTagToFiltered(_ tag: String) {
        guard !tag.isEmpty else { return }
        let count = filtered.count
        for memory in filtered {
            var tags = memory.tagsCSV
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if !tags.contains(tag) {
                tags.append(tag)
            }
            memory.tagsCSV = tags.joined(separator: ", ")
        }
        try? modelContext.save()
        bulkTagStatus = "✅ Tag '\(tag)' ajouté à \(count) memories"
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            bulkTagStatus = nil
        }
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
            // v1.239 — Hidden Cmd+/ shortcut to focus search field
            Button("") { searchFieldFocused = true }
                .keyboardShortcut(KeyEquivalent("/"), modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
            header
            if !hideTagCloud {
                tagCloud
                Divider()
            }
            retrievalBar
            Divider()
            if !retrievalResults.isEmpty {
                retrievalResultsView
                Divider()
            }
            duplicatesBanner
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

            // v1.215 — Pin all of currently-filtered type
            if !typeFilter.isEmpty {
                Button { pinAllOfType(typeFilter) } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "pin.fill").font(.system(size: 9))
                        Text("Pin all").font(.system(size: 10))
                    }
                }
                .controlSize(.small)
                .tint(IRISTokens.goldAccent)
                .help("Pin tous les memories du type \(typeFilter)")
            }

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

            // v1.312 — Date range filter Picker
            Picker("Date", selection: $dateRangeFilter) {
                Text("All time").tag("all")
                Text("Past 7d").tag("7d")
                Text("Past 30d").tag("30d")
                Text("Past 90d").tag("90d")
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(maxWidth: 100)
            .pickerStyle(.menu)

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

            // v1.227 — Bulk add-tag to filtered
            HStack(spacing: 4) {
                TextField("Bulk tag", text: $bulkTagInput)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .frame(maxWidth: 80)
                    .onSubmit {
                        let trimmed = bulkTagInput.trimmingCharacters(in: .whitespaces)
                        addTagToFiltered(trimmed)
                        bulkTagInput = ""
                    }
                Button {
                    let trimmed = bulkTagInput.trimmingCharacters(in: .whitespaces)
                    addTagToFiltered(trimmed)
                    bulkTagInput = ""
                } label: {
                    Image(systemName: "tag.fill").font(.system(size: 9))
                }
                .controlSize(.small)
                .tint(IRISTokens.aquaTint)
                .disabled(bulkTagInput.trimmingCharacters(in: .whitespaces).isEmpty)
                .help("Ajouter ce tag à toutes les memories visibles (\(filtered.count))")
                if let status = bulkTagStatus {
                    Text(status)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(status.hasPrefix("✅") ? .green : .red)
                        .lineLimit(1)
                }
            }

            // v1.198 — Sort by Picker (v1.269 — direction indicator)
            HStack(spacing: 4) {
                Picker("Sort", selection: $sortMode) {
                    Text("Newest").tag(MemorySortMode.newest)
                    Text("Oldest").tag(MemorySortMode.oldest)
                    Text("Type").tag(MemorySortMode.type)
                    Text("Name").tag(MemorySortMode.name)
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: 100)
                Image(systemName: sortIndicatorIcon)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary.opacity(0.6))
            }

            TextField("Search name/summary/content…", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(maxWidth: 240)
                .focused($searchFieldFocused)

            // v1.291 — Regex mode toggle
            Button { regexMode.toggle() } label: {
                Text(".*")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(regexMode ? IRISTokens.goldAccent : .secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(Capsule().fill(regexMode ? IRISTokens.goldAccent.opacity(0.15) : Color.clear))
            .help(regexMode ? "Désactiver le mode regex" : "Activer mode regex (NSRegularExpression case-insensitive)")

            // v1.264 — Hide tag cloud toggle (compact mode)
            Button { hideTagCloud.toggle() } label: {
                Image(systemName: hideTagCloud ? "tag.slash" : "tag.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help(hideTagCloud ? "Show tag cloud" : "Hide tag cloud (compact mode)")
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

    // v1.300 — Duplicates banner
    @ViewBuilder
    private var duplicatesBanner: some View {
        if duplicateCounts.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(IRISTokens.goldAccent)
                    .font(.system(size: 11))
                Text("\(duplicateCounts.count) noms dupliqués détectés (\(duplicateCounts.values.reduce(0, +)) memories au total)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.85))
                Spacer()
            }
            .padding(.horizontal, IRISTokens.spacing16)
            .padding(.vertical, 4)
            .background(IRISTokens.goldAccent.opacity(0.08))
        }
    }

    private var mainList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if filtered.isEmpty {
                        Text("Aucune mémoire correspondante.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(IRISTokens.spacing24)
                            .id("top")
                    } else {
                        let pinned = filtered.filter { isPinned($0) }
                        let unpinned = filtered.filter { !isPinned($0) }
                        if let firstPinned = pinned.first {
                            memoryRow(firstPinned, score: nil, rank: nil).id("top")
                            ForEach(pinned.dropFirst()) { memory in
                                memoryRow(memory, score: nil, rank: nil)
                            }
                            if !unpinned.isEmpty {
                                HStack(spacing: 4) {
                                    Rectangle().fill(Color.secondary.opacity(0.15)).frame(height: 1)
                                    Text("UNPINNED")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .tracking(1.4)
                                        .foregroundStyle(.secondary.opacity(0.6))
                                    Rectangle().fill(Color.secondary.opacity(0.15)).frame(height: 1)
                                }
                                .padding(.horizontal, IRISTokens.spacing8)
                                .padding(.vertical, 6)
                            }
                            ForEach(unpinned) { memory in
                                memoryRow(memory, score: nil, rank: nil)
                            }
                        } else if let firstUnpinned = unpinned.first {
                            memoryRow(firstUnpinned, score: nil, rank: nil).id("top")
                            ForEach(unpinned.dropFirst()) { memory in
                                memoryRow(memory, score: nil, rank: nil)
                            }
                        }
                    }
                }
                .padding(IRISTokens.spacing8)
            }
            .overlay(alignment: .bottomTrailing) {
                // v1.306 — Jump-to-top floating button
                Button {
                    withAnimation { proxy.scrollTo("top", anchor: .top) }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(IRISTokens.aquaTint)
                        .background(Circle().fill(.regularMaterial))
                }
                .buttonStyle(.plain)
                .padding(IRISTokens.spacing16)
                .help("Jump to top of memories list")
            }
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
                    HStack(spacing: 2) {
                        Text(String(format: "%.3f", score))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(IRISTokens.goldAccent)
                        Rectangle()
                            .fill(IRISTokens.goldAccent.opacity(0.6))
                            .frame(width: max(2, CGFloat(min(1.0, max(0.0, score)) * 40)), height: 3)
                            .cornerRadius(1.5)
                    }
                }
                Text(memory.createdAt, format: .dateTime.day().month().hour().minute())
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                // v1.233 — Expand/collapse full content
                Button {
                    if expandedIds.contains(memory.id) {
                        expandedIds.remove(memory.id)
                    } else {
                        expandedIds.insert(memory.id)
                    }
                } label: {
                    Image(systemName: expandedIds.contains(memory.id) ? "chevron.down.circle.fill" : "chevron.right.circle")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help(expandedIds.contains(memory.id) ? "Collapse content" : "Show full content")
                // v1.285 — Copy UUID to pasteboard
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(memory.id.uuidString, forType: .string)
                } label: {
                    Image(systemName: "number.circle")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help("Copier UUID au presse-papier (\(memory.id.uuidString.prefix(8))…)")
                // v1.208 — Copy content to pasteboard
                Button {
                    copyContent(memory)
                } label: {
                    Image(systemName: copyStatus[memory.id] == true ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 9))
                        .foregroundStyle(copyStatus[memory.id] == true ? .green : IRISTokens.aquaTint.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("Copier content de cette memory au presse-papier")
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
                highlightedText(memory.summary, search: searchText, baseFont: .system(size: 11), baseColor: .primary.opacity(0.85))
                    .lineLimit(2)
            }
            if expandedIds.contains(memory.id) && !memory.content.isEmpty {
                highlightedText(memory.content, search: searchText, baseFont: .system(size: 10, design: .monospaced), baseColor: .primary.opacity(0.75))
                    .padding(.top, 4)
                    .padding(.horizontal, 4)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(3)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 4).padding(.horizontal, IRISTokens.spacing8)
        .background(RoundedRectangle(cornerRadius: IRISTokens.cornerRadiusSmall).fill(.thinMaterial))
    }

    // MARK: — v1.251 Search-text highlighting

    private func highlightedText(_ source: String, search: String, baseFont: Font, baseColor: Color) -> Text {
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Text(source).font(baseFont).foregroundColor(baseColor)
        }
        var attr = AttributedString(source)
        attr.font = baseFont
        attr.foregroundColor = baseColor
        let lowSource = source.lowercased()
        let lowSearch = trimmed.lowercased()
        var cursor = lowSource.startIndex
        while cursor < lowSource.endIndex,
              let range = lowSource.range(of: lowSearch, range: cursor..<lowSource.endIndex) {
            if let attrRange = Range(range, in: attr) {
                attr[attrRange].backgroundColor = IRISTokens.goldAccent.opacity(0.3)
                attr[attrRange].foregroundColor = .primary
            }
            cursor = range.upperBound
        }
        return Text(attr)
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

    // MARK: — v1.208 Copy content

    private func copyContent(_ memory: Memory) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(memory.content, forType: .string)
        copyStatus[memory.id] = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copyStatus[memory.id] = nil
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
