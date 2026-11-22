//
//  UltimateAudioEngine.swift
//  VLCUltimateEngine
//
//  Created for VLC iOS Ultimate Workstation.
//  Swift 6 High-Performance Audio Coordinator: 14 DSP Modules, Low-Latency Mic I/O, Karaoke & Pitch Scoring.
//

import Foundation
import AVFoundation
import Accelerate
import Combine

// MARK: - Direct C-ABI Bindings for Audio DSP

@_silgen_name("ultimate_dsp_chain_create")
private func c_dsp_chain_create(_ sampleRate: Double, _ channels: Int32) -> OpaquePointer?

@_silgen_name("ultimate_dsp_chain_destroy")
private func c_dsp_chain_destroy(_ handle: OpaquePointer?)

@_silgen_name("ultimate_dsp_chain_set_parameters")
private func c_dsp_chain_set_parameters(_ handle: OpaquePointer?, _ params: UnsafePointer<UltimateDSPParameters>)

@_silgen_name("ultimate_dsp_chain_set_fft_size")
private func c_dsp_chain_set_fft_size(_ handle: OpaquePointer?, _ fftSize: Int32)

@_silgen_name("ultimate_dsp_chain_process_stereo")
private func c_dsp_chain_process_stereo(
    _ handle: OpaquePointer?,
    _ audioBuffer: UnsafeMutablePointer<Float>?,
    _ frameCount: Int,
    _ micBuffer: UnsafePointer<Float>?,
    _ mixedOutBuffer: UnsafeMutablePointer<Float>?,
    _ outMetrics: UnsafeMutablePointer<UltimateAudioMetrics>?
)

@_silgen_name("ultimate_pitch_detector_create")
private func c_pitch_detector_create(_ sampleRate: Double, _ bufferSize: Int) -> OpaquePointer?

@_silgen_name("ultimate_pitch_detector_destroy")
private func c_pitch_detector_destroy(_ handle: OpaquePointer?)

@_silgen_name("ultimate_pitch_detector_analyze_yin")
private func c_pitch_detector_analyze_yin(
    _ handle: OpaquePointer?,
    _ monoBuffer: UnsafePointer<Float>?,
    _ sampleCount: Int,
    _ outConfidence: UnsafeMutablePointer<Float>?
) -> Float

@_silgen_name("ultimate_chord_detector_analyze")
private func c_chord_detector_analyze(
    _ handle: OpaquePointer?,
    _ audioBuffer: UnsafePointer<Float>?,
    _ frameCount: Int,
    _ outChordName: UnsafeMutablePointer<CChar>?,
    _ maxLen: Int
)

@_silgen_name("ultimate_pitch_shifter_create")
private func c_pitch_shifter_create(_ sampleRate: Double, _ channels: Int32) -> OpaquePointer?

@_silgen_name("ultimate_pitch_shifter_destroy")
private func c_pitch_shifter_destroy(_ handle: OpaquePointer?)

@_silgen_name("ultimate_pitch_shifter_set_semitones")
private func c_pitch_shifter_set_semitones(_ handle: OpaquePointer?, _ semitones: Float)

@_silgen_name("ultimate_pitch_shifter_process")
private func c_pitch_shifter_process(
    _ handle: OpaquePointer?,
    _ inSamples: UnsafePointer<Float>?,
    _ inFrames: Int,
    _ outSamples: UnsafeMutablePointer<Float>?,
    _ maxOutFrames: Int
) -> Int

@_silgen_name("ultimate_audio_parse_autoeq_text")
private func c_audio_parse_autoeq_text(
    _ text: UnsafePointer<CChar>?,
    _ outBands: UnsafeMutablePointer<UltimateBiquadParam>?,
    _ maxBands: Int32
) -> Int32

// MARK: - Pitch Point Data for 2-Tier Piano Roll
public struct UltimatePitchPoint: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: TimeInterval
    public let accompanimentMidi: Float // target note (-1 if unvoiced)
    public let vocalMidi: Float        // singer note (-1 if unvoiced)
    public let isHit: Bool
    
    public init(timestamp: TimeInterval, accompanimentMidi: Float, vocalMidi: Float, isHit: Bool) {
        self.timestamp = timestamp
        self.accompanimentMidi = accompanimentMidi
        self.vocalMidi = vocalMidi
        self.isHit = isHit
    }
}

