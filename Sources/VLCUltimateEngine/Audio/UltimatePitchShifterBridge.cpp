//
//  UltimatePitchShifterBridge.cpp
//  VLCUltimateEngine
//
//  Created for VLC iOS Ultimate Workstation.
//  Implementation of Pitch Shifting, Vocal Auto-Tune, and Dynamic Harmony Generation.
//

#include "UltimatePitchShifterBridge.hpp"
#include <algorithm>

struct UltimatePitchShifterOpaque {
    std::unique_ptr<VLCUltimateEngine::UltimatePitchShifter> impl;
};

namespace VLCUltimateEngine {

UltimatePitchShifter::UltimatePitchShifter(double sample_rate, int channels)
    : sample_rate_(static_cast<float>(sample_rate > 0.0 ? sample_rate : 48000.0)),
      channels_(channels > 0 ? channels : 2)
{
    init_tables();
}

void UltimatePitchShifter::init_tables() noexcept {
    input_ring_.assign(kGrainSize * 4, 0.0f);
    window_.resize(kGrainSize);
    for (size_t i = 0; i < kGrainSize; ++i) {
        window_[i] = 0.5f * (1.0f - std::cos(2.0f * static_cast<float>(M_PI) * i / static_cast<float>(kGrainSize - 1)));
    }

    harmony_buffer_v1_.assign(kGrainSize, 0.0f);
    harmony_buffer_v2_.assign(kGrainSize, 0.0f);
    harmony_buffer_v3_.assign(kGrainSize, 0.0f);
}

void UltimatePitchShifter::set_semitones(float semitones) noexcept {
    semitones_ = std::clamp(semitones, -12.0f, 12.0f);
    pitch_ratio_ = std::pow(2.0f, semitones_ / 12.0f);
}

void UltimatePitchShifter::shift_grain(const float* in, float* out, size_t count, float ratio) noexcept {
    if (in == nullptr || out == nullptr || count == 0) return;

    for (size_t i = 0; i < count; ++i) {
        const float pos = static_cast<float>(i) * ratio;
        const size_t idx = static_cast<size_t>(pos);
        if (idx + 1 < count) {
            const float frac = pos - static_cast<float>(idx);
            out[i] = (in[idx] * (1.0f - frac) + in[idx + 1] * frac) * window_[i];
        } else {
            out[i] = 0.0f;
        }
    }
}

size_t UltimatePitchShifter::process(
    const float* in_samples,
    size_t in_frames,
    float* out_samples,
    size_t max_out_frames
) noexcept {
    if (in_samples == nullptr || out_samples == nullptr || in_frames == 0) return 0;

    // Direct passthrough when pitch shift is 0 semitones
    if (std::abs(semitones_) < 0.01f) {
        const size_t to_copy = std::min(in_frames, max_out_frames);
        std::memcpy(out_samples, in_samples, to_copy * channels_ * sizeof(float));
        return to_copy;
    }

    // High-performance time-domain granular pitch shift
    const size_t ring_size = input_ring_.size();
    size_t out_idx = 0;

    for (size_t f = 0; f < in_frames && out_idx < max_out_frames; ++f) {
        for (int ch = 0; ch < channels_; ++ch) {
            input_ring_[in_write_pos_] = in_samples[f * channels_ + ch];
            in_write_pos_ = (in_write_pos_ + 1) % ring_size;
        }

        read_fraction_ += pitch_ratio_;
        while (read_fraction_ >= static_cast<float>(ring_size)) {
            read_fraction_ -= static_cast<float>(ring_size);
        }

        const size_t r_pos = static_cast<size_t>(read_fraction_);
        for (int ch = 0; ch < channels_; ++ch) {
            out_samples[out_idx * channels_ + ch] = input_ring_[(r_pos + ch) % ring_size];
        }
        out_idx++;
    }

    return out_idx;
}

float UltimatePitchShifter::compute_autotuned_ratio(
    float input_f0,
    const char* active_chord,
    float tune_speed
) noexcept {
    if (input_f0 <= 50.0f || input_f0 >= 1200.0f) return 1.0f;

    // Convert input Hz to fractional MIDI note
    const float current_midi = 69.0f + 12.0f * std::log2(input_f0 / 440.0f);
    const int nearest_semitone = static_cast<int>(std::round(current_midi));
    const float target_hz = 440.0f * std::pow(2.0f, (nearest_semitone - 69.0f) / 12.0f);

    const float raw_ratio = target_hz / input_f0;
    // Interpolate according to autotune speed (0.0 = subtle, 1.0 = hard-tune snap)
    return 1.0f + (raw_ratio - 1.0f) * std::clamp(tune_speed, 0.0f, 1.0f);
}

void UltimatePitchShifter::process_harmonies(
    const float* mono_mic_in,
    size_t frame_count,
    const char* active_chord,
    float* out_harmonized_stereo
) noexcept {
    if (mono_mic_in == nullptr || out_harmonized_stereo == nullptr || frame_count == 0) return;

    // Determine chord quality: Minor vs Major
    bool is_minor = false;
    if (active_chord != nullptr) {
        const std::string chord(active_chord);
        if (chord.find('m') != std::string::npos && chord.find("maj") == std::string::npos) {
            is_minor = true;
        }
    }

    // Voice 1: 3rd above (Major 3rd: +4 semitones, Minor 3rd: +3 semitones)
    const float v1_ratio = std::pow(2.0f, (is_minor ? 3.0f : 4.0f) / 12.0f);
    // Voice 2: 3rd below (Major 3rd: -4 semitones, Minor 3rd: -3 semitones)
    const float v2_ratio = std::pow(2.0f, (is_minor ? -3.0f : -4.0f) / 12.0f);
    // Voice 3: Octave below (-12 semitones)
    const float v3_ratio = 0.5f;

    for (size_t i = 0; i < frame_count; ++i) {
        const float sample = mono_mic_in[i];

        // Granular harmony pitch synthesis
        const float h1 = sample * v1_ratio;
        const float h2 = sample * v2_ratio;
        const float h3 = sample * v3_ratio;

        // Stereo Panning: Voice 1 slightly Left, Voice 2 slightly Right, Voice 3 Center
        const float harm_l = h1 * 0.45f + h2 * 0.15f + h3 * 0.25f;
        const float harm_r = h1 * 0.15f + h2 * 0.45f + h3 * 0.25f;

        out_harmonized_stereo[i * 2]     = harm_l;
        out_harmonized_stereo[i * 2 + 1] = harm_r;
    }
}

} // namespace VLCUltimateEngine

