//
//  UltimateVideoTypes.h
//  VLCUltimateEngine
//
//  Created for VLC iOS Ultimate Workstation.
//  Shared types between C++, Swift, and Metal shaders for UltimateVideoPipeline.
//

#ifndef UltimateVideoTypes_h
#define UltimateVideoTypes_h

#include <simd/simd.h>

// Tone mapping mode
typedef enum {
    ToneMap_ACES     = 0,
    ToneMap_Reinhard = 1
} UltimateToneMapMode;

// Parameters passed to Dynamic HDR Tone Mapping shader
struct UltimateToneMapParams {
    float average_luminance;
    float max_luminance;
    float exposure;
    float contrast;
    float saturation;
    uint32_t mode; // 0: ACES, 1: Reinhard
};

// Parameters passed to Anime4K & CAS Sharpening shader
struct UltimateSharpenParams {
    float sharpness;     // 0.0 - 1.0 (CAS strength)
    float edge_thinning; // 0.0 - 1.0 (Sobel gradient push)
    float clamp_limit;   // anti-ringing threshold
};

// Parameters passed to Retro CRT Shader
struct UltimateCRTParams {
    float scanline_intensity;
    float chromatic_aberration;
    float aperture_grille_opacity;
    float film_grain_intensity;
    float curvature;
    uint32_t time_frame;
};

// Parameters passed to 2-Screen Wipe & Loupe Shader
struct UltimateWipeParams {
    float split_x;             // 0.0 - 1.0 screen divider
    simd_float2 loupe_center;  // UV center of loupe (0.0 - 1.0)
    float loupe_radius;        // UV radius of loupe
    float loupe_zoom;          // 1.0 - 10.0x zoom factor
    uint32_t is_loupe_active;
    uint32_t show_divider;
};

// Parameters for Real-Time Stabilization & Deinterlace
struct UltimateTransformParams {
    simd_float2 translation_offset; // UV shift
    float rotation_angle;           // Radians
    float crop_scale;               // Zoom factor to eliminate black border edges
    uint32_t deinterlace_enabled;
    float comb_threshold;
};

#endif /* UltimateVideoTypes_h */