// MARK: - Ultimate Audio Engine Class
@MainActor
public final class UltimateAudioEngine: ObservableObject {
    
    public static let shared = UltimateAudioEngine()
    
    // MARK: - Published Real-Time Metrics
    @Published public private(set) var currentPeakDb: Float = -100.0
    @Published public private(set) var currentRmsDb: Float = -100.0
    @Published public private(set) var activeChord: String = "Cmaj"
    @Published public private(set) var detectedPitchHz: Float = 0.0
    @Published public private(set) var detectedMidiNote: Float = -1.0
    @Published public private(set) var vocalPitchHz: Float = 0.0
    @Published public private(set) var vocalMidiNote: Float = -1.0
    @Published public private(set) var karaokeScore: Float = 100.0
    @Published public private(set) var pitchHistory: [UltimatePitchPoint] = []
    
    // MARK: - Published DSP Parameters
    @Published public var dseeUltimateEnabled: Bool = true { didSet { updateParams() } }
    @Published public var dseeBlendAmount: Float = 0.85 { didSet { updateParams() } }
    @Published public var vinylProcessorEnabled: Bool = false { didSet { updateParams() } }
    @Published public var vinylIntensity: Float = 0.50 { didSet { updateParams() } }
    @Published public var dcPhaseMode: DCPhaseLinearizerMode = .dcPhaseLinearizer_Standard { didSet { updateParams() } }
    
    @Published public var spatialAudio714Enabled: Bool = false { didSet { updateParams() } }
    @Published public var spatialRoomSize: Float = 0.65 { didSet { updateParams() } }
    @Published public var dialogEnhancerEnabled: Bool = false { didSet { updateParams() } }
    
    @Published public var autoEqEnabled: Bool = false { didSet { updateParams() } }
    @Published public var nightModeEnabled: Bool = false { didSet { updateParams() } }
    @Published public var nightModeMakeupDb: Float = 4.0 { didSet { updateParams() } }
    
    @Published public var vocalRemoverEnabled: Bool = false { didSet { updateParams() } }
    @Published public var vocalRemoverStrength: Float = 0.90 { didSet { updateParams() } }
    @Published public var keyShiftSemitones: Int = 0 { didSet { updateKeyShift() } }
    @Published public var autoTuneEnabled: Bool = false { didSet { updateParams() } }
    @Published public var autoTuneSpeed: Float = 0.70 { didSet { updateParams() } }
    @Published public var harmonyEnabled: Bool = false { didSet { updateParams() } }
    @Published public var harmonyMix: Float = 0.50 { didSet { updateParams() } }
    
    @Published public var micGain: Float = 1.0 { didSet { updateParams() } }
    @Published public var micEchoDelayMs: Float = 180.0 { didSet { updateParams() } }
    @Published public var micReverbDecay: Float = 0.40 { didSet { updateParams() } }
    @Published public var isMicMonitoringActive: Bool = false
    
    // MARK: - Private Handles & State
    private var dspChainHandle: OpaquePointer?
    private var pitchDetectorHandle: OpaquePointer?
    private var pitchShifterHandle: OpaquePointer?
    private var micAudioEngine: AVAudioEngine?
    private let sampleRate: Double = 48000.0
    private var cancellables = Set<AnyCancellable>()
    
    // Scoring metrics
    private var totalPitchedFrames: Int = 0
    private var hitPitchedFrames: Int = 0
    
    // Temporary mono buffers for pitch analysis
    private var monoScratchBuffer = [Float](repeating: 0.0, count: 2048)
    private var micScratchBuffer = [Float](repeating: 0.0, count: 2048)
    
    private init() {
        self.dspChainHandle = c_dsp_chain_create(sampleRate, 2)
        self.pitchDetectorHandle = c_pitch_detector_create(sampleRate, 2048)
        self.pitchShifterHandle = c_pitch_shifter_create(sampleRate, 2)
        
        setupResourceObservers()
        updateParams()
    }
    
