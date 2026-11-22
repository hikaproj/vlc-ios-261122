//
//  UltimateAudioBridge.h
//  VLCUltimateEngine
//
//  Created for VLC iOS Ultimate Workstation.
//  Strict C-ABI Boundary Header for Lock-Free DSP, Karaoke, and Pitch Synchronization.
//

#ifndef UltimateAudioBridge_h
#define UltimateAudioBridge_h

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// MARK: - Constants & Limits
// =============================================================================

#define ULTIMATE_AUDIO_MAX_CHANNELS 8
#define ULTIMATE_RINGBUFFER_DEFAULT_FRAMES 16384
#define ULTIMATE_AUDIO_CACHE_LINE_SIZE 64
#define ULTIMATE_MAX_EQ_BANDS 10

// =============================================================================
// MARK: - Data Types & Enums
// =============================================================================

typedef struct UltimateRingBufferOpaque* ultimate_ringbuffer_handle_t;
typedef struct UltimateDSPChainOpaque* ultimate_dsp_chain_handle_t;
typedef struct UltimatePitchDetectorOpaque* ultimate_pitch_detector_handle_t;
typedef struct UltimatePitchShifterOpaque* ultimate_pitch_shifter_handle_t;

typedef enum {
    UltimateAudioFormat_Float32_Interleaved = 0,
    UltimateAudioFormat_Float32_Planar      = 1,
    UltimateAudioFormat_Int16_Interleaved   = 2
} UltimateAudioFormat;

typedef enum {
    UltimateFFTSize_1024 = 1024,
    UltimateFFTSize_2048 = 2048,
    UltimateFFTSize_4096 = 4096
} UltimateFFTSize;

typedef enum {
    DCPhaseLinearizer_Off      = 0,
    DCPhaseLinearizer_Standard = 1,
    DCPhaseLinearizer_Low      = 2,
    DCPhaseLinearizer_High     = 3
} DCPhaseLinearizerMode;

typedef struct {
    uint32_t sample_rate;
    uint16_t channel_count;
    UltimateAudioFormat format;
    UltimateFFTSize initial_fft_size;
    float preferred_buffer_duration_sec;
} UltimateAudioConfig;

typedef struct {
    float peak_amplitude_db;
    float rms_energy_db;
    float bass_transient_intensity; // 0.0 - 1.0 for Haptic engine
    float bass_transient_sharpness;
    int detected_pitch_midi_note;   // Note index, -1 if unvoiced
    float detected_pitch_hz;
    float spectral_flux;
    char detected_chord_name[16];   // e.g. "Cmaj7", "Am", "G7"
    uint64_t underrun_count;
    uint64_t overrun_count;
} UltimateAudioMetrics;

typedef struct {
    float frequency;
    float gain_db;
    float q_factor;
    bool enabled;
} UltimateBiquadParam;

typedef struct {
    // Sony Walkman DSP
    bool dsee_ultimate_enabled;
    float dsee_blend_amount;        // 0.0 - 1.0
    bool vinyl_processor_enabled;
    float vinyl_intensity;          // 0.0 - 1.0
    DCPhaseLinearizerMode dc_phase_mode;
    
    // Dolby Sound DSP
    bool spatial_audio_7_1_4_enabled;
    float spatial_room_size;        // 0.0 - 1.0
    bool dialog_enhancer_enabled;
    float dialog_ducking_db;        // -3.0 to -6.0 dB
    
    // Professional Utilities
    bool auto_eq_enabled;
    UltimateBiquadParam auto_eq_bands[ULTIMATE_MAX_EQ_BANDS];
    int auto_eq_band_count;
    bool night_mode_enabled;
    float night_mode_makeup_gain_db;
    
    // Karaoke Engine
    bool vocal_remover_enabled;
    float vocal_remover_strength;   // 0.0 - 1.0
    int key_shift_semitones;        // -6 to +6
    bool auto_tune_enabled;
    float auto_tune_speed;          // 0.0 (subtle) to 1.0 (hard-tune)
    bool harmony_enabled;
    float harmony_mix;              // 0.0 - 1.0
    
    // Mic Reverb & Mixer
    float mic_gain;                 // 0.0 - 2.0
    float mic_echo_delay_ms;        // 0 - 500ms
    float mic_reverb_decay;         // 0.0 - 1.0
} UltimateDSPParameters;

