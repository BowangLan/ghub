import SwiftUI

enum DT {
    enum Color {
        static let emerald = SwiftUI.Color(red: 0.063, green: 0.725, blue: 0.506)
        static let red     = SwiftUI.Color(red: 0.937, green: 0.267, blue: 0.267)
        static let amber   = SwiftUI.Color(red: 0.961, green: 0.620, blue: 0.043)
        static let sky     = SwiftUI.Color(red: 0.055, green: 0.647, blue: 0.914)

        static let border       = SwiftUI.Color.primary.opacity(0.10)
        static let surface      = SwiftUI.Color.primary.opacity(0.05)
        static let surfaceHover = SwiftUI.Color.primary.opacity(0.09)
    }

    enum Radius {
        static let md: CGFloat = 10
        static let sm: CGFloat = 6
    }

    enum Spacing {
        static let h: CGFloat = 16
        static let v: CGFloat = 16
    }

    enum Size {
        static let footerBtnHeight: CGFloat = 26
    }
}
