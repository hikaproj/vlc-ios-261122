//
//  UltimateVideoShaders.metal
//  VLCUltimateEngine
//
//  Created for VLC iOS Ultimate Workstation.
//  Metal Shaders: HDR Tone Mapping, Anime4K/CAS, Retro CRT, Motion Deinterlace, Wipe Loupe.
//

#include <metal_stdlib>
#include "UltimateVideoTypes.h"

using namespace metal;

// MARK: - Constants & Helper Functions

constant float3 kLuminanceWeights = float3(0.2126, 0.7152, 0.0722);

inline float rgb_to_luminance(float3 rgb) {
    return dot(rgb, kLuminanceWeights);
}

inline float3 ACESFilm(float3 x) {
    float a = 2.51f;
    float b = 0.03f;
    float c = 2.43f;
    float d = 0.59f;
    float e = 0.14f;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0f, 1.0f);
}

// MARK: - 1. 256-Bin Luminance Histogram Compute Kernel
kernel void calculate_luminance_histogram(
    texture2d<float, access::read> inTexture [[texture(0)]],
    device atomic_uint* globalHistogram [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]],
    uint2 tid [[thread_position_in_threadgroup]],
    uint2 tdims [[threads_per_threadgroup]]
) {
    // 256-bin threadgroup shared memory
    threadgroup atomic_uint localHistogram[256];
    
    uint linearTid = tid.y * tdims.x + tid.x;
    if (linearTid < 256) {
        atomic_store_explicit(&localHistogram[linearTid], 0, memory_order_relaxed);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    
    if (gid.x < inTexture.get_width() && gid.y < inTexture.get_height()) {
        float4 color = inTexture.read(gid);
        float lum = clamp(rgb_to_luminance(color.rgb), 0.0f, 0.999f);
        uint bin = uint(lum * 256.0f);
        atomic_fetch_add_explicit(&localHistogram[bin], 1, memory_order_relaxed);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    
    // Atomically write into global histogram
    if (linearTid < 256) {
        uint count = atomic_load_explicit(&localHistogram[linearTid], memory_order_relaxed);
        if (count > 0) {
            atomic_fetch_add_explicit(&globalHistogram[linearTid], count, memory_order_relaxed);
        }
    }
}

// MARK: - 2. Dynamic HDR Tone Mapping Compute Kernel
kernel void dynamic_hdr_tone_mapping(
    texture2d<float, access::read> inTexture [[texture(0)]],
    texture2d<float, access::write> outTexture [[texture(1)]],
    constant UltimateToneMapParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= inTexture.get_width() || gid.y >= inTexture.get_height()) return;
    
    float4 src = inTexture.read(gid);
    float3 color = src.rgb;
    
    // Auto-Exposure scaling based on temporal average luminance
    float avgLum = max(params.average_luminance, 0.05f);
    float scaledExposure = params.exposure / avgLum;
    color *= scaledExposure;
    
    float3 toneMapped;
    if (params.mode == ToneMap_ACES) {
        toneMapped = ACESFilm(color);
    } else {
        // Extended Reinhard
        float maxLumSq = params.max_luminance * params.max_luminance;
        toneMapped = (color * (1.0f + color / maxLumSq)) / (1.0f + color);
    }
    
    // Contrast Adjustment
    toneMapped = max(float3(0.0f), (toneMapped - 0.5f) * params.contrast + 0.5f);
    
    // Saturation Adjustment
    float lum = rgb_to_luminance(toneMapped);
    toneMapped = max(float3(0.0f), mix(float3(lum), toneMapped, params.saturation));
    
    outTexture.write(float4(toneMapped, src.a), gid);
}

// MARK: - 3. Anime4K Edge Thinning & CAS Sharpening Compute Kernel
kernel void anime4k_edge_and_cas_sharpen(
    texture2d<float, access::read> inTexture [[texture(0)]],
    texture2d<float, access::write> outTexture [[texture(1)]],
    constant UltimateSharpenParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint width = inTexture.get_width();
    uint height = inTexture.get_height();
    if (gid.x >= width || gid.y >= height) return;
    
    int2 pos = int2(gid);
    
    // 3x3 Neighborhood Sampling
    float4 c_m  = inTexture.read(uint2(pos));
    float4 c_tl = inTexture.read(uint2(clamp(pos + int2(-1, -1), int2(0), int2(width-1, height-1))));
    float4 c_tc = inTexture.read(uint2(clamp(pos + int2( 0, -1), int2(0), int2(width-1, height-1))));
    float4 c_tr = inTexture.read(uint2(clamp(pos + int2( 1, -1), int2(0), int2(width-1, height-1))));
    float4 c_ml = inTexture.read(uint2(clamp(pos + int2(-1,  0), int2(0), int2(width-1, height-1))));
    float4 c_mr = inTexture.read(uint2(clamp(pos + int2( 1,  0), int2(0), int2(width-1, height-1))));
    float4 c_bl = inTexture.read(uint2(clamp(pos + int2(-1,  1), int2(0), int2(width-1, height-1))));
    float4 c_bc = inTexture.read(uint2(clamp(pos + int2( 0,  1), int2(0), int2(width-1, height-1))));
    float4 c_br = inTexture.read(uint2(clamp(pos + int2( 1,  1), int2(0), int2(width-1, height-1))));
    
    // Sobel Gradient Calculation for Anime4K edge thinning
    float l_tl = rgb_to_luminance(c_tl.rgb);
    float l_tc = rgb_to_luminance(c_tc.rgb);
    float l_tr = rgb_to_luminance(c_tr.rgb);
    float l_ml = rgb_to_luminance(c_ml.rgb);
    float l_mr = rgb_to_luminance(c_mr.rgb);
    float l_bl = rgb_to_luminance(c_bl.rgb);
    float l_bc = rgb_to_luminance(c_bc.rgb);
    float l_br = rgb_to_luminance(c_br.rgb);
    float l_m  = rgb_to_luminance(c_m.rgb);
    
    float gx = (l_tr + 2.0f * l_mr + l_br) - (l_tl + 2.0f * l_ml + l_bl);
    float gy = (l_bl + 2.0f * l_bc + l_br) - (l_tl + 2.0f * l_tc + l_tr);
    float gradMag = sqrt(gx * gx + gy * gy);
    
    // Contrast Adaptive Sharpening (CAS) Filter
    float min_l = min(l_m, min(min(l_tc, l_bc), min(l_ml, l_mr)));
    float max_l = max(l_m, max(max(l_tc, l_bc), max(l_ml, l_mr)));
    
    // CAS Peak Weight with Anti-Ringing
    float amp = clamp(min(min_l, 1.0f - max_l) / max(max_l, 0.001f), 0.0f, 1.0f);
    float w = -sqrt(amp) * (params.sharpness * 0.20f);
    
    float3 cross_sum = c_tc.rgb + c_bc.rgb + c_ml.rgb + c_mr.rgb;
    float3 cas_color = (c_m.rgb + cross_sum * w) / (1.0f + 4.0f * w);
    
    // Apply Edge Thinning Push if gradient is strong
    float3 final_color = cas_color;
    if (gradMag > 0.12f && params.edge_thinning > 0.05f) {
        float2 dir = normalize(float2(gx, gy));
        int2 pushPos = clamp(pos - int2(round(dir * params.edge_thinning)), int2(0), int2(width-1, height-1));
        float3 thinColor = inTexture.read(uint2(pushPos)).rgb;
        final_color = mix(cas_color, thinColor, 0.40f * params.edge_thinning);
    }
    
    outTexture.write(float4(clamp(final_color, 0.0f, 1.0f), c_m.a), gid);
}

// MARK: - 4. Retro CRT Filter Compute Kernel
kernel void retro_crt_filter(
    texture2d<float, access::read> inTexture [[texture(0)]],
    texture2d<float, access::write> outTexture [[texture(1)]],
    constant UltimateCRTParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    float width = float(inTexture.get_width());
    float height = float(inTexture.get_height());
    if (float(gid.x) >= width || float(gid.y) >= height) return;
    
    float2 uv = float2(gid) / float2(width, height);
    
    // CRT Barrel Curvature
    float2 cc = uv - 0.5f;
    float dist = dot(cc, cc);
    float2 curvd_uv = 0.5f + cc * (1.0f + params.curvature * dist);
    
    if (curvd_uv.x < 0.0f || curvd_uv.x > 1.0f || curvd_uv.y < 0.0f || curvd_uv.y > 1.0f) {
        outTexture.write(float4(0.0f, 0.0f, 0.0f, 1.0f), gid);
        return;
    }
    
    // Chromatic Aberration Sampling
    float r_offset = params.chromatic_aberration * 0.003f;
    float b_offset = -params.chromatic_aberration * 0.003f;
    
    uint2 r_pos = uint2(clamp(curvd_uv + float2(r_offset, 0.0f), 0.0f, 1.0f) * float2(width, height));
    uint2 g_pos = uint2(curvd_uv * float2(width, height));
    uint2 b_pos = uint2(clamp(curvd_uv + float2(b_offset, 0.0f), 0.0f, 1.0f) * float2(width, height));
    
    float r = inTexture.read(r_pos).r;
    float g = inTexture.read(g_pos).g;
    float b = inTexture.read(b_pos).b;
    
    // Scanlines (Horizontal Sine modulation)
    float scanline = sin(curvd_uv.y * height * 3.14159f);
    float scanline_mul = 1.0f - params.scanline_intensity * (0.5f + 0.5f * scanline);
    
    // Aperture Grille (Phosphor Trio Mask: Red, Green, Blue columns)
    uint col = uint(gid.x) % 3;
    float3 mask = float3(1.0f);
    if (col == 0) mask = float3(1.15f, 0.85f, 0.85f);
    else if (col == 1) mask = float3(0.85f, 1.15f, 0.85f);
    else mask = float3(0.85f, 0.85f, 1.15f);
    
    float3 crt_color = float3(r, g, b) * scanline_mul * mix(float3(1.0f), mask, params.aperture_grille_opacity);
    
    // Film Grain (PRNG)
    if (params.film_grain_intensity > 0.01f) {
        float grain = fract(sin(dot(curvd_uv * float(params.time_frame), float2(12.9898, 78.233))) * 43758.5453);
        crt_color += (grain - 0.5f) * params.film_grain_intensity;
    }
    
    outTexture.write(float4(clamp(crt_color, 0.0f, 1.0f), 1.0f), gid);
}

// MARK: - 5. Motion-Adaptive Deinterlace Compute Kernel
kernel void motion_adaptive_deinterlace(
    texture2d<float, access::read> inTexture [[texture(0)]],
    texture2d<float, access::write> outTexture [[texture(1)]],
    constant UltimateTransformParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    uint width = inTexture.get_width();
    uint height = inTexture.get_height();
    if (gid.x >= width || gid.y >= height) return;
    
    float4 current = inTexture.read(gid);
    if (params.deinterlace_enabled == 0 || gid.y == 0 || gid.y >= height - 1) {
        outTexture.write(current, gid);
        return;
    }
    
    float4 prev_line = inTexture.read(uint2(gid.x, gid.y - 1));
    float4 next_line = inTexture.read(uint2(gid.x, gid.y + 1));
    
    // Comb artifact detector: |2*C - (P + N)|
    float3 comb = abs(2.0f * current.rgb - (prev_line.rgb + next_line.rgb));
    float comb_max = max(comb.r, max(comb.g, comb.b));
    
    if (comb_max > params.comb_threshold) {
        // High comb: interpolate vertically
        float4 interpolated = 0.5f * (prev_line + next_line);
        outTexture.write(interpolated, gid);
    } else {
        // Progressive: preserve scanline
        outTexture.write(current, gid);
    }
}

// MARK: - 6. 2-Screen Wipe Comparison & Loupe Render Shader
struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut wipe_vertex_shader(uint vertexID [[vertex_id]]) {
    VertexOut out;
    // Full screen triangle
    float2 coords[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    float2 uvs[3]    = { float2(0.0, 1.0),   float2(2.0, 1.0),  float2(0.0, -1.0) };
    out.position = float4(coords[vertexID], 0.0, 1.0);
    out.uv = uvs[vertexID];
    return out;
}

fragment float4 wipe_comparison_and_loupe(
    VertexOut in [[stage_in]],
    texture2d<float> textureA [[texture(0)]], // Original / Secondary
    texture2d<float> textureB [[texture(1)]], // Processed / Primary
    constant UltimateWipeParams& params [[buffer(0)]],
    sampler textureSampler [[sampler(0)]]
) {
    float2 uv = in.uv;
    
    // Check Loupe
    if (params.is_loupe_active != 0) {
        float2 diff = uv - params.loupe_center;
        float dist = length(diff);
        
        // Loupe Inner Magnifier
        if (dist < params.loupe_radius) {
            float2 zoomed_uv = params.loupe_center + diff / params.loupe_zoom;
            float4 colorA = textureA.sample(textureSampler, zoomed_uv);
            float4 colorB = textureB.sample(textureSampler, zoomed_uv);
            return (zoomed_uv.x < params.split_x) ? colorA : colorB;
        }
        
        // Loupe Neon Cyan Rim
        if (dist >= params.loupe_radius && dist < (params.loupe_radius + 0.004f)) {
            return float4(0.40f, 0.988f, 0.945f, 1.0f); // Neon Teal
        }
    }
    
    // Split Screen Wipe
    float4 sampleA = textureA.sample(textureSampler, uv);
    float4 sampleB = textureB.sample(textureSampler, uv);
    
    // Divider line
    if (params.show_divider != 0 && abs(uv.x - params.split_x) < 0.0015f) {
        return float4(1.0f, 1.0f, 1.0f, 1.0f);
    }
    
    return (uv.x < params.split_x) ? sampleA : sampleB;
}