// =============================================================================
// MARK: - RingBuffer C-ABI
// =============================================================================

ultimate_ringbuffer_handle_t ultimate_ringbuffer_create(size_t capacity_frames, size_t channels);
void ultimate_ringbuffer_destroy(ultimate_ringbuffer_handle_t handle);
size_t ultimate_ringbuffer_write(ultimate_ringbuffer_handle_t handle, const float* data, size_t sample_count);
size_t ultimate_ringbuffer_read(ultimate_ringbuffer_handle_t handle, float* destination, size_t sample_count);
size_t ultimate_ringbuffer_available_read(const ultimate_ringbuffer_handle_t handle);
size_t ultimate_ringbuffer_available_write(const ultimate_ringbuffer_handle_t handle);
void ultimate_ringbuffer_reset(ultimate_ringbuffer_handle_t handle);
double ultimate_audio_calculate_group_delay_ms(UltimateFFTSize current_fft_size, size_t rubber_band_latency_samples, double sample_rate);

// =============================================================================
// MARK: - DSP Chain & Processing C-ABI
// =============================================================================

ultimate_dsp_chain_handle_t ultimate_dsp_chain_create(double sample_rate, int channels);
void ultimate_dsp_chain_destroy(ultimate_dsp_chain_handle_t handle);
void ultimate_dsp_chain_set_parameters(ultimate_dsp_chain_handle_t handle, const UltimateDSPParameters* params);
void ultimate_dsp_chain_set_fft_size(ultimate_dsp_chain_handle_t handle, UltimateFFTSize fft_size);

/// Processes interleaved stereo audio in-place. Hard real-time safe (zero allocation, lock-free).
void ultimate_dsp_chain_process_stereo(
    ultimate_dsp_chain_handle_t handle,
    float* audio_buffer,
    size_t frame_count,
    const float* mic_buffer, // optional, NULL if no mic input
    float* mixed_out_buffer, // optional, NULL for in-place
    UltimateAudioMetrics* out_metrics
);

/// Fast AutoEQ Text Parser (Regex-free, executes in < 0.2ms)
/// Parses ParametricEQ / GraphicEQ text lines into biquad parameters.
int ultimate_audio_parse_autoeq_text(
    const char* text_content,
    UltimateBiquadParam* out_bands,
    int max_bands
);

// =============================================================================
// MARK: - Real-Time Pitch & Chord Detection C-ABI
// =============================================================================

ultimate_pitch_detector_handle_t ultimate_pitch_detector_create(double sample_rate, size_t buffer_size);
void ultimate_pitch_detector_destroy(ultimate_pitch_detector_handle_t handle);

/// Analyzes mono buffer using YIN algorithm for fundamental frequency F0 and MIDI note number.
float ultimate_pitch_detector_analyze_yin(
    ultimate_pitch_detector_handle_t handle,
    const float* mono_buffer,
    size_t sample_count,
    float* out_confidence
);

/// Analyzes stereo/mono buffer for Chroma PCP and detects chord name.
void ultimate_chord_detector_analyze(
    ultimate_pitch_detector_handle_t handle,
    const float* audio_buffer,
    size_t frame_count,
    char* out_chord_name,
    size_t chord_name_max_len
);

// =============================================================================
// MARK: - Pitch Shifter, Auto-Tune & Multi-Harmony C-ABI
// =============================================================================

ultimate_pitch_shifter_handle_t ultimate_pitch_shifter_create(double sample_rate, int channels);
void ultimate_pitch_shifter_destroy(ultimate_pitch_shifter_handle_t handle);
void ultimate_pitch_shifter_set_semitones(ultimate_pitch_shifter_handle_t handle, float semitones);
size_t ultimate_pitch_shifter_process(
    ultimate_pitch_shifter_handle_t handle,
    const float* in_samples,
    size_t in_frames,
    float* out_samples,
    size_t max_out_frames
);

/// Generates parallel harmonies (+3rd, -3rd, -8ve) matching target chord.
void ultimate_harmony_generator_process(
    ultimate_pitch_shifter_handle_t handle,
    const float* mono_mic_in,
    size_t frame_count,
    const char* active_chord,
    float* out_harmonized_stereo
);

#ifdef __cplusplus
}
#endif

#endif /* UltimateAudioBridge_h */
