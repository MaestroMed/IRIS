import SwiftUI

// IRIS Design Tokens — Liquid Glass palette.
// Cohérence visuelle avec MIND iOS (palette iris / aqua / sky soft).
// v0.0.2 — couleurs migrées vers Asset Catalog (App/Resources/Assets.xcassets/Colors/*).
//          Les hex fallback restent en `Color` extension privée si l'asset venait à manquer.
// v0.0.5+ → tokens partagés via SwiftPM package commun MIND ↔ IRIS si feasible.

public enum IRISTokens {
    // MARK: — Couleurs (Asset Catalog avec variants light/dark)

    /// Accent principal : iris doux. Utilisé pour les titres, les éléments actifs.
    public static let irisAccent = Color("IrisAccent", bundle: .main)

    /// Aqua tint : verts-bleus pour les états "vivants" (agents actifs, events frais).
    public static let aquaTint = Color("AquaTint", bundle: .main)

    /// Sky background : crème-bleuté pour les fonds, soft, non-fatigant.
    public static let skyBackground = Color("SkyBackground", bundle: .main)

    /// Gold subtle pour les highlights importants (rare, à utiliser avec parcimonie).
    public static let goldAccent = Color("GoldAccent", bundle: .main)

    /// Surface "carte" pour les panels — légèrement plus foncée que sky.
    public static let cardSurface = Color("CardSurface", bundle: .main)

    // MARK: — Typographie

    /// Famille pour les titres / display — Didone-style via .system(design: .serif).
    public static let displayFont: Font = .system(size: 96, weight: .ultraLight, design: .serif)

    /// Corps : system, lisible, neutre.
    public static let bodyFont: Font = .system(size: 14, weight: .regular, design: .default)

    /// Mono pour métriques / cost / versions.
    public static let monoFont: Font = .system(size: 12, weight: .light, design: .monospaced)

    // MARK: — Espacements (8-pt grid)

    public static let spacing4: CGFloat = 4
    public static let spacing8: CGFloat = 8
    public static let spacing16: CGFloat = 16
    public static let spacing24: CGFloat = 24
    public static let spacing32: CGFloat = 32
    public static let spacing48: CGFloat = 48

    // MARK: — Corner radii

    public static let cornerRadiusSmall: CGFloat = 8
    public static let cornerRadiusMedium: CGFloat = 12
    public static let cornerRadiusLarge: CGFloat = 20

    // MARK: — Layout NavigationSplitView (v0.0.2)

    public static let sidebarMinWidth: CGFloat = 240
    public static let sidebarIdealWidth: CGFloat = 280
    public static let sidebarMaxWidth: CGFloat = 320

    public static let inspectorMinWidth: CGFloat = 280
    public static let inspectorIdealWidth: CGFloat = 320
    public static let inspectorMaxWidth: CGFloat = 360
}

// MARK: — Fallback hex values (used si l'asset catalog n'est pas embarqué pour quelconque raison)
// Ne sont pas exposés publiquement — les vraies sources de vérité sont les colorsets.

extension Color {
    static let irisAccentFallback     = Color(red: 0.50, green: 0.45, blue: 0.85)
    static let aquaTintFallback       = Color(red: 0.75, green: 0.90, blue: 0.92)
    static let skyBackgroundFallback  = Color(red: 0.95, green: 0.96, blue: 0.99)
    static let goldAccentFallback     = Color(red: 0.79, green: 0.64, blue: 0.42)
    static let cardSurfaceFallback    = Color(red: 0.99, green: 0.99, blue: 1.00)
}
