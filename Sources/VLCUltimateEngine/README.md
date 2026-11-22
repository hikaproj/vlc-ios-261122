# VLC Ultimate Workstation Engine (`VLCUltimateEngine`)
> **Architected, Customized & Maintained by [Hikaproj](https://hikaproj.com)**  
> 🌐 **Website:** [https://hikaproj.com](https://hikaproj.com)  
> 📩 **Contact:** [https://hikaproj.com/new/contact](https://hikaproj.com/new/contact)  
> 🐦 **X (Twitter):** [@hikaproj](https://x.com/hikaproj)

---

## 🌟 Executive Summary
`VLCUltimateEngine` は、オープンソースの `vlc-ios` をスタジオプロ機材水準へと昇華させる完全疎結合の拡張エンジンです。**Hikaproj** によって、RAM 2GB（A11 Bionic、iPhone 8 / X）端末において iOS の Jetsam 制限（850MB以下）を絶対遵守しながら常時60fpsで動作するよう設計・実装されています。

---

## 🛠️ Complete Feature Index (36 Modules)

### 🎵 Module A: Audio DSP & Karaoke Engine
- **DSEE Ultimate™**: 8k-16kHz harmonic waveshaping & 14k-22kHz air band restoration.
- **Vinyl Processor**: 25Hz tonearm resonance peaking EQ, tube saturation, -82dBFS noise.
- **DC Phase Linearizer**: 4-8 stage cascaded allpass filters reproducing Class-A amplifier bass punch.
- **Dolby 7.1.4ch Spatial Audio**: 12-channel virtual coordinates, HRTF convolution, FDN early reflection reverb.
- **Dialog Enhancer**: 1k-4kHz formant detection with dynamic -4.5dB side ducking.
- **AutoEQ Fast Parser**: C++ high-speed parser for ParametricEQ / GraphicEQ profiles.
- **Night Mode Dynamics**: 2ms lookahead compressor with 8:1 peak ratio and makeup gain.
- **Chord Recognition & FFT**: 2048-point Hanning window, 12-semitone Chroma PCP, 72-chord dictionary.
- **Sub-Bass Taptic Pulse**: 4th-order Butterworth 75Hz lowpass envelope transient detection.
- **Center Vocal Remover**: 120Hz mono bass preservation + center-channel cancellation.
- **2-Tier Real-Time Pitch Bar**: YIN algorithm + fractional parabolic interpolation F0 scoring.
- **Key Shift & Auto-Tune**: Granular pitch stretching (-6 to +6 st) + target scale snap.
- **Intelligent Auto-Harmonies**: Real-time chord-synced parallel 3-voice harmonies (+3rd, -3rd, -8ve).
- **Low-Latency Mic Mixer**: 5.33ms I/O buffer duration, plate delay & FDN reverb.

### 🎬 Module B: Metal Zero-Copy Video Pipeline
- **Dynamic HDR Tone Mapping**: Threadgroup shared-memory 256-bin histogram + ACES/Reinhard tone mapping.
- **Anime4K & Retro CRT**: Sobel gradient edge thinning, CAS anti-ringing, CRT scanlines & phosphor mask.
- **2-Screen Wipe Comparison**: Real-time A/B split-screen slider with tactile center detent.
- **Pinch Loupe & Minimap**: 1x-10x circular magnifying loupe + floating minimap viewport overlay.
- **Real-Time Stabilization & Deinterlace**: 16x16 macroblock optical flow + comb artifact detection.
- **PNG Snapshot Export**: High-quality lossless PNG image capture with applied shader pipeline.

### 📊 Module C: Waveform & Search Engine
- **Downsampled Waveform Cache**: AVAssetReader background parallel scanning with binary cache.
- **Silence Auto-Skip**: Automatic 2.5x speed acceleration across silence zones (< -45dB, > 0.4s).
- **Highlight Heatmap**: Short-term energy flux mapping to cold teal -> blazing orange gradient.
- **2-Point AB Repeat Drag**: Interactive boundary pins with magnetic haptic feedback.
- **SQLite FTS5 Subtitle Search**: C SQLite3 FTS5 virtual table (`tokenize='unicode61'`) instant text search.

### 📚 Module D: Subtitle & Study Engine
- **Bilingual Subtitles & Dictionary**: O(log N) binary search cue alignment + UIReferenceLibraryViewController.
- **In-Video Vision OCR**: VNRecognizeTextRequest (.accurate) on paused frames with bounding box selection.
- **Shadowing Recorder**: Turn-taking auto-record & alternate model/user voice playback.
- **Speed Step Trainer**: Incremental playback speed increase per completed loop (0.70x -> 1.00x).

### ⚙️ Module E: System Integration
- **Live Activities & Dynamic Island**: ActivityKit & AppIntents background controls.
- **CoreNFC Tag Automation**: Instant DSP profile & sleep timer loading/writing via NDEF tags.
- **Ultra Power Saver & Custom PiP**: Metal pipeline suspension + subtitle-burned PiP layer.
- **Local Wi-Fi Remote & 2-Device Sync**: Network.framework HTTP + RFC 6455 WebSocket with millisecond clock sync.
- **Lossless Trimmer & Baked Exporter**: AVAssetExportPresetPassthrough & offline DSP rendering.

### 🛡️ Module F: UX & Vault
- **Pro Gestures & Rotary Jog Dial**: Long-press 2.0x, 1-frame rotary jog dial, 2-finger swipe.
- **Per-Folder Settings Store**: Directory SHA-256 hash auto-save/restore SQLite store.
- **Calculator Camouflage Secret Vault**: Working calculator UI, `7749=` formula trigger, AES-GCM storage.
- **Sleep Fadeout Timer**: Final 60s logarithmic volume fade + 20kHz->250Hz lowpass cutoff sweep.

---

## 🤖 GitHub Actions IPA Builder
The repository includes [`.github/workflows/build-ipa.yml`](../../.github/workflows/build-ipa.yml) which automatically compiles and packages `VLC-Ultimate-Hikaproj.ipa` ready for AltStore, TrollStore, and Sideloadly.
