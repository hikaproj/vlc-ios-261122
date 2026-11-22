//
//  UltimatePitchAndChordDetector.hpp
//  VLCUltimateEngine
//
//  Created for VLC iOS Ultimate Workstation.
//  Ultra-Fast YIN Pitch Tracking and 12-Tone Chroma PCP Chord Recognition.
//

#ifndef UltimatePitchAndChordDetector_hpp
#define UltimatePitchAndChordDetector_hpp

#include "UltimateAudioBridge.h"
#include <vector>
#include <cmath>
#include <cstring>
#include <string>
#include <array>

namespace VLCUltimateEngine {

class UltimatePitchAndChordDetector {
public:
    UltimatePitchAndChordDetector(double sample_rate, size_t buffer_size);
    ~UltimatePitchAndChordDetector() = default;

    /// Analyzes mono buffer using YIN algorithm.
    /// Returns detected F0 in Hz (or -1.0f if unvoiced/silent) and writes confidence (0.0 - 1.0).
    float analyze_yin(const float* mono_buffer, size_t sample_count, float& out_confidence) noexcept;

    /// Analyzes audio for Chroma PCP and detects the dominant chord name.
    void analyze_chord(const float* audio_buffer, size_t frame_count, char* out_chord_name, size_t max_len) noexcept;

    /// Converts frequency in Hz to fractional MIDI note number.
    static inline float hz_to_midi_note(float hz) noexcept {
        if (hz <= 10.0f) return -1.0f;
        return 69.0f + 12.0f * std::log2(hz / 440.0f);
    }

private:
    float sample_rate_;
    size_t buffer_size_;
    std::vector<float> yin_buffer_;
    std::vector<float> hanning_window_;
    std::array<float, 12> chroma_vector_{};

    void init_tables() noexcept;
};

} // namespace VLCUltimateEngine

#endif /* UltimatePitchAndChordDetector_hpp */