    deinit {
        stopMicMonitoring()
        if let h = dspChainHandle { c_dsp_chain_destroy(h) }
        if let h = pitchDetectorHandle { c_pitch_detector_destroy(h) }
        if let h = pitchShifterHandle { c_pitch_shifter_destroy(h) }
    }
    
    // MARK: - Resource Coordinator Integration
    
    private func setupResourceObservers() {
        NotificationCenter.default.publisher(for: .vlcUltimateAudioFFTResizeRequested)
            .sink { [weak self] notification in
                guard let self = self,
                      let windowSize = notification.userInfo?["windowSize"] as? Int,
                      let handle = self.dspChainHandle else { return }
                c_dsp_chain_set_fft_size(handle, Int32(windowSize))
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Parameter Synchronization
    
    private func updateParams() {
        guard let handle = dspChainHandle else { return }
        
        var params = UltimateDSPParameters()
        params.dsee_ultimate_enabled = dseeUltimateEnabled
        params.dsee_blend_amount = dseeBlendAmount
        params.vinyl_processor_enabled = vinylProcessorEnabled
        params.vinyl_intensity = vinylIntensity
        params.dc_phase_mode = dcPhaseMode
        
        params.spatial_audio_7_1_4_enabled = spatialAudio714Enabled
        params.spatial_room_size = spatialRoomSize
        params.dialog_enhancer_enabled = dialogEnhancerEnabled
        params.dialog_ducking_db = -4.5
        
        params.auto_eq_enabled = autoEqEnabled
        params.night_mode_enabled = nightModeEnabled
        params.night_mode_makeup_gain_db = nightModeMakeupDb
        
        params.vocal_remover_enabled = vocalRemoverEnabled
        params.vocal_remover_strength = vocalRemoverStrength
        params.key_shift_semitones = Int32(keyShiftSemitones)
        params.auto_tune_enabled = autoTuneEnabled
        params.auto_tune_speed = autoTuneSpeed
        params.harmony_enabled = harmonyEnabled
        params.harmony_mix = harmonyMix
        
        params.mic_gain = micGain
        params.mic_echo_delay_ms = micEchoDelayMs
        params.mic_reverb_decay = micReverbDecay
        
        c_dsp_chain_set_parameters(handle, &params)
    }
    
    private func updateKeyShift() {
        guard let shifter = pitchShifterHandle else { return }
        c_pitch_shifter_set_semitones(shifter, Float(keyShiftSemitones))
        updateParams()
    }
    
    // MARK: - Low-Latency Karaoke Microphone Engine (AVAudioEngine)
    
    public func startMicMonitoring() {
        guard micAudioEngine == nil else { return }
        
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setPreferredIOBufferDuration(0.005) // 5.33ms low latency
            try session.setActive(true)
            
            let engine = AVAudioEngine()
            let inputNode = engine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)
            
            inputNode.installTap(onBus: 0, bufferSize: 256, format: inputFormat) { [weak self] buffer, _ in
                guard let self = self,
                      let channelData = buffer.floatChannelData?[0] else { return }
                let frames = Int(buffer.frameLength)
                self.processMicFrames(samples: channelData, count: frames)
            }
            
            try engine.start()
            self.micAudioEngine = engine
            self.isMicMonitoringActive = true
        } catch {
            self.isMicMonitoringActive = false
        }
    }
    
    public func stopMicMonitoring() {
        micAudioEngine?.stop()
        micAudioEngine?.inputNode.removeTap(onBus: 0)
        micAudioEngine = nil
        isMicMonitoringActive = false
    }
    
