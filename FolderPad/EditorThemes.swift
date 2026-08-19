import AppKit
import CodeEditSourceEditor
import SwiftUI

enum EditorThemeName: String, CaseIterable, Identifiable {
    case `default` = "Default"
    case github = "GitHub"
    case solarized = "Solarized"

    var id: String { rawValue }
}

enum EditorThemes {
    static func theme(_ name: EditorThemeName, colorScheme: ColorScheme) -> EditorTheme {
        let isDark = colorScheme == .dark
        switch (name, isDark) {
        case (.default, false):
            return make(
                background: 0xFFFFFF, text: 0x24292F, keyword: 0x9A1B4A,
                type: 0x005CC5, value: 0x032F62, number: 0x005CC5,
                string: 0x0A3069, comment: 0x6E7781, line: 0xF3F4F6, selection: 0xB6D7FF
            )
        case (.default, true):
            return make(
                background: 0x1E1E1E, text: 0xD4D4D4, keyword: 0xC586C0,
                type: 0x4EC9B0, value: 0x9CDCFE, number: 0xB5CEA8,
                string: 0xCE9178, comment: 0x6A9955, line: 0x292929, selection: 0x264F78
            )
        case (.github, false):
            return make(
                background: 0xFFFFFF, text: 0x1F2328, keyword: 0xCF222E,
                type: 0x8250DF, value: 0x0550AE, number: 0x0550AE,
                string: 0x0A3069, comment: 0x6E7781, line: 0xF6F8FA, selection: 0xB6D7FF
            )
        case (.github, true):
            return make(
                background: 0x0D1117, text: 0xE6EDF3, keyword: 0xFF7B72,
                type: 0xD2A8FF, value: 0x79C0FF, number: 0x79C0FF,
                string: 0xA5D6FF, comment: 0x8B949E, line: 0x161B22, selection: 0x264F78
            )
        case (.solarized, false):
            return make(
                background: 0xFDF6E3, text: 0x657B83, keyword: 0x859900,
                type: 0xB58900, value: 0x268BD2, number: 0xD33682,
                string: 0x2AA198, comment: 0x93A1A1, line: 0xEEE8D5, selection: 0xD7E4E8
            )
        case (.solarized, true):
            return make(
                background: 0x002B36, text: 0x839496, keyword: 0x859900,
                type: 0xB58900, value: 0x268BD2, number: 0xD33682,
                string: 0x2AA198, comment: 0x586E75, line: 0x073642, selection: 0x174A55
            )
        }
    }

    private static func make(
        background: Int,
        text: Int,
        keyword: Int,
        type: Int,
        value: Int,
        number: Int,
        string: Int,
        comment: Int,
        line: Int,
        selection: Int
    ) -> EditorTheme {
        let textAttribute = EditorTheme.Attribute(color: color(text))
        return EditorTheme(
            text: textAttribute,
            insertionPoint: color(text),
            invisibles: EditorTheme.Attribute(color: color(comment)),
            background: color(background),
            lineHighlight: color(line),
            selection: color(selection),
            keywords: EditorTheme.Attribute(color: color(keyword), bold: true),
            commands: EditorTheme.Attribute(color: color(keyword)),
            types: EditorTheme.Attribute(color: color(type)),
            attributes: EditorTheme.Attribute(color: color(type)),
            variables: EditorTheme.Attribute(color: color(text)),
            values: EditorTheme.Attribute(color: color(value)),
            numbers: EditorTheme.Attribute(color: color(number)),
            strings: EditorTheme.Attribute(color: color(string)),
            characters: EditorTheme.Attribute(color: color(string)),
            comments: EditorTheme.Attribute(color: color(comment), italic: true)
        )
    }

    private static func color(_ hex: Int) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