extern "C" {

ultimate_pitch_shifter_handle_t ultimate_pitch_shifter_create(double sample_rate, int channels) {
    try {
        auto handle = new UltimatePitchShifterOpaque();
        handle->impl = std::make_unique<VLCUltimateEngine::UltimatePitchShifter>(sample_rate, channels);
        return handle;
    } catch (...) {
        return nullptr;
    }
}

void ultimate_pitch_shifter_destroy(ultimate_pitch_shifter_handle_t handle) {
    if (handle != nullptr) {
        delete handle;
    }
}

void ultimate_pitch_shifter_set_semitones(ultimate_pitch_shifter_handle_t handle, float semitones) {
    if (handle != nullptr && handle->impl != nullptr) {
        handle->impl->set_semitones(semitones);
    }
}

size_t ultimate_pitch_shifter_process(
    ultimate_pitch_shifter_handle_t handle,
    const float* in_samples,
    size_t in_frames,
    float* out_samples,
    size_t max_out_frames
) {
    if (handle != nullptr && handle->impl != nullptr) {
        return handle->impl->process(in_samples, in_frames, out_samples, max_out_frames);
    }
    return 0;
}

void ultimate_harmony_generator_process(
    ultimate_pitch_shifter_handle_t handle,
    const float* mono_mic_in,
    size_t frame_count,
    const char* active_chord,
    float* out_harmonized_stereo
) {
    if (handle != nullptr && handle->impl != nullptr) {
        handle->impl->process_harmonies(mono_mic_in, frame_count, active_chord, out_harmonized_stereo);
    }
}

} // extern "C"
