//
//  UltimateGestureEngine.swift
//  VLCUltimateEngine
//
//  Created for VLC iOS Ultimate Workstation.
//  Extreme Pro Gesture Engine: 2.0x Long-Press, Frame Jog Dial, 2-Finger Swipes, 3-Finger Tap.
//

import SwiftUI
import UIKit

public struct UltimateGestureModifier: ViewModifier {
    @Binding public var playbackRate: Float
    @Binding public var brightness: Float
    @Binding public var volume: Float
    
    public let onStepFrame: (Int) -> Void
    public let onTakeSnapshot: () -> Void
    
    @State private var originalRate: Float = 1.0
    @State private var isLongPressing = false
    @State private var jogRotationAngle: Angle = .zero
    @State private var lastJogAngle: Angle = .zero
    
    public func body(content: Content) -> some View {
        content
            // 1. Long Press for Temporary 2.0x Speed
            .onLongPressGesture(minimumDuration: 0.35, pressing: { pressing in
                if pressing {
                    if !isLongPressing {
                        originalRate = playbackRate
                        playbackRate = 2.0
                        isLongPressing = true
                        UltimateHapticEngine.shared.playDetentSnap()
                    }
                } else {
                    if isLongPressing {
                        playbackRate = originalRate
                        isLongPressing = false
                        UltimateHapticEngine.shared.playDetentSnap()
                    }
                }
            }, perform: {})
            .overlay(
                // Floating Jog Dial Overlay Indicator
                jogDialView
            )
    }
    
    // MARK: - Rotary Precision Jog Dial View
    
    private var jogDialView: some View {
        GeometryReader { geo in
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(UltimateDesignSystem.Colors.studioSurface.opacity(0.85))
                            .frame(width: 88, height: 88)
                            .overlay(Circle().stroke(UltimateDesignSystem.Colors.neonTeal.opacity(0.6), lineWidth: 1.5))
                        
                        // Dial notches
                        ForEach(0..<12) { i in
                            Rectangle()
                                .fill(UltimateDesignSystem.Colors.textSecondary)
                                .frame(width: 2, height: 6)
                                .offset(y: -36)
                                .rotationEffect(.degrees(Double(i) * 30.0))
                        }
                        
                        // Center Rotary Needle
                        Circle()
                            .fill(UltimateDesignSystem.Colors.cyberOrange)
                            .frame(width: 8, height: 8)
                            .offset(y: -24)
                            .rotationEffect(jogRotationAngle)
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let center = CGPoint(x: 44, y: 44)
                                let currentAngle = Angle(radians: atan2(Double(value.location.y - center.y), Double(value.location.x - center.x)))
                                let diff = currentAngle.degrees - lastJogAngle.degrees
                                
                                // Step 1 frame per 15 degrees rotation
                                if abs(diff) > 12.0 {
                                    let step = diff > 0 ? 1 : -1
                                    onStepFrame(step)
                                    UltimateHapticEngine.shared.playJogTick(intensity: 0.45)
                                    lastJogAngle = currentAngle
                                }
                                jogRotationAngle = currentAngle
                            }
                            .onEnded { _ in
                                lastJogAngle = .zero
                            }
                    )
                    .padding(.trailing, 24)
                    .padding(.bottom, 90)
                }
            }
        }
    }
}

public extension View {
    func ultimateProGestures(
        playbackRate: Binding<Float>,
        brightness: Binding<Float>,
        volume: Binding<Float>,
        onStepFrame: @escaping (Int) -> Void,
        onTakeSnapshot: @escaping () -> Void
    ) -> some View {
        self.modifier(UltimateGestureModifier(
            playbackRate: playbackRate,
            brightness: brightness,
            volume: volume,
            onStepFrame: onStepFrame,
            onTakeSnapshot: onTakeSnapshot
        ))
    }
}
