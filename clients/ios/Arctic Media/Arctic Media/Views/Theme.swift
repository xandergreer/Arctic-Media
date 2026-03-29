import SwiftUI

// Matches the website's CSS variables exactly
extension Color {
    static let arcticBg      = Color(hex: "#080c14")
    static let arcticSurface = Color(hex: "#0d1526")
    static let arcticPrimary = Color(hex: "#4f8ef7")
    static let arcticText    = Color(hex: "#f0f4ff")
    static let arcticSub     = Color(hex: "#a8b4cc")
    static let arcticMuted   = Color(hex: "#5a6a85")
    static let arcticBorder  = Color(hex: "#1e2d45")

    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: h).scanHexInt64(&rgb)
        self.init(
            red:   Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >>  8) & 0xFF) / 255,
            blue:  Double( rgb        & 0xFF) / 255
        )
    }
}
