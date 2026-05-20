import SwiftUI

// IRIS Design Tokens — Liquid Glass palette.
// Cohérence visuelle avec MIND iOS (palette iris / aqua / sky soft).
// v0.0.1 — hardcoded. v0.0.2 → migration vers Asset Catalog avec variants light/dark.
// v0.0.5+ → tokens partagés via SwiftPM package commun MIND ↔ IRIS si feasible.

enum IRISTokens {
    // MARK: — Couleurs (palette iris / aqua / sky soft)

    /// Accent principal : iris doux. Utilisé pour les titres, les éléments actifs.
    static let irisAccent = Color(red: 0.50, green: 0.45, blue: 0.85)

    /// Aqua tint : verts-bleus pour les états "vivants" (agents actifs, events frais).
    static let aquaTint = Color(red: 0.75, green: 0.90, blue: 0.92)

    /// Sky background : crème-bleuté pour les fonds, soft, non-fatigant.
    static let skyBackground = Color(red: 0.95, green: 0.96, blue: 0.99)

    /// Gold subtle pour les highlights importants (rare, à utiliser avec parcimonie).
    static let goldAccent = Color(red: 0.79, green: 0.64, blue: 0.42)

    /// Surface "carte" pour les panels — légèrement plus foncée que sky.
    static let cardSurface = Color(red: 0.99, green: 0.99, blue: 1.0)

    // MARK: — Typographie

    /// Famille pour les titres / display — sera Didone-style en v0.0.2 via .system(design: .serif)
    /// Pour l'instant, system serif fallback.
    static let displayFont: Font = .system(size: 96, weight: .ultraLight, design: .serif)

    /// Corps : system, lisible, neutre.
    static let bodyFont: Font = .system(size: 14, weight: .regular, design: .default)

    /// Mono pour métriques / cost / versions.
    static let monoFont: Font = .system(size: 12, weight: .light, design: .monospaced)

    // MARK: — Espacements (8-pt grid)

    static let spacing4: CGFloat = 4
    static let spacing8: CGFloat = 8
    static let spacing16: CGFloat = 16
    static let spacing24: CGFloat = 24
    static let spacing32: CGFloat = 32
    static let spacing48: CGFloat = 48

    // MARK: — Corner radii

    static let cornerRadiusSmall: CGFloat = 8
    static let cornerRadiusMedium: CGFloat = 12
    static let cornerRadiusLarge: CGFloat = 20
}
