import SwiftUI
import SwiftData

/// v1.342 — Edit 3rd-party service connections for a ProjectRecord
/// (Vercel, Supabase, Cloudflare, Resend, client email, custom links).
struct ProjectStackEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var project: ProjectRecord

    // Local edit state for custom links (parsed/serialized to JSON)
    @State private var customLinks: [CustomLink] = []
    @State private var newLinkLabel: String = ""
    @State private var newLinkURL: String = ""

    struct CustomLink: Identifiable, Codable, Equatable {
        var id = UUID()
        var label: String
        var url: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: IRISTokens.spacing16) {
            // Header
            HStack {
                Image(systemName: "rectangle.connected.to.line.below")
                    .foregroundStyle(IRISTokens.aquaTint)
                    .font(.system(size: 18))
                Text("Stack & Services — \(project.displayName)")
                    .font(.system(size: 20, weight: .light, design: .serif))
                Spacer()
                Button("Fermer") { dismiss() }.keyboardShortcut(.cancelAction)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: IRISTokens.spacing16) {
                    // 6 service fields
                    serviceField(icon: "triangle.fill", color: .black,
                        label: "Vercel deployment URL", placeholder: "https://vercel.com/...",
                        binding: Binding(get: { project.vercelURL ?? "" }, set: { project.vercelURL = $0.isEmpty ? nil : $0 }))

                    serviceField(icon: "leaf.fill", color: .green,
                        label: "Supabase project URL", placeholder: "https://supabase.com/dashboard/project/...",
                        binding: Binding(get: { project.supabaseURL ?? "" }, set: { project.supabaseURL = $0.isEmpty ? nil : $0 }))

                    serviceField(icon: "cloud.fill", color: .orange,
                        label: "Cloudflare zone", placeholder: "example.com",
                        binding: Binding(get: { project.cloudflareZone ?? "" }, set: { project.cloudflareZone = $0.isEmpty ? nil : $0 }))

                    serviceField(icon: "envelope.badge.fill", color: .purple,
                        label: "Resend sender domain", placeholder: "mail.example.com",
                        binding: Binding(get: { project.resendDomain ?? "" }, set: { project.resendDomain = $0.isEmpty ? nil : $0 }))

                    serviceField(icon: "person.crop.circle.fill", color: IRISTokens.irisAccent,
                        label: "Client email", placeholder: "contact@client.com",
                        binding: Binding(get: { project.clientEmail ?? "" }, set: { project.clientEmail = $0.isEmpty ? nil : $0 }))

                    Divider().padding(.vertical, IRISTokens.spacing8)

                    // Custom links section
                    VStack(alignment: .leading, spacing: 6) {
                        Text("CUSTOM LINKS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(1.4)
                            .foregroundStyle(.secondary)

                        ForEach(customLinks) { link in
                            HStack(spacing: 6) {
                                Image(systemName: "link")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                Text(link.label).font(.system(size: 12, weight: .medium))
                                Text(link.url).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                                Spacer()
                                Button {
                                    customLinks.removeAll { $0.id == link.id }
                                    persistCustomLinks()
                                } label: {
                                    Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(.red.opacity(0.6))
                                }.buttonStyle(.plain)
                            }
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 4).fill(.thinMaterial))
                        }

                        // Add new link
                        HStack(spacing: 6) {
                            TextField("Label (Notion, Linear, …)", text: $newLinkLabel)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                                .frame(maxWidth: 180)
                            TextField("https://…", text: $newLinkURL)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                            Button {
                                let label = newLinkLabel.trimmingCharacters(in: .whitespaces)
                                let url = newLinkURL.trimmingCharacters(in: .whitespaces)
                                guard !label.isEmpty, !url.isEmpty else { return }
                                customLinks.append(CustomLink(label: label, url: url))
                                newLinkLabel = ""
                                newLinkURL = ""
                                persistCustomLinks()
                            } label: { Image(systemName: "plus.circle.fill") }
                            .buttonStyle(.plain)
                            .disabled(newLinkLabel.trimmingCharacters(in: .whitespaces).isEmpty || newLinkURL.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Enregistrer") {
                    persistCustomLinks()
                    try? modelContext.save()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(IRISTokens.spacing24)
        .frame(minWidth: 600, idealWidth: 720, minHeight: 480, idealHeight: 580)
        .onAppear { loadCustomLinks() }
    }

    private func serviceField(icon: String, color: Color, label: String, placeholder: String, binding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12)).foregroundStyle(color)
                Text(label).font(.system(size: 12, weight: .medium))
            }
            TextField(placeholder, text: binding)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .font(.system(size: 12, design: .monospaced))
        }
    }

    private func loadCustomLinks() {
        guard let data = project.customLinksJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([CustomLink].self, from: data) else {
            customLinks = []
            return
        }
        customLinks = decoded
    }

    private func persistCustomLinks() {
        if let data = try? JSONEncoder().encode(customLinks),
           let str = String(data: data, encoding: .utf8) {
            project.customLinksJSON = str
        }
    }
}
