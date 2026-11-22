//
//  UltimateDesignSystem.swift
//  VLCUltimateEngine
//
//  Created for VLC iOS Ultimate Workstation.
//  Ultra-lightweight Studio Design System with Physics Springs and Zero-Lag Glassmorphism.
//

import SwiftUI
import CoreHaptics

// MARK: - Ultimate Design System Tokens

public struct UltimateDesignSystem {
    
    // MARK: - Color Palette (Studio Darkroom Grade)
    public struct Colors {
        public static let obsidianBlack = Color(red: 0.043, green: 0.047, blue: 0.063)   // #0B0C10
        public static let studioSurface = Color(red: 0.082, green: 0.090, blue: 0.118)   // #15171E
        public static let studioBorder  = Color(red: 0.180, green: 0.200, blue: 0.250)   // #2E3340
        public static let electricCyan  = Color(red: 0.271, green: 0.635, blue: 0.620)   // #45A29E
        public static let neonTeal      = Color(red: 0.400, green: 0.988, blue: 0.945)   // #66FCF1
        public static let cyberOrange   = Color(red: 1.000, green: 0.420, blue: 0.208)   // #FF6B35
        public static let studioCrimson = Color(red: 0.902, green: 0.224, blue: 0.275)   // #E63946
        public static let meterGreen    = Color(red: 0.180, green: 0.800, blue: 0.443)   // #2ECC71
        public static let meterYellow   = Color(red: 0.945, green: 0.769, blue: 0.059)   // #F1C40F
        public static let textPrimary   = Color(red: 0.960, green: 0.960, blue: 0.980)
        public static let textSecondary = Color(red: 0.600, green: 0.630, blue: 0.700)
    }
    
    // MARK: - Physics Springs (Mandated by Directive 2)
    /// Exact mandated spring: mass: 0.8, stiffness: 280, damping: 22
    public static let ultimateSpring = Animation.interpolatingSpring(
        mass: 0.8,
        stiffness: 280,
        damping: 22
    )
    
    /// Snappy responsive spring for small knobs and toggles
    public static let snapSpring = Animation.interpolatingSpring(
        mass: 0.5,
        stiffness: 350,
        damping: 26
    )
    
    // MARK: - Typography (Monospaced for Numeric Precision)
    public struct Typography {
        public static let timecode = Font.system(.caption, design: .monospaced).weight(.semibold)
        public static let dialLabel = Font.system(size: 10, weight: .bold, design: .rounded)
        public static let dspTitle  = Font.system(size: 13, weight: .bold, design: .default)
        public static let meterText = Font.system(size: 9, weight: .heavy, design: .monospaced)
    }
}

// MARK: - Ultra-Lightweight Glassmorphic Card (Zero Heavy Blur)

public struct UltimateGlassCardModifier: ViewModifier {
    public var cornerRadius: CGFloat = 14
    public var borderColor: Color = UltimateDesignSystem.Colors.studioBorder
    public var fillOpacity: Double = 0.65
    
    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(UltimateDesignSystem.Colors.studioSurface.opacity(fillOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.18),
                                borderColor.opacity(0.4),
                                Color.black.opacity(0.3)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.0
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

public extension View {
    /// Applies high-performance zero-blur glassmorphism.
    func ultimateGlassCard(
        cornerRadius: CGFloat = 14,
        borderColor: Color = UltimateDesignSystem.Colors.studioBorder,
        fillOpacity: Double = 0.65
    ) -> some View {
        self.modifier(UltimateGlassCardModifier(
            cornerRadius: cornerRadius,
            borderColor: borderColor,
            fillOpacity: fillOpacity
        ))
    }
}