    private func processMicFrames(samples: UnsafePointer<Float>, count: Int) {
        guard let detector = pitchDetectorHandle else { return }
        var confidence: Float = 0.0
        let f0 = c_pitch_detector_analyze_yin(detector, samples, count, &confidence)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if f0 > 50.0 && confidence > 0.65 {
                self.vocalPitchHz = f0
                self.vocalMidiNote = 69.0 + 12.0 * log2(f0 / 440.0)
            } else {
                self.vocalPitchHz = 0.0
                self.vocalMidiNote = -1.0
            }
        }
    }
    
    // MARK: - Real-Time Audio Tap Hook (Called from VLC)
    
    public func processAudioFrames(
        samples: UnsafeMutablePointer<Float>,
        frameCount: Int
    ) {
        guard let chain = dspChainHandle else { return }
        
        var metrics = UltimateAudioMetrics()
        c_dsp_chain_process_stereo(chain, samples, frameCount, nil, nil, &metrics)
        
        // Analyze Accompaniment Chord & Pitch
        if let detector = pitchDetectorHandle {
            var chordBuf = [CChar](repeating: 0, count: 16)
            c_chord_detector_analyze(detector, samples, frameCount, &chordBuf, 16)
            let chordStr = String(cString: chordBuf)
            
            // Downmix to mono for accompaniment pitch tracking
            let monoCount = min(frameCount, monoScratchBuffer.count)
            for i in 0..<monoCount {
                monoScratchBuffer[i] = 0.5 * (samples[i * 2] + samples[i * 2 + 1])
            }
            var conf: Float = 0.0
            let songF0 = c_pitch_detector_analyze_yin(detector, monoScratchBuffer, monoCount, &conf)
            
            // Sub-Bass Transient Taptic feedback
            if metrics.bass_transient_intensity > 0.08 {
                UltimateHapticEngine.shared.playBassTransient(
                    intensity: metrics.bass_transient_intensity,
                    sharpness: metrics.bass_transient_sharpness
                )
            }
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.currentPeakDb = metrics.peak_amplitude_db
                self.currentRmsDb = metrics.rms_energy_db
                self.activeChord = chordStr
                
                let songMidi: Float
                if songF0 > 50.0 && conf > 0.60 {
                    self.detectedPitchHz = songF0
                    songMidi = 69.0 + 12.0 * log2(songF0 / 440.0)
                    self.detectedMidiNote = songMidi
                } else {
                    songMidi = -1.0
                    self.detectedMidiNote = -1.0
                }
                
                // Karaoke Pitch Bar Recording & Scoring
                self.recordPitchComparison(accompanimentMidi: songMidi, singerMidi: self.vocalMidiNote)
            }
        }
    }
    
    private func recordPitchComparison(accompanimentMidi: Float, singerMidi: Float) {
        let isPitched = accompanimentMidi > 0.0
        let isHit: Bool
        if isPitched && singerMidi > 0.0 {
            // Pitch match tolerance: within 0.75 semitone (octave-invariant)
            let diff = abs(accompanimentMidi - singerMidi).truncatingRemainder(dividingBy: 12.0)
            isHit = (diff <= 0.75 || diff >= 11.25)
            totalPitchedFrames += 1
            if isHit { hitPitchedFrames += 1 }
        } else {
            isHit = false
        }
        
        if totalPitchedFrames > 0 {
            self.karaokeScore = Float(hitPitchedFrames) / Float(totalPitchedFrames) * 100.0
        }
        
        let point = UltimatePitchPoint(
            timestamp: Date().timeIntervalSinceReferenceDate,
            accompanimentMidi: accompanimentMidi,
            vocalMidi: singerMidi,
            isHit: isHit
        )
        
        pitchHistory.append(point)
        if pitchHistory.count > 120 { // Keep last 2 seconds of scroll
            pitchHistory.removeFirst()
        }
    }
    
    // MARK: - AutoEQ Import
    
    public func loadAutoEqProfile(text: String) {
        guard let chain = dspChainHandle else { return }
        var bands = [UltimateBiquadParam](repeating: UltimateBiquadParam(), count: Int(ULTIMATE_MAX_EQ_BANDS))
        
        text.withCString { cStr in
            let count = c_audio_parse_autoeq_text(cStr, &bands, Int32(ULTIMATE_MAX_EQ_BANDS))
            if count > 0 {
                self.autoEqEnabled = true
                self.updateParams()
            }
        }
    }
}
