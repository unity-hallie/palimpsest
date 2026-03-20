// common.glsl -- shared helpers for palimpsest shaders
// include with: //@ include "common.glsl"

// Perceptual luminance
float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

// 1D hash
float hash1(float n) { return fract(sin(n) * 43758.5453); }

// 2D hash -> [0,1]
float hash2(vec2 p) {
    p = fract(p * vec2(127.1, 311.7));
    p += dot(p, p.yx + 19.19);
    return fract(p.x * p.y);
}

// Value noise (smooth, based on hash2)
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash2(i);
    float b = hash2(i + vec2(1.0, 0.0));
    float c = hash2(i + vec2(0.0, 1.0));
    float d = hash2(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// 4-octave fBm
float fbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) { v += a * noise(p); p *= 2.1; a *= 0.5; }
    return v;
}
