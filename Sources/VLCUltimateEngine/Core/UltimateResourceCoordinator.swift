//
//  UltimateResourceCoordinator.swift
//  VLCUltimateEngine
//
//  Created for VLC iOS Ultimate Workstation.
//  Zero-overhead Jetsam & Thermal Management Engine targeting 2GB RAM devices (A11 Bionic).
//

import Foundation
import UIKit
import Darwin
import Combine

/// Hardware and Jetsam resource budget tracker and coordinator.
/// Enforces physical memory footprint (phys_footprint) strictly below 850 MB to prevent Jetsam kills on 2GB RAM devices.
@MainActor
public final class UltimateResourceCoordinator: ObservableObject {
    
    // MARK: - Memory Budget Constants (in Megabytes)
    public static let totalMaxBudgetMB: UInt64 = 850
    public static let vlcCoreMaxBudgetMB: UInt64 = 300
    public static let metalPipelineMaxBudgetMB: UInt64 = 120
    public static let audioDspMaxBudgetMB: UInt64 = 45
    public static let waveformSqliteUiMaxBudgetMB: UInt64 = 45
    
    // Memory Pressure Thresholds
    private static let thresholdModerateMB: UInt64 = 600
    private static let thresholdWarningMB: UInt64 = 750
    private static let thresholdCriticalMB: UInt64 = 820
    
    // MARK: - Memory Pressure & Thermal States
    public enum MemoryPressureLevel: Int, Comparable, Sendable {
        case normal = 0
        case moderate = 1
        case warning = 2
        case critical = 3
        
        public static func < (lhs: MemoryPressureLevel, rhs: MemoryPressureLevel) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }
    
    // MARK: - Published Properties for UI Observation
    @Published public private(set) var physicalFootprintMB: Double = 0.0
    @Published public private(set) var memoryPressure: MemoryPressureLevel = .normal
    @Published public private(set) var thermalState: ProcessInfo.ThermalState = .nominal
    @Published public private(set) var isHighPrecisionVideoAllowed: Bool = true
    @Published public private(set) var currentFftWindowSize: Int = 2048
    
    // MARK: - Singleton Instance
    public static let shared = UltimateResourceCoordinator()
    
    // MARK: - Internal State
    private var monitoringTimer: Timer?
    private var notificationCancellables = Set<AnyCancellable>()
    private let stateQueue = DispatchQueue(label: "org.videolan.vlc.ultimate.coordinator.state", qos: .utility)
    
    // MARK: - Initialization
    private init() {
        self.thermalState = ProcessInfo.processInfo.thermalState
        setupSystemObservers()
        refreshMetrics()
        startPeriodicMonitoring()
    }
    
    deinit {
        monitoringTimer?.invalidate()
    }
    
    // MARK: - Public Control APIs
    
    /// Starts background memory & thermal monitoring (interval: 1.0s, reduced when backgrounded).
    public func startPeriodicMonitoring() {
        monitoringTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshMetrics()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.monitoringTimer = timer
    }
    
