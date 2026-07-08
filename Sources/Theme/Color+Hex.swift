import SwiftUI

extension Color {
    /// Create a Color from a hex string like "#F59E0B", "F59E0B", or "#FFF".
    /// Returns `fallback` when the string can't be parsed.
    init(hex: String?, fallback: Color = .gray) {
        guard let hex else { self = fallback; return }
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }

        // Expand shorthand (#RGB -> #RRGGBB)
        if s.count == 3 {
            s = s.map { "\($0)\($0)" }.joined()
        }

        guard s.count == 6, let value = UInt64(s, radix: 16) else {
            self = fallback
            return
        }
        let r = Double((value & 0xFF0000) >> 16) / 255.0
        let g = Double((value & 0x00FF00) >> 8) / 255.0
        let b = Double(value & 0x0000FF) / 255.0
        self = Color(red: r, green: g, blue: b)
    }
}
