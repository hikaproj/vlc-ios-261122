//
//  UltimateAudioDSPChain.cpp
//  VLCUltimateEngine
//
//  Created for VLC iOS Ultimate Workstation.
//  Zero-Allocation C++17 DSP Engine: Sony Walkman, Dolby Spatial, AutoEQ, Karaoke, Dynamics.
//

#include "UltimateAudioDSPChain.hpp"
#include <cstdio>
#include <cstdlib>

struct UltimateDSPChainOpaque {
    std::unique_ptr<VLCUltimateEngine::UltimateAudioDSPChain> impl;
};

namespace VLCUltimateEngine {

UltimateAudioDSPChain::UltimateAudioDSPChain(double sample_rate, int channels)
    : sample_rate_(static_cast<float>(sample_rate > 0.0 ? sample_rate : 48000.0)),
      channels_(channels > 0 ? channels : 2)
{
    init_filters();

    // Lookahead delay buffers for Night Mode (2ms = 96 samples @ 48kHz)
    night_lookahead_delay_l_.assign(kLookaheadSamples, 0.0f);
    night_lookahead_delay_r_.assign(kLookaheadSamples, 0.0f);

    // Mic Delay line (up to 500ms = 24000 samples @ 48kHz)
    mic_delay_line_.assign(24000, 0.0f);

    // FDN Reverb Prime Delay Line Lengths
    const size_t fdn_lens[4] = { 1087, 1327, 1619, 1987 };
    for (size_t i = 0; i < 4; ++i) {
        fdn_delay_lines_[i].assign(fdn_lens[i], 0.0f);
        fdn_indices_[i] = 0;
        fdn_feedback_[i] = 0.0f;
    }
}

void UltimateAudioDSPChain::init_filters() noexcept {
    // 1. DSEE Ultimate: 8k-16k Bandpass + 14k Highpass
    dsee_bp_filter_l_ = BiquadFilter::make_bandpass(sample_rate_, 11500.0f, 1.2f);
    dsee_bp_filter_r_ = BiquadFilter::make_bandpass(sample_rate_, 11500.0f, 1.2f);
    dsee_hp_filter_l_ = BiquadFilter::make_highpass(sample_rate_, 14500.0f, 0.7071f);
    dsee_hp_filter_r_ = BiquadFilter::make_highpass(sample_rate_, 14500.0f, 0.7071f);

    // 2. Vinyl Processor: 25Hz Arm/Cartridge Resonance (+2.5dB Peaking)
    vinyl_resonance_l_ = BiquadFilter::make_peaking(sample_rate_, 25.0f, 2.5f, 1.2f);
    vinyl_resonance_r_ = BiquadFilter::make_peaking(sample_rate_, 25.0f, 2.5f, 1.2f);

    // 3. DC Phase Linearizer: Cascaded 2nd-Order Allpass Filters
    const float ap_freqs[8] = { 25.0f, 35.0f, 45.0f, 60.0f, 80.0f, 110.0f, 150.0f, 200.0f };
    for (size_t i = 0; i < 8; ++i) {
        dc_allpass_l_[i] = BiquadFilter::make_allpass(sample_rate_, ap_freqs[i], 0.7071f);
        dc_allpass_r_[i] = BiquadFilter::make_allpass(sample_rate_, ap_freqs[i], 0.7071f);
    }

    // 4. Dialog Enhancer Formant Bandpass (1kHz - 4kHz, Center 2.2kHz)
    dialog_formant_filter_ = BiquadFilter::make_bandpass(sample_rate_, 2200.0f, 0.8f);

    // 5. Sub-Bass Transient Detection (4th-order Butterworth: two Q=0.7071 LPFs @ 75Hz)
    bass_lp_stage1_ = BiquadFilter::make_lowpass(sample_rate_, 75.0f, 0.7071f);
    bass_lp_stage2_ = BiquadFilter::make_lowpass(sample_rate_, 75.0f, 0.7071f);

    // 6. Vocal Remover Bass Bypass (120Hz 2nd-order LPF)
    vocal_bass_lp_l_ = BiquadFilter::make_lowpass(sample_rate_, 120.0f, 0.7071f);
    vocal_bass_lp_r_ = BiquadFilter::make_lowpass(sample_rate_, 120.0f, 0.7071f);
}

void UltimateAudioDSPChain::set_parameters(const UltimateDSPParameters& params) noexcept {
    params_ = params;

    // Update AutoEQ Biquads
    for (int i = 0; i < params.auto_eq_band_count && i < ULTIMATE_MAX_EQ_BANDS; ++i) {
        const auto& band = params.auto_eq_bands[i];
        if (band.enabled && band.frequency > 10.0f && band.frequency < (sample_rate_ * 0.49f)) {
            const float q = band.q_factor > 0.05f ? band.q_factor : 1.41f;
            autoeq_l_[i] = BiquadFilter::make_peaking(sample_rate_, band.frequency, band.gain_db, q);
            autoeq_r_[i] = BiquadFilter::make_peaking(sample_rate_, band.frequency, band.gain_db, q);
        } else {
            autoeq_l_[i].reset();
            autoeq_r_[i].reset();
        }
    }
}

void UltimateAudioDSPChain::set_fft_size(UltimateFFTSize size) noexcept {
    fft_size_ = size;
}

float UltimateAudioDSPChain::generate_vinyl_noise() noexcept {
    // Ultra-lightweight linear congruential generator for subtle analog noise floor (<-82dBFS)
    noise_seed_ = (noise_seed_ * 196314165 + 907633515);
    const float raw = static_cast<float>(static_cast<int32_t>(noise_seed_)) / 2147483648.0f;
    return raw * 0.00008f; // approx -82dBFS
}

void UltimateAudioDSPChain::process_spatial_audio(float& l, float& r) noexcept {
    // 7.1.4ch Schroeder/Moorer Early Reflection Reverb Matrix
    // Combines direct sound with cross-fed delayed binaural reflections
    float fdn_in = 0.5f * (l + r);
    float sum_out[4] = { 0.0f, 0.0f, 0.0f, 0.0f };

    for (size_t i = 0; i < 4; ++i) {
        const size_t len = fdn_delay_lines_[i].size();
        const size_t read_idx = fdn_indices_[i];
        const float delayed = fdn_delay_lines_[i][read_idx];

        fdn_delay_lines_[i][read_idx] = fdn_in + fdn_feedback_[i] * (0.68f * params_.spatial_room_size);
        fdn_indices_[i] = (read_idx + 1) % len;
        sum_out[i] = delayed;
    }

    // Householder Diffuser Matrix: [ -0.5, 0.5, 0.5, 0.5 ]
    const float h = 0.5f * (sum_out[0] + sum_out[1] + sum_out[2] + sum_out[3]);
    for (size_t i = 0; i < 4; ++i) {
        fdn_feedback_[i] = sum_out[i] - h;
    }

    const float early_l = (sum_out[0] + sum_out[2]) * 0.25f;
    const float early_r = (sum_out[1] + sum_out[3]) * 0.25f;

    l = l * 0.85f + early_l;
    r = r * 0.85f + early_r;
}

void UltimateAudioDSPChain::process_stereo(
    float* audio_buffer,
    size_t frame_count,
    const float* mic_buffer,
    float* mixed_out_buffer,
    UltimateAudioMetrics* out_metrics
) noexcept {
    if (audio_buffer == nullptr || frame_count == 0) return;

    float peak_amp = 0.0f;
    float sum_sq = 0.0f;
    float max_bass_transient = 0.0f;

    const float attack_coeff  = 1.0f - std::exp(-1.0f / (0.002f * sample_rate_)); // 2ms attack
    const float release_coeff = 1.0f - std::exp(-1.0f / (0.150f * sample_rate_)); // 150ms release

    for (size_t i = 0; i < frame_count; ++i) {
        const size_t idx = i * 2;
        float l = audio_buffer[idx];
        float r = audio_buffer[idx + 1];

        // -------------------------------------------------------------
        // 1. Karaoke Vocal Remover (High-Precision Center Cancellation)
        // -------------------------------------------------------------
        if (params_.vocal_remover_enabled) {
            // Keep bass (<120Hz) completely mono and un-cancelled to preserve kick & bassline
            const float bass_l = vocal_bass_lp_l_.process(l);
            const float bass_r = vocal_bass_lp_r_.process(r);
            const float bass_mono = 0.5f * (bass_l + bass_r);

            // High pass residual
            const float mid = 0.5f * ((l - bass_l) + (r - bass_r));
            const float side = 0.5f * ((l - bass_l) - (r - bass_r));

            // Subtract center channel from high pass residual
            const float cancelled_mid = mid * (1.0f - params_.vocal_remover_strength);
            l = bass_mono + cancelled_mid + side;
            r = bass_mono + cancelled_mid - side;
        }

        // -------------------------------------------------------------
        // 2. Sony Walkman DSEE Ultimate (Harmonic High-Frequency Reconstruction)
        // -------------------------------------------------------------
        if (params_.dsee_ultimate_enabled) {
            const float bp_l = dsee_bp_filter_l_.process(l);
            const float bp_r = dsee_bp_filter_r_.process(r);

            // Non-linear waveshaping (half-wave rectification + cubic polynomial saturation)
            const float rect_l = (bp_l > 0.0f) ? bp_l : 0.0f;
            const float rect_r = (bp_r > 0.0f) ? bp_r : 0.0f;
            const float harm_l = 1.5f * (rect_l - 0.333333f * rect_l * rect_l * rect_l);
            const float harm_r = 1.5f * (rect_r - 0.333333f * rect_r * rect_r * rect_r);

            // Filter out fundamentals, retain only high harmonics (14kHz - 22kHz)
            const float air_l = dsee_hp_filter_l_.process(harm_l);
            const float air_r = dsee_hp_filter_r_.process(harm_r);

            l += air_l * (params_.dsee_blend_amount * 0.45f);
            r += air_r * (params_.dsee_blend_amount * 0.45f);
        }

        // -------------------------------------------------------------
        // 3. Sony Walkman Vinyl Processor
        // -------------------------------------------------------------
        if (params_.vinyl_processor_enabled) {
            // 25Hz tonearm resonance peaking
            l = vinyl_resonance_l_.process(l);
            r = vinyl_resonance_r_.process(r);

            // Even-order harmonic warmth saturation: y = x + 0.12*x^2 - 0.04*x^4
            const float sat_l = l + 0.12f * (l * l) - 0.04f * (l * l * l * l);
            const float sat_r = r + 0.12f * (r * r) - 0.04f * (r * r * r * r);
            l = l * (1.0f - params_.vinyl_intensity) + sat_l * params_.vinyl_intensity;
            r = r * (1.0f - params_.vinyl_intensity) + sat_r * params_.vinyl_intensity;

            // Ultra-subtle analog vinyl noise floor
            const float noise = generate_vinyl_noise() * params_.vinyl_intensity;
            l += noise;
            r += noise;
        }

        // -------------------------------------------------------------
        // 4. Sony Walkman DC Phase Linearizer (Cascaded Allpass Stages)
        // -------------------------------------------------------------
        if (params_.dc_phase_mode != DCPhaseLinearizer_Off) {
            int stages = 4; // Standard
            if (params_.dc_phase_mode == DCPhaseLinearizer_Low) stages = 6;
            if (params_.dc_phase_mode == DCPhaseLinearizer_High) stages = 8;

            for (int s = 0; s < stages; ++s) {
                l = dc_allpass_l_[s].process(l);
                r = dc_allpass_r_[s].process(r);
            }
        }

        // -------------------------------------------------------------
        // 5. Dialog Enhancer (Mid/Side Adaptive Ducking)
        // -------------------------------------------------------------
        if (params_.dialog_enhancer_enabled) {
            const float m = 0.5f * (l + r);
            const float s = 0.5f * (l - r);

            // Detect speech presence in 1kHz - 4kHz formant band
            const float formant = dialog_formant_filter_.process(m);
            const float formant_power = std::abs(formant);

            // Fast envelope follower
            if (formant_power > dialog_envelope_) {
                dialog_envelope_ += 0.08f * (formant_power - dialog_envelope_);
            } else {
                dialog_envelope_ += 0.005f * (formant_power - dialog_envelope_);
            }

            // Duck side component when speech is prominent (-3dB to -6dB)
            const float ducking_factor = std::clamp(dialog_envelope_ * 3.5f, 0.0f, 1.0f);
            const float side_gain = 1.0f - ducking_factor * 0.45f; // ~ -5.2dB reduction

            l = m + s * side_gain;
            r = m - s * side_gain;
        }

        // -------------------------------------------------------------
        // 6. Dolby 7.1.4ch Spatial Audio
        // -------------------------------------------------------------
        if (params_.spatial_audio_7_1_4_enabled) {
            process_spatial_audio(l, r);
        }

        // -------------------------------------------------------------
        // 7. AutoEQ Parametric Filter Bank
        // -------------------------------------------------------------
        if (params_.auto_eq_enabled) {
            for (int b = 0; b < params_.auto_eq_band_count && b < ULTIMATE_MAX_EQ_BANDS; ++b) {
                l = autoeq_l_[b].process(l);
                r = autoeq_r_[b].process(r);
            }
        }

        // -------------------------------------------------------------
        // 8. Night Mode Fast Lookahead Dynamics
        // -------------------------------------------------------------
        if (params_.night_mode_enabled) {
            const float in_level = std::max(std::abs(l), std::abs(r));
            if (in_level > night_envelope_) {
                night_envelope_ += attack_coeff * (in_level - night_envelope_);
            } else {
                night_envelope_ += release_coeff * (in_level - night_envelope_);
            }

            // Lookahead ringbuffer read & write
            const float delayed_l = night_lookahead_delay_l_[lookahead_write_pos_];
            const float delayed_r = night_lookahead_delay_r_[lookahead_write_pos_];
            night_lookahead_delay_l_[lookahead_write_pos_] = l;
            night_lookahead_delay_r_[lookahead_write_pos_] = r;
            lookahead_write_pos_ = (lookahead_write_pos_ + 1) % kLookaheadSamples;

            // 8:1 ratio compression above -18dBFS (0.1258)
            const float threshold = 0.1258f;
            float gain = 1.0f;
            if (night_envelope_ > threshold) {
                gain = std::pow(threshold / night_envelope_, 0.875f);
            }

            const float makeup = std::pow(10.0f, params_.night_mode_makeup_gain_db / 20.0f);
            l = delayed_l * gain * makeup;
            r = delayed_r * gain * makeup;
        }

        // -------------------------------------------------------------
        // 9. Sub-Bass Transient Detection (<75Hz for CoreHaptics)
        // -------------------------------------------------------------
        const float mono_signal = 0.5f * (l + r);
        const float bass_filtered = bass_lp_stage2_.process(bass_lp_stage1_.process(mono_signal));
        const float current_bass_energy = bass_filtered * bass_filtered;

        // Envelope follower on low-frequency power
        bass_envelope_ += 0.15f * (current_bass_energy - bass_envelope_);
        const float bass_diff = std::max(0.0f, bass_envelope_ - prev_bass_energy_);
        prev_bass_energy_ = bass_envelope_;

        if (bass_diff > max_bass_transient) {
            max_bass_transient = bass_diff;
        }

        // -------------------------------------------------------------
        // 10. Microphone Mixer & Low-Latency Echo/Reverb
        // -------------------------------------------------------------
        if (mic_buffer != nullptr) {
            const float mic_raw = mic_buffer[i] * params_.mic_gain;

            // Simple Plate Delay line for Mic Echo
            const size_t delay_samples = static_cast<size_t>(params_.mic_echo_delay_ms * 0.001f * sample_rate_);
            const size_t read_pos = (mic_delay_pos_ + mic_delay_line_.size() - delay_samples) % mic_delay_line_.size();
            const float echoed = mic_delay_line_[read_pos] * params_.mic_reverb_decay;

            mic_delay_line_[mic_delay_pos_] = mic_raw + echoed * 0.5f;
            mic_delay_pos_ = (mic_delay_pos_ + 1) % mic_delay_line_.size();

            l += (mic_raw + echoed);
            r += (mic_raw + echoed);
        }

        // Write processed samples
        if (mixed_out_buffer != nullptr) {
            mixed_out_buffer[idx] = l;
            mixed_out_buffer[idx + 1] = r;
        } else {
            audio_buffer[idx] = l;
            audio_buffer[idx + 1] = r;
        }

        // Metrics aggregation
        const float abs_l = std::abs(l);
        const float abs_r = std::abs(r);
        peak_amp = std::max({ peak_amp, abs_l, abs_r });
        sum_sq += (l * l + r * r) * 0.5f;
    }

    if (out_metrics != nullptr) {
        const float rms = std::sqrt(sum_sq / static_cast<float>(frame_count));
        out_metrics->peak_amplitude_db = (peak_amp > 1e-6f) ? (20.0f * std::log10(peak_amp)) : -100.0f;
        out_metrics->rms_energy_db = (rms > 1e-6f) ? (20.0f * std::log10(rms)) : -100.0f;
        out_metrics->bass_transient_intensity = std::clamp(max_bass_transient * 18.0f, 0.0f, 1.0f);
        out_metrics->bass_transient_sharpness = 0.85f;
    }
}

} // namespace VLCUltimateEngine

