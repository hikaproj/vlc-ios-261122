//
//  UltimateAudioDSPChain.hpp
//  VLCUltimateEngine
//
//  Created for VLC iOS Ultimate Workstation.
//  Zero-Allocation C++17 DSP Engine: Sony Walkman, Dolby Spatial, AutoEQ, Karaoke, Dynamics.
//

#ifndef UltimateAudioDSPChain_hpp
#define UltimateAudioDSPChain_hpp

#include "UltimateAudioBridge.h"
#include <cmath>
#include <cstring>
#include <algorithm>
#include <vector>
#include <array>

namespace VLCUltimateEngine {

// MARK: - Direct Form II Transposed Biquad Filter
struct BiquadFilter {
    float b0 = 1.0f, b1 = 0.0f, b2 = 0.0f;
    float a1 = 0.0f, a2 = 0.0f;
    float s1 = 0.0f, s2 = 0.0f;

    inline void reset() noexcept {
        s1 = 0.0f;
        s2 = 0.0f;
    }

    inline float process(float in) noexcept {
        const float out = b0 * in + s1;
        s1 = b1 * in - a1 * out + s2;
        s2 = b2 * in - a2 * out;
        return out;
    }

    static BiquadFilter make_peaking(float sample_rate, float freq, float gain_db, float q) noexcept {
        BiquadFilter f;
        const float w0 = 2.0f * static_cast<float>(M_PI) * (freq / sample_rate);
        const float alpha = std::sin(w0) / (2.0f * q);
        const float A = std::pow(10.0f, gain_db / 40.0f);
        const float cos_w0 = std::cos(w0);

        const float a0 = 1.0f + alpha / A;
        f.b0 = (1.0f + alpha * A) / a0;
        f.b1 = (-2.0f * cos_w0) / a0;
        f.b2 = (1.0f - alpha * A) / a0;
        f.a1 = (-2.0f * cos_w0) / a0;
        f.a2 = (1.0f - alpha / A) / a0;
        return f;
    }

    static BiquadFilter make_lowpass(float sample_rate, float freq, float q = 0.7071f) noexcept {
        BiquadFilter f;
        const float w0 = 2.0f * static_cast<float>(M_PI) * (freq / sample_rate);
        const float alpha = std::sin(w0) / (2.0f * q);
        const float cos_w0 = std::cos(w0);

        const float a0 = 1.0f + alpha;
        f.b0 = ((1.0f - cos_w0) * 0.5f) / a0;
        f.b1 = (1.0f - cos_w0) / a0;
        f.b2 = ((1.0f - cos_w0) * 0.5f) / a0;
        f.a1 = (-2.0f * cos_w0) / a0;
        f.a2 = (1.0f - alpha) / a0;
        return f;
    }

    static BiquadFilter make_highpass(float sample_rate, float freq, float q = 0.7071f) noexcept {
        BiquadFilter f;
        const float w0 = 2.0f * static_cast<float>(M_PI) * (freq / sample_rate);
        const float alpha = std::sin(w0) / (2.0f * q);
        const float cos_w0 = std::cos(w0);

        const float a0 = 1.0f + alpha;
        f.b0 = ((1.0f + cos_w0) * 0.5f) / a0;
        f.b1 = (-(1.0f + cos_w0)) / a0;
        f.b2 = ((1.0f + cos_w0) * 0.5f) / a0;
        f.a1 = (-2.0f * cos_w0) / a0;
        f.a2 = (1.0f - alpha) / a0;
        return f;
    }

    static BiquadFilter make_bandpass(float sample_rate, float freq, float q) noexcept {
        BiquadFilter f;
        const float w0 = 2.0f * static_cast<float>(M_PI) * (freq / sample_rate);
        const float alpha = std::sin(w0) / (2.0f * q);
        const float cos_w0 = std::cos(w0);

        const float a0 = 1.0f + alpha;
        f.b0 = alpha / a0;
        f.b1 = 0.0f;
        f.b2 = -alpha / a0;
        f.a1 = (-2.0f * cos_w0) / a0;
        f.a2 = (1.0f - alpha) / a0;
        return f;
    }

