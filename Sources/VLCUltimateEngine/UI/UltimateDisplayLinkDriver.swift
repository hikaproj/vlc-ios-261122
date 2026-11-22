//
//  UltimateDisplayLinkDriver.swift
//  VLCUltimateEngine
//
//  Created for VLC iOS Ultimate Workstation.
//  Strict 60fps CADisplayLink Driver decoupling real-time rendering from SwiftUI View evaluations.
//

import Foundation
import QuartzCore
import UIKit

/// Protocol for real-time 60fps synchronized subscribers (Waveform, Pitch Bar, Waterfall FFT).
public protocol UltimateDisplayLinkSubscriber: AnyObject {
    func displayLinkDidTick(timestamp: CFTimeInterval, targetTimestamp: CFTimeInterval)
}

/// Centralized CADisplayLink coordinator locked to 60Hz.
/// Eliminates redundant SwiftUI body evaluations while ensuring smooth, jitter-free visual rendering.
@MainActor
public final class UltimateDisplayLinkDriver: NSObject {
    
    public static let shared = UltimateDisplayLinkDriver()
    
    private var displayLink: CADisplayLink?
    private var subscribers = NSHashTable<AnyObject>.weakObjects()
    private var isPaused: Bool = true
    
    private override init() {
        super.init()
        setupNotifications()
    }
    
    deinit {
        displayLink?.invalidate()
    }
    
    // MARK: - Subscriber Management
    
    public func addSubscriber(_ subscriber: UltimateDisplayLinkSubscriber) {
        subscribers.add(subscriber)
        updateDisplayLinkState()
    }
    
    public func removeSubscriber(_ subscriber: UltimateDisplayLinkSubscriber) {
        subscribers.remove(subscriber)
        updateDisplayLinkState()
    }
    
    // MARK: - DisplayLink Control
    
    private func updateDisplayLinkState() {
        let hasActiveSubscribers = subscribers.allObjects.count > 0
        if hasActiveSubscribers && isPaused {
            startDisplayLink()
        } else if !hasActiveSubscribers && !isPaused {
            pauseDisplayLink()
        }
    }
    
    private func startDisplayLink() {
        if displayLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(handleDisplayLinkTick(_:)))
            // Lock strictly to 60fps on ProMotion (120Hz) as well as 60Hz displays to prevent thermal throttling
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
            link.add(to: .main, forMode: .common)
            self.displayLink = link
        }
        displayLink?.isPaused = false
        isPaused = false
    }
    
    private func pauseDisplayLink() {
        displayLink?.isPaused = true
        isPaused = true
    }
    
    @objc private func handleDisplayLinkTick(_ link: CADisplayLink) {
        let timestamp = link.timestamp
        let targetTimestamp = link.targetTimestamp
        
        for case let subscriber as UltimateDisplayLinkSubscriber in subscribers.allObjects {
            subscriber.displayLinkDidTick(timestamp: timestamp, targetTimestamp: targetTimestamp)
        }
    }
    
    // MARK: - App Lifecycle Handling
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
    
    @objc private func handleAppDidEnterBackground() {
        pauseDisplayLink()
    }
    
    @objc private func handleAppWillEnterForeground() {
        updateDisplayLinkState()
    }
}
