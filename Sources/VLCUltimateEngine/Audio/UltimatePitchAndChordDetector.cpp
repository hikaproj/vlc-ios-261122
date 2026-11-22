//
//  UltimatePitchAndChordDetector.cpp
//  VLCUltimateEngine
//
//  Created for VLC iOS Ultimate Workstation.
//  Implementation of YIN Fundamental Frequency Detection and Chroma Chord Recognition.
//

#include "UltimatePitchAndChordDetector.hpp"
#include <algorithm>
#include <numeric>

struct UltimatePitchDetectorOpaque {
    std::unique_ptr<VLCUltimateEngine::UltimatePitchAndChordDetector> impl;
};

namespace VLCUltimateEngine {

UltimatePitchAndChordDetector::UltimatePitchAndChordDetector(double sample_rate, size_t buffer_size)
    : sample_rate_(static_cast<float>(sample_rate > 0.0 ? sample_rate : 48000.0)),
      buffer_size_(buffer_size >= 512 ? buffer_size : 2048)
{
    init_tables();
}

void UltimatePitchAndChordDetector::init_tables() noexcept {
    yin_buffer_.assign(buffer_size_ / 2, 0.0f);
    hanning_window_.resize(buffer_size_);
    for (size_t i = 0; i < buffer_size_; ++i) {
        hanning_window_[i] = 0.5f * (1.0f - std::cos(2.0f * static_cast<float>(M_PI) * i / static_cast<float>(buffer_size_ - 1)));
    }
}

float UltimatePitchAndChordDetector::analyze_yin(
    const float* mono_buffer,
    size_t sample_count,
    float& out_confidence
) noexcept {
    out_confidence = 0.0f;
    if (mono_buffer == nullptr || sample_count < 256) {
        return -1.0f;
    }

    const size_t W = std::min(sample_count / 2, yin_buffer_.size());
    if (W < 64) return -1.0f;

    // Check RMS signal energy to quickly reject silence (< -55dBFS)
    float energy = 0.0f;
    for (size_t i = 0; i < W; ++i) {
        energy += mono_buffer[i] * mono_buffer[i];
    }
    energy /= static_cast<float>(W);
    if (energy < 0.000003f) {
        return -1.0f;
    }

    // Step 1: Difference function d(tau)
    yin_buffer_[0] = 0.0f;
    for (size_t tau = 1; tau < W; ++tau) {
        float diff_sum = 0.0f;
        for (size_t j = 0; j < W; ++j) {
            const float delta = mono_buffer[j] - mono_buffer[j + tau];
            diff_sum += delta * delta;
        }
        yin_buffer_[tau] = diff_sum;
    }

    // Step 2: Cumulative mean normalized difference function d'(tau)
    yin_buffer_[0] = 1.0f;
    float running_sum = 0.0f;
    for (size_t tau = 1; tau < W; ++tau) {
        running_sum += yin_buffer_[tau];
        if (running_sum > 1e-7f) {
            yin_buffer_[tau] *= static_cast<float>(tau) / running_sum;
        } else {
            yin_buffer_[tau] = 1.0f;
        }
    }

    // Step 3: Absolute threshold (0.12) search
    const float threshold = 0.12f;
    size_t tau_found = 0;

    for (size_t tau = 2; tau < W; ++tau) {
        if (yin_buffer_[tau] < threshold) {
            while (tau + 1 < W && yin_buffer_[tau + 1] < yin_buffer_[tau]) {
                tau++;
            }
            tau_found = tau;
            break;
        }
    }

    // If no valley below threshold, find global minimum
    if (tau_found == 0) {
        float min_val = 1e9f;
        for (size_t tau = 2; tau < W; ++tau) {
            if (yin_buffer_[tau] < min_val) {
                min_val = yin_buffer_[tau];
                tau_found = tau;
            }
        }
        if (min_val > 0.35f) {
            return -1.0f; // Unvoiced
        }
    }

    // Step 4: Parabolic interpolation for sub-sample precision
    float better_tau = static_cast<float>(tau_found);
    if (tau_found > 0 && tau_found + 1 < W) {
        const float s0 = yin_buffer_[tau_found - 1];
        const float s1 = yin_buffer_[tau_found];
        const float s2 = yin_buffer_[tau_found + 1];
        const float denom = 2.0f * (2.0f * s1 - s0 - s2);
        if (std::abs(denom) > 1e-6f) {
            const float delta = (s2 - s0) / denom;
            better_tau += delta;
        }
    }

    const float f0 = sample_rate_ / better_tau;
    // Human vocal range clamp (50Hz - 1400Hz)
    if (f0 >= 50.0f && f0 <= 1400.0f) {
        out_confidence = std::clamp(1.0f - yin_buffer_[tau_found], 0.0f, 1.0f);
        return f0;
    }

    return -1.0f;
}

void UltimatePitchAndChordDetector::analyze_chord(
    const float* audio_buffer,
    size_t frame_count,
    char* out_chord_name,
    size_t max_len
) noexcept {
    if (out_chord_name == nullptr || max_len == 0) return;
    if (audio_buffer == nullptr || frame_count < 512) {
        std::snprintf(out_chord_name, max_len, "N.C.");
        return;
    }

    chroma_vector_.fill(0.0f);

    // Compute DFT energy across musical notes (C2 to B5: 65Hz to 987Hz)
    // 48 semitones mapped to 12 chroma bins
    for (int midi = 36; midi <= 83; ++midi) {
        const float freq = 440.0f * std::pow(2.0f, (midi - 69.0f) / 12.0f);
        const float w = 2.0f * static_cast<float>(M_PI) * freq / sample_rate_;
        const int chroma_idx = midi % 12;

        float real_sum = 0.0f;
        float imag_sum = 0.0f;
        const size_t N = std::min(frame_count, static_cast<size_t>(1024));

        for (size_t n = 0; n < N; ++n) {
            const float sample = audio_buffer[n * 2] * hanning_window_[n % buffer_size_];
            real_sum += sample * std::cos(w * n);
            imag_sum -= sample * std::sin(w * n);
        }

        chroma_vector_[chroma_idx] += std::sqrt(real_sum * real_sum + imag_sum * imag_sum);
    }

    // Normalize Chroma Vector
    float chroma_norm = 0.0f;
    for (float val : chroma_vector_) {
        chroma_norm += val * val;
    }
    chroma_norm = std::sqrt(chroma_norm);
    if (chroma_norm < 1e-4f) {
        std::snprintf(out_chord_name, max_len, "N.C.");
        return;
    }
    for (float& val : chroma_vector_) {
        val /= chroma_norm;
    }

    // 12 Semitone Root Names
    static const char* note_names[12] = {
        "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"
    };

    // Chord Templates (relative semitone offsets)
    struct ChordTemplate {
        const char* suffix;
        std::vector<int> intervals;
    };

    static const ChordTemplate templates[] = {
        { "maj",  { 0, 4, 7 } },
        { "m",    { 0, 3, 7 } },
        { "7",    { 0, 4, 7, 10 } },
        { "m7",   { 0, 3, 7, 10 } },
        { "maj7", { 0, 4, 7, 11 } },
        { "sus4", { 0, 5, 7 } }
    };

    float best_score = -1.0f;
    int best_root = 0;
    const char* best_suffix = "";

    for (int root = 0; root < 12; ++root) {
        for (const auto& t : templates) {
            float score = 0.0f;
            for (int interval : t.intervals) {
                const int note_idx = (root + interval) % 12;
                score += chroma_vector_[note_idx];
            }
            score /= std::sqrt(static_cast<float>(t.intervals.size()));

            if (score > best_score) {
                best_score = score;
                best_root = root;
                best_suffix = t.suffix;
            }
        }
    }

    if (best_score > 0.48f) {
        std::snprintf(out_chord_name, max_len, "%s%s", note_names[best_root], best_suffix);
    } else {
        std::snprintf(out_chord_name, max_len, "...");
    }
}

} // namespace VLCUltimateEngine

