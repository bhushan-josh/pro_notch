import NotchCore
import SwiftUI

enum MediaTint {
    @MainActor
    static func color(_ style: MediaColorStyle, artwork: Color?) -> Color {
        switch style {
        case .artwork, .gradient: artwork ?? .white
        case .color: .accentColor
        case .mono: .white
        }
    }

    @MainActor
    static func shape(_ style: MediaColorStyle, artwork: Color?) -> AnyShapeStyle {
        switch style {
        case .gradient:
            let base = artwork ?? .white
            return AnyShapeStyle(LinearGradient(colors: [base, base.mix(with: .white, by: 0.5)], startPoint: .leading, endPoint: .trailing))
        default:
            return AnyShapeStyle(color(style, artwork: artwork))
        }
    }
}
