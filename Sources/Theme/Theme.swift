import SwiftUI
import UIKit

/// Central palette, spacing and type scale for the "Refined Native" restyle.
///
/// Warm-neutral surfaces, near-black ink, a single brand accent. Status and type
/// colours stay as concepts but are only ever used as dots / micro-labels — never
/// as tinted capsule fills. Every colour adapts to light/dark: the dark palette
/// mirrors the neutrals (ink canvas, lifted card) and lightens the accent/status
/// hues just enough to stay legible on a dark ground.
enum Theme {

    // MARK: Surfaces

    static let canvas      = dynamic(light: "#F4F2EE", dark: "#121316") // screen background
    static let card        = dynamic(light: "#FFFFFF", dark: "#1C1E23") // row / card surface
    static let groupFill   = dynamic(light: "#E7E3DC", dark: "#26282E") // container behind rows (hairlines)
    static let cardBorder  = dynamic(light: "#E2DDD4", dark: "#2D2F36") // group / card outline
    static let rowDivider  = dynamic(light: "#F0ECE4", dark: "#2A2C32") // hairline between detail rows

    // MARK: Ink

    static let ink         = dynamic(light: "#15171C", dark: "#F2F0EB") // titles, values
    static let secondary   = dynamic(light: "#7C766B", dark: "#A29B90") // destination, body
    static let tertiary    = dynamic(light: "#A39C90", dark: "#7E776C") // meta line, labels, counts
    static let haulierName  = dynamic(light: "#3D3A34", dark: "#D8D3CA") // haulier name text

    // MARK: Brand

    /// Burnt orange (the chosen direction; amber #F59E0B was the original).
    static let accent      = dynamic(light: "#C2410C", dark: "#E2683A")

    static let whatsApp    = Color(hex: "#25D366", fallback: .green)

    // MARK: Metrics

    static let cardCornerRadius: CGFloat = 8   // squared — chosen direction (18 = softer)
    static let cardPadding: CGFloat = 16
    static let detailRowVPadding: CGFloat = 12
    static let sectionGap: CGFloat = 22

    // MARK: Status

    /// Dot + label colour. Deepened from the originals for contrast; lightened in
    /// dark mode so the small labels stay readable.
    static func statusColor(_ status: JobStatus) -> Color {
        switch status {
        case .pending:   return dynamic(light: "#9A6A00", dark: "#D8A23C")
        case .booked:    return dynamic(light: "#2563EB", dark: "#5C8DEF")
        case .completed: return dynamic(light: "#15803D", dark: "#46B26A")
        }
    }

    // MARK: Job type

    static func typeColor(_ type: JobType) -> Color {
        switch type {
        case .delivery:   return dynamic(light: "#0E7490", dark: "#3BB0CE")
        case .collection: return dynamic(light: "#7C3AED", dark: "#A78BFA")
        }
    }

    // MARK: Dynamic colour

    /// A colour that resolves to `light`/`dark` hex by the current interface style.
    private static func dynamic(light: String, dark: String) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
    }
}

// MARK: - Type scale

extension Font {
    /// The "Refined Native" type scale. Sizes are the handoff design points, but
    /// nudged up slightly for legibility and — importantly — made to **scale with
    /// the system Dynamic Type setting** (via `UIFontMetrics`) so the app respects
    /// the user's preferred text size.
    ///   screen title 25/700 · card title 17.5/600 · body 14.5 · secondary 14 ·
    ///   meta 13.5 · section header 13/600 · status label 12.5/600 · type micro 10.5/700
    static func dc(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let base = UIFont.systemFont(ofSize: size + 1, weight: uiWeight(weight))
        return Font(UIFontMetrics(forTextStyle: .body).scaledFont(for: base))
    }

    private static func uiWeight(_ weight: Font.Weight) -> UIFont.Weight {
        switch weight {
        case .bold:      return .bold
        case .heavy:     return .heavy
        case .semibold:  return .semibold
        case .medium:    return .medium
        case .light:     return .light
        case .thin:      return .thin
        default:         return .regular
        }
    }
}
