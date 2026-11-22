//
//  UltimateLockFreeRingBuffer.cpp
//  VLCUltimateEngine
//
//  Created for VLC iOS Ultimate Workstation.
//  Implementation of C-ABI Bridge for Lock-Free RingBuffer and Group Delay compensation.
//

#include "UltimateAudioBridge.h"
#include "UltimateLockFreeRingBuffer.hpp"
#include <memory>

// Define opaque struct wrapper
struct UltimateRingBufferOpaque {
    std::unique_ptr<VLCUltimateEngine::UltimateLockFreeRingBuffer> impl;
};

extern "C" {

ultimate_ringbuffer_handle_t ultimate_ringbuffer_create(size_t capacity_frames, size_t channels) {
    if (channels == 0) {
        channels = 2; // Default to stereo
    }
    const size_t total_samples = capacity_frames * channels;
    
    try {
        auto handle = new UltimateRingBufferOpaque();
        handle->impl = std::make_unique<VLCUltimateEngine::UltimateLockFreeRingBuffer>(total_samples);
        return handle;
    } catch (...) {
        return nullptr;
    }
}

void ultimate_ringbuffer_destroy(ultimate_ringbuffer_handle_t handle) {
    if (handle != nullptr) {
        delete handle;
    }
}

size_t ultimate_ringbuffer_write(ultimate_ringbuffer_handle_t handle, const float* data, size_t sample_count) {
    if (handle == nullptr || handle->impl == nullptr) {
        return 0;
    }
    return handle->impl->write(data, sample_count);
}

size_t ultimate_ringbuffer_read(ultimate_ringbuffer_handle_t handle, float* destination, size_t sample_count) {
    if (handle == nullptr || handle->impl == nullptr) {
        return 0;
    }
    return handle->impl->read(destination, sample_count);
}

size_t ultimate_ringbuffer_available_read(const ultimate_ringbuffer_handle_t handle) {
    if (handle == nullptr || handle->impl == nullptr) {
        return 0;
    }
    return handle->impl->available_read();
}

size_t ultimate_ringbuffer_available_write(const ultimate_ringbuffer_handle_t handle) {
    if (handle == nullptr || handle->impl == nullptr) {
        return 0;
    }
    return handle->impl->available_write();
}

void ultimate_ringbuffer_reset(ultimate_ringbuffer_handle_t handle) {
    if (handle != nullptr && handle->impl != nullptr) {
        handle->impl->reset();
    }
}

double ultimate_audio_calculate_group_delay_ms(
    UltimateFFTSize current_fft_size,
    size_t rubber_band_latency_samples,
    double sample_rate
) {
    if (sample_rate <= 0.0) {
        sample_rate = 48000.0;
    }
    
    // Symmetrical STFT overlap-add 50% hop latency: (fft_size / 2) samples
    const double fft_latency_samples = static_cast<double>(current_fft_size) * 0.5;
    const double total_samples = fft_latency_samples + static_cast<double>(rubber_band_latency_samples);
    
    // Group delay in milliseconds
    return (total_samples / sample_rate) * 1000.0;
}

} // extern "C"