    static BiquadFilter make_allpass(float sample_rate, float freq, float q) noexcept {
        BiquadFilter f;
        const float w0 = 2.0f * static_cast<float>(M_PI) * (freq / sample_rate);
        const float alpha = std::sin(w0) / (2.0f * q);
        const float cos_w0 = std::cos(w0);

        const float a0 = 1.0f + alpha;
        f.b0 = (1.0f - alpha) / a0;
        f.b1 = (-2.0f * cos_w0) / a0;
        f.b2 = (1.0f + alpha) / a0;
        f.a1 = (-2.0f * cos_w0) / a0;
        f.a2 = (1.0f - alpha) / a0;
        return f;
    }
};

// MARK: - Ultimate Audio DSP Chain Class
class UltimateAudioDSPChain {
public:
    UltimateAudioDSPChain(double sample_rate, int channels);
    ~UltimateAudioDSPChain() = default;

    void set_parameters(const UltimateDSPParameters& params) noexcept;
    void set_fft_size(UltimateFFTSize size) noexcept;

    void process_stereo(
        float* audio_buffer,
        size_t frame_count,
        const float* mic_buffer,
        float* mixed_out_buffer,
        UltimateAudioMetrics* out_metrics
    ) noexcept;

private:
    float sample_rate_;
    int channels_;
    UltimateDSPParameters params_{};
    UltimateFFTSize fft_size_ = UltimateFFTSize_2048;

    // Sony Walkman DSP Components
    BiquadFilter dsee_bp_filter_l_, dsee_bp_filter_r_;
    BiquadFilter dsee_hp_filter_l_, dsee_hp_filter_r_;
    BiquadFilter vinyl_resonance_l_, vinyl_resonance_r_;
    uint32_t noise_seed_ = 22222;

    // DC Phase Linearizer (up to 8 cascaded 2nd-order allpass filters per channel)
    std::array<BiquadFilter, 8> dc_allpass_l_;
    std::array<BiquadFilter, 8> dc_allpass_r_;

    // Dialog Enhancer Formant Bandpass & Envelope
    BiquadFilter dialog_formant_filter_;
    float dialog_envelope_ = 0.0f;

    // AutoEQ Filter Banks (10 bands stereo)
    std::array<BiquadFilter, ULTIMATE_MAX_EQ_BANDS> autoeq_l_;
    std::array<BiquadFilter, ULTIMATE_MAX_EQ_BANDS> autoeq_r_;

    // Night Mode Lookahead Dynamics
    float night_envelope_ = 0.0f;
    std::vector<float> night_lookahead_delay_l_;
    std::vector<float> night_lookahead_delay_r_;
    size_t lookahead_write_pos_ = 0;
    static constexpr size_t kLookaheadSamples = 96; // 2ms @ 48kHz

    // Sub-Bass Transient Detection (4th-order Butterworth: 2 cascaded 2nd-order LPF)
    BiquadFilter bass_lp_stage1_;
    BiquadFilter bass_lp_stage2_;
    float bass_envelope_ = 0.0f;
    float prev_bass_energy_ = 0.0f;

    // Vocal Remover Bass Bypass (120Hz 2nd-order LPF)
    BiquadFilter vocal_bass_lp_l_;
    BiquadFilter vocal_bass_lp_r_;

    // Mic Reverb & Plate FDN Delay Lines
    std::vector<float> mic_delay_line_;
    size_t mic_delay_pos_ = 0;
    std::array<std::vector<float>, 4> fdn_delay_lines_;
    std::array<size_t, 4> fdn_indices_{};
    std::array<float, 4> fdn_feedback_{};

    // Internal DSP helper routines
    void init_filters() noexcept;
    float generate_vinyl_noise() noexcept;
    void process_spatial_audio(float& l, float& r) noexcept;
};

} // namespace VLCUltimateEngine

#endif /* UltimateAudioDSPChain_hpp */