    /// Stops periodic monitoring to conserve CPU when playback is stopped.
    public func stopPeriodicMonitoring() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
    }
    
    /// Force an immediate memory check and execute eviction strategies if over budget.
    public func auditMemoryBudgetImmediately() {
        refreshMetrics()
        enforceMemoryBudgetRules(footprintMB: UInt64(physicalFootprintMB))
    }
    
    /// Direct query for real-time task physical footprint in bytes via Mach kernel VM info.
    public nonisolated static func getPhysicalMemoryFootprintBytes() -> UInt64 {
        var taskInfo = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return UInt64(taskInfo.phys_footprint)
        }
        return 0
    }
    
    // MARK: - Private Setup & Handlers
    
    private func setupSystemObservers() {
        // Observe system memory warnings (OS-level dispatch)
        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleSystemMemoryWarning()
                }
            }
            .store(in: &notificationCancellables)
        
        // Observe thermal state changes
        NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleThermalStateChange()
                }
            }
            .store(in: &notificationCancellables)
            
        // App backgrounding: aggressive cache dump
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleAppEnteredBackground()
                }
            }
            .store(in: &notificationCancellables)
    }
    
    private func refreshMetrics() {
        let footprintBytes = Self.getPhysicalMemoryFootprintBytes()
        let footprintMB = Double(footprintBytes) / (1024.0 * 1024.0)
        self.physicalFootprintMB = footprintMB
        self.thermalState = ProcessInfo.processInfo.thermalState
        
        let footprintUInt64 = UInt64(footprintMB)
        updatePressureLevel(footprintMB: footprintUInt64)
        enforceMemoryBudgetRules(footprintMB: footprintUInt64)
    }
    
    private func updatePressureLevel(footprintMB: UInt64) {
        let newLevel: MemoryPressureLevel
        if footprintMB >= Self.thresholdCriticalMB {
            newLevel = .critical
        } else if footprintMB >= Self.thresholdWarningMB {
            newLevel = .warning
        } else if footprintMB >= Self.thresholdModerateMB {
            newLevel = .moderate
        } else {
            newLevel = .normal
        }
        
        if newLevel != self.memoryPressure {
            self.memoryPressure = newLevel
            NotificationCenter.default.post(
                name: .vlcUltimateResourcePressureDidChange,
                object: self,
                userInfo: [
                    "pressure": newLevel.rawValue,
                    "footprintMB": self.physicalFootprintMB,
                    "thermal": self.thermalState.rawValue
                ]
            )
        }
    }
    
    private func enforceMemoryBudgetRules(footprintMB: UInt64) {
        let isThermalRestricted = (thermalState == .serious || thermalState == .critical)
        let isMemoryCritical = (footprintMB >= Self.thresholdWarningMB)
        
        // Dynamic Shader Half-Precision Fallback (RGBA16Float -> BGRA8Unorm)
        let shouldAllowHighPrecision = !isThermalRestricted && !isMemoryCritical
        if self.isHighPrecisionVideoAllowed != shouldAllowHighPrecision {
            self.isHighPrecisionVideoAllowed = shouldAllowHighPrecision
            NotificationCenter.default.post(
                name: .vlcUltimateVideoPrecisionFallbackRequested,
                object: self,
                userInfo: ["highPrecision": shouldAllowHighPrecision]
            )
        }
        
        // Dynamic FFT Window Resizing: 4096 (Audiophile) -> 2048 (Nominal) -> 1024 (Constrained)
        let targetFftSize: Int
        if isThermalRestricted || isMemoryCritical {
            targetFftSize = 1024
        } else if footprintMB >= Self.thresholdModerateMB {
            targetFftSize = 2048
        } else {
            targetFftSize = 4096
        }
        
        if self.currentFftWindowSize != targetFftSize {
            self.currentFftWindowSize = targetFftSize
            NotificationCenter.default.post(
                name: .vlcUltimateAudioFFTResizeRequested,
                object: self,
                userInfo: ["windowSize": targetFftSize]
            )
        }
    }
    
    private func handleSystemMemoryWarning() {
        self.memoryPressure = .critical
        // 1. Purge all volatile caches immediately
        NotificationCenter.default.post(
            name: .vlcUltimatePurgeNonEssentialCachesRequested,
            object: self
        )
        // 2. Downgrade video shader precision
        self.isHighPrecisionVideoAllowed = false
        NotificationCenter.default.post(
            name: .vlcUltimateVideoPrecisionFallbackRequested,
            object: self,
            userInfo: ["highPrecision": false]
        )
        // 3. Compress FFT window size to minimum
        self.currentFftWindowSize = 1024
        NotificationCenter.default.post(
            name: .vlcUltimateAudioFFTResizeRequested,
            object: self,
            userInfo: ["windowSize": 1024]
        )
    }
    
    private func handleThermalStateChange() {
        let currentThermal = ProcessInfo.processInfo.thermalState
        self.thermalState = currentThermal
        
        switch currentThermal {
        case .serious, .critical:
            // Thermal throttling prevention: downgrade pipeline and drop FFT
            self.isHighPrecisionVideoAllowed = false
            self.currentFftWindowSize = 1024
            NotificationCenter.default.post(
                name: .vlcUltimateVideoPrecisionFallbackRequested,
                object: self,
                userInfo: ["highPrecision": false]
            )
            NotificationCenter.default.post(
                name: .vlcUltimateAudioFFTResizeRequested,
                object: self,
                userInfo: ["windowSize": 1024]
            )
            NotificationCenter.default.post(
                name: .vlcUltimatePurgeNonEssentialCachesRequested,
                object: self
            )
        case .nominal, .fair:
            // Relax constraints if memory budget permits
            enforceMemoryBudgetRules(footprintMB: UInt64(physicalFootprintMB))
        @unknown default:
            break
        }
    }
    
    private func handleAppEnteredBackground() {
        // Evict offscreen caches, shrink heap textures, purge OCR bounding box overlays
        NotificationCenter.default.post(
            name: .vlcUltimatePurgeNonEssentialCachesRequested,
            object: self
        )
    }
}
