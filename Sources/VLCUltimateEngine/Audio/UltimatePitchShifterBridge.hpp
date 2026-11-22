//
//  UltimatePitchShifterBridge.hpp
//  VLCUltimateEngine
//
//  Created for VLC iOS Ultimate Workstation.
//  High-Performance Pitch Shifting, Vocal Auto-Tune, and Parallel Harmony Generator.
//

#ifndef UltimatePitchShifterBridge_hpp
#define UltimatePitchShifterBridge_hpp

#include "UltimateAudioBridge.h"
#include <vector>
#include <cmath>
#include <cstring>
#include <string>

namespace VLCUltimateEngine {

class UltimatePitchShifter {
public:
    UltimatePitchShifter(double sample_rate, int channels);
    ~UltimatePitchShifter() = default;

    void set_semitones(float semitones) noexcept;

    /// Time-stretch & pitch-shift audio buffer.
    size_t process(
        const float* in_samples,
        size_t in_frames,
        float* out_samples,
        size_t max_out_frames
    ) noexcept;

    /// Auto-Tunes detected vocal frequency towards nearest scale/chord target.
    float compute_autotuned_ratio(float input_f0, const char* active_chord, float tune_speed) noexcept;

    /// Parallel 3-Voice Harmony Generator (+3rd, -3rd, -8ve) matching active chord.
    void process_harmonies(
        const float* mono_mic_in,
        size_t frame_count,
        const char* active_chord,
        float* out_harmonized_stereo
    ) noexcept;

private:
    float sample_rate_;
    int channels_;
    float semitones_ = 0.0f;
    float pitch_ratio_ = 1.0f;

    // Granular overlap-add state
    static constexpr size_t kGrainSize = 1024;
    static constexpr size_t kHopSize = 256;
    std::vector<float> input_ring_;
    size_t in_write_pos_ = 0;
    float read_fraction_ = 0.0f;
    std::vector<float> window_;

    // Multi-voice harmony delay and grain buffers
    std::vector<float> harmony_buffer_v1_;
    std::vector<float> harmony_buffer_v2_;
    std::vector<float> harmony_buffer_v3_;

    void init_tables() noexcept;
    void shift_grain(const float* in, float* out, size_t count, float ratio) noexcept;
};

} // namespace VLCUltimateEngine

#endif /* UltimatePitchShifterBridge_hpp */