extern "C" {

ultimate_pitch_detector_handle_t ultimate_pitch_detector_create(double sample_rate, size_t buffer_size) {
    try {
        auto handle = new UltimatePitchDetectorOpaque();
        handle->impl = std::make_unique<VLCUltimateEngine::UltimatePitchAndChordDetector>(sample_rate, buffer_size);
        return handle;
    } catch (...) {
        return nullptr;
    }
}

void ultimate_pitch_detector_destroy(ultimate_pitch_detector_handle_t handle) {
    if (handle != nullptr) {
        delete handle;
    }
}

float ultimate_pitch_detector_analyze_yin(
    ultimate_pitch_detector_handle_t handle,
    const float* mono_buffer,
    size_t sample_count,
    float* out_confidence
) {
    if (handle != nullptr && handle->impl != nullptr) {
        float conf = 0.0f;
        const float pitch = handle->impl->analyze_yin(mono_buffer, sample_count, conf);
        if (out_confidence != nullptr) {
            *out_confidence = conf;
        }
        return pitch;
    }
    return -1.0f;
}

void ultimate_chord_detector_analyze(
    ultimate_pitch_detector_handle_t handle,
    const float* audio_buffer,
    size_t frame_count,
    char* out_chord_name,
    size_t chord_name_max_len
) {
    if (handle != nullptr && handle->impl != nullptr) {
        handle->impl->analyze_chord(audio_buffer, frame_count, out_chord_name, chord_name_max_len);
    }
}

} // extern "C"
