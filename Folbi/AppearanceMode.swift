import SwiftUI

/// 外观模式：应用界面的明暗外观设置。
/// rawValue 持久化在 UserDefaults，属于持久合同；改动取值会破坏既有用户的设置。
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    /// 传给 `View.preferredColorScheme` 的值；跟随系统返回 nil。
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// “显示”菜单中的展示名。
    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
}