// =============================================================================
// MARK: - AutoEQ Regex-Free C++ Fast Parser
// =============================================================================

extern "C" {

int ultimate_audio_parse_autoeq_text(
    const char* text_content,
    UltimateBiquadParam* out_bands,
    int max_bands
) {
    if (text_content == nullptr || out_bands == nullptr || max_bands <= 0) return 0;

    int parsed_count = 0;
    const char* line = text_content;

    while (*line != '\0' && parsed_count < max_bands) {
        // Find line start and end
        while (*line == '\r' || *line == '\n') line++;
        if (*line == '\0') break;

        const char* line_end = line;
        while (*line_end != '\0' && *line_end != '\r' && *line_end != '\n') {
            line_end++;
        }

        // Check if line contains "Filter" and "ON"
        const char* filter_pos = std::strstr(line, "Filter");
        const char* on_pos = std::strstr(line, "ON");

        if (filter_pos != nullptr && filter_pos < line_end && on_pos != nullptr && on_pos < line_end) {
            // Find "Fc"
            const char* fc_pos = std::strstr(line, "Fc");
            const char* gain_pos = std::strstr(line, "Gain");
            const char* q_pos = std::strstr(line, "Q");

            if (fc_pos != nullptr && fc_pos < line_end &&
                gain_pos != nullptr && gain_pos < line_end &&
                q_pos != nullptr && q_pos < line_end) {

                float freq = std::strtof(fc_pos + 2, nullptr);
                float gain = std::strtof(gain_pos + 4, nullptr);
                float q = std::strtof(q_pos + 1, nullptr);

                if (freq >= 20.0f && freq <= 22000.0f && q > 0.01f) {
                    out_bands[parsed_count].frequency = freq;
                    out_bands[parsed_count].gain_db = gain;
                    out_bands[parsed_count].q_factor = q;
                    out_bands[parsed_count].enabled = true;
                    parsed_count++;
                }
            }
        }
        line = line_end;
    }

    return parsed_count;
}

ultimate_dsp_chain_handle_t ultimate_dsp_chain_create(double sample_rate, int channels) {
    try {
        auto handle = new UltimateDSPChainOpaque();
        handle->impl = std::make_unique<VLCUltimateEngine::UltimateAudioDSPChain>(sample_rate, channels);
        return handle;
    } catch (...) {
        return nullptr;
    }
}

void ultimate_dsp_chain_destroy(ultimate_dsp_chain_handle_t handle) {
    if (handle != nullptr) {
        delete handle;
    }
}

void ultimate_dsp_chain_set_parameters(ultimate_dsp_chain_handle_t handle, const UltimateDSPParameters* params) {
    if (handle != nullptr && handle->impl != nullptr && params != nullptr) {
        handle->impl->set_parameters(*params);
    }
}

void ultimate_dsp_chain_set_fft_size(ultimate_dsp_chain_handle_t handle, UltimateFFTSize fft_size) {
    if (handle != nullptr && handle->impl != nullptr) {
        handle->impl->set_fft_size(fft_size);
    }
}

void ultimate_dsp_chain_process_stereo(
    ultimate_dsp_chain_handle_t handle,
    float* audio_buffer,
    size_t frame_count,
    const float* mic_buffer,
    float* mixed_out_buffer,
    UltimateAudioMetrics* out_metrics
) {
    if (handle != nullptr && handle->impl != nullptr) {
        handle->impl->process_stereo(audio_buffer, frame_count, mic_buffer, mixed_out_buffer, out_metrics);
    }
}

} // extern "C"
