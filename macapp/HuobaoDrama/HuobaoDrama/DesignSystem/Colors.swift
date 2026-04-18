import SwiftUI

// MARK: - Color Scheme Adaptive Colors
//
// 使用方式:
// - 直接通过 Color.bg0, Color.text0 等方式访问
// - 颜色会根据系统当前的 colorScheme 自动适配
// - 支持浅色模式 (light) 和黑暗模式 (dark)

extension Color {
    // MARK: - Backgrounds
    
    /// 主背景色 - 页面最底层背景
    static var bg0: Color {
        Color.adaptive(light: Color(hex: "#FFFFFF"), dark: Color(hex: "#1A1A1F"))
    }
    
    /// 次级背景色 - 侧边栏、次级区域
    static var bg1: Color {
        Color.adaptive(light: Color(hex: "#F8F9FC"), dark: Color(hex: "#232328"))
    }
    
    /// 三级背景色 - 输入框背景、悬停状态
    static var bg2: Color {
        Color.adaptive(light: Color(hex: "#F0F2F7"), dark: Color(hex: "#2C2C33"))
    }
    
    /// 四级背景色 - 分隔区域、标签背景
    static var bg3: Color {
        Color.adaptive(light: Color(hex: "#E8EBF2"), dark: Color(hex: "#36363D"))
    }
    
    /// 卡片背景色
    static var bgCard: Color {
        Color.adaptive(light: Color(hex: "#FFFFFF"), dark: Color(hex: "#25252B"))
    }
    
    /// 遮罩层背景色
    static var bgOverlay: Color {
        Color.adaptive(light: Color.black.opacity(0.4), dark: Color.black.opacity(0.6))
    }
    
    // MARK: - Text Colors
    
    /// 主文本色 - 标题、重要内容
    static var text0: Color {
        Color.adaptive(light: Color(hex: "#182132"), dark: Color(hex: "#F0F0F5"))
    }
    
    /// 次级文本色 - 正文内容
    static var text1: Color {
        Color.adaptive(light: Color(hex: "#374357"), dark: Color(hex: "#C5C5D0"))
    }
    
    /// 三级文本色 - 辅助说明
    static var text2: Color {
        Color.adaptive(light: Color(hex: "#6B7A96"), dark: Color(hex: "#8E8E9E"))
    }
    
    /// 四级文本色 - 占位符、禁用状态
    static var text3: Color {
        Color.adaptive(light: Color(hex: "#9AA3B8"), dark: Color(hex: "#6B6B7B"))
    }
    
    /// 禁用文本色
    static var textDisabled: Color {
        Color.adaptive(light: Color(hex: "#C4CAD9"), dark: Color(hex: "#4A4A55"))
    }
    
    /// 反色文本 - 用于深色背景上的文字
    static var textInverse: Color {
        Color.adaptive(light: Color(hex: "#FFFFFF"), dark: Color(hex: "#1A1A1F"))
    }
    
    // MARK: - Accent / Brand Colors
    
    /// 主品牌色
    static let accent = Color(hex: "#4C7DFF")
    
    /// 品牌色悬停状态
    static let accentHover = Color(hex: "#3A6AEF")
    
    /// 品牌色浅色背景
    static var accentLight: Color {
        Color.adaptive(light: Color(hex: "#EBF0FF"), dark: Color(hex: "#1E3A5F"))
    }
    
    // MARK: - Border Colors
    
    /// 主边框色
    static var border0: Color {
        Color.adaptive(light: Color(hex: "#E2E6F0"), dark: Color(hex: "#3A3A45"))
    }
    
    /// 次级边框色
    static var border1: Color {
        Color.adaptive(light: Color(hex: "#CDD3E3"), dark: Color(hex: "#4A4A55"))
    }
    
    // MARK: - Status Colors
    
    /// 成功色
    static let statusSuccess = Color(hex: "#22C55E")
    
    static var statusSuccessLight: Color {
        Color.adaptive(light: Color(hex: "#DCFCE7"), dark: Color(hex: "#1A3D28"))
    }
    
    /// 错误色
    static let statusError = Color(hex: "#EF4444")
    
    static var statusErrorLight: Color {
        Color.adaptive(light: Color(hex: "#FEE2E2"), dark: Color(hex: "#3D1A1A"))
    }
    
    /// 警告色
    static let statusWarning = Color(hex: "#F59E0B")
    
    static var statusWarningLight: Color {
        Color.adaptive(light: Color(hex: "#FEF3C7"), dark: Color(hex: "#3D3015"))
    }
    
    /// 信息色
    static let statusInfo = Color(hex: "#3B82F6")
    
    static var statusInfoLight: Color {
        Color.adaptive(light: Color(hex: "#DBEAFE"), dark: Color(hex: "#1A2D4D"))
    }
    
    // MARK: - Gradients
    
    static let gradientStart = Color(hex: "#667EEA")
    static let gradientEnd = Color(hex: "#764BA2")
    
    // MARK: - Helper Methods
    
    /// 创建自适应颜色（根据系统浅色/黑暗模式自动切换）
    static func adaptive(light: Color, dark: Color) -> Color {
        #if canImport(AppKit)
        return Color(
            NSColor(name: nil, dynamicProvider: { appearance in
                if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                    return NSColor(dark)
                }
                return NSColor(light)
            })
        )
        #else
        return light
        #endif
    }
    
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (1, 1, 0)
        }
        self.init(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
}

// MARK: - NSColor Extension

#if canImport(AppKit)
import AppKit

extension NSColor {
    convenience init(_ color: Color) {
        self.init(
            red: CGFloat(color.resolve(in: .init()).red),
            green: CGFloat(color.resolve(in: .init()).green),
            blue: CGFloat(color.resolve(in: .init()).blue),
            alpha: CGFloat(color.resolve(in: .init()).opacity)
        )
    }
}
#endif
