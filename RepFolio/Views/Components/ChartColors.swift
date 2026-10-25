import SwiftUI
import UIKit

/// Chart series colors – fixed identity per data type, separately stepped for light & dark mode
/// (validated for color-vision deficiency separation).
extension Color {
    /// Gym / strength training (slot 1, blue)
    static let chartGym = Color(light: 0x2A78D6, dark: 0x3987E5)
    /// Running (slot 2, orange)
    static let chartRun = Color(light: 0xEB6834, dark: 0xD95926)
    /// Base metabolism / everyday energy (slot 3, aqua)
    static let chartBase = Color(light: 0x1BAF7A, dark: 0x199E70)

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: 1)
        })
    }
}
