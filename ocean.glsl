// ocean.glsl — rolling ocean swells under terminal text
//
// iChannel0 = terminal content
// No compute needed — Gerstner waves are analytic.
//
// Screen split: upper portion = terminal over water surface,
// lower portion = ocean depth view. Waves roll through the text.

// ── Tuning ────────────────────────────────────────────────────────────────────
#define HORIZON      0.28     // where ocean meets sky (0=bottom, 1=top)
#define WAVE_HEIGHT  0.018    // swell amplitude
#define CHOP         0.55     // steepness / choppiness [0=sine, 1=sharp crests]
#define FOAM_STR     0.55     // whitecap brightness
#define DEPTH_COLOR  vec3(0.02, 0.08, 0.18)
#define SHALLOW_COLOR vec3(0.04, 0.22, 0.32)
#define SKY_COLOR    vec3(0.06, 0.10, 0.22)
#define REFRACT_STR  0.022    // text distortion through surface
// ─────────────────────────────────────────────────────────────────────────────

float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

// Gerstner wave — returns (displacement_x, displacement_y, height)
vec3 gerstner(vec2 pos, vec2 dir, float wavelength, float amplitude, float steepness, float speed) {
    float k = 6.28318 / wavelength;
    float c = sqrt(9.8 / k);
    float f = k * (dot(dir, pos) - c * speed * iTime);
    float Q = steepness / (k * amplitude);
    return vec3(
        Q * amplitude * dir.x * cos(f),
        Q * amplitude * dir.y * cos(f),
        amplitude * sin(f)
    );
}

// Sum of Gerstner waves
vec3 oceanSurface(vec2 pos) {
    vec3 w = vec3(0.0);
    w += gerstner(pos, normalize(vec2(1.0,  0.4)), 0.38, WAVE_HEIGHT * 1.00, CHOP, 0.32);
    w += gerstner(pos, normalize(vec2(0.7,  1.0)), 0.21, WAVE_HEIGHT * 0.60, CHOP, 0.28);
    w += gerstner(pos, normalize(vec2(1.2, -0.3)), 0.15, WAVE_HEIGHT * 0.35, CHOP, 0.22);
    w += gerstner(pos, normalize(vec2(0.3,  0.8)), 0.09, WAVE_HEIGHT * 0.18, CHOP, 0.18);
    return w;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv  = fragCoord / iResolution.xy;
    vec2 px  = 1.0 / iResolution.xy;
    float aspect = iResolution.x / iResolution.y;

    // ── World position (scaled for wave detail) ───────────────────────────
    vec2 pos = vec2(uv.x * aspect * 3.0, uv.y * 3.0);

    // ── Ocean surface height at this column ───────────────────────────────
    vec3 surf     = oceanSurface(pos);
    float waveH   = surf.z;  // [-1,1] height
    float horizon  = HORIZON + waveH * 0.04;  // horizon bobs with swell

    // ── Surface gradient for normals + refraction ─────────────────────────
    vec3 surfR = oceanSurface(pos + vec2(px.x * aspect * 3.0, 0.0));
    vec3 surfU = oceanSurface(pos + vec2(0.0, px.y * 3.0));
    vec2 grad  = vec2(surfR.z - waveH, surfU.z - waveH) * 40.0;
    vec3 N     = normalize(vec3(-grad, 1.0));

    // ── Terminal text with wave refraction ────────────────────────────────
    vec2 refractOffset = grad * REFRACT_STR * smoothstep(horizon - 0.06, horizon + 0.06, uv.y);
    float ch = 0.012;
    vec3 term = vec3(
        texture(iChannel0, clamp(uv + refractOffset * (1.0 - ch), 0.001, 0.999)).r,
        texture(iChannel0, clamp(uv + refractOffset,               0.001, 0.999)).g,
        texture(iChannel0, clamp(uv + refractOffset * (1.0 + ch), 0.001, 0.999)).b
    );
    float textL = luma(term);

    // ── Sky ───────────────────────────────────────────────────────────────
    vec3 sky = mix(SKY_COLOR * 1.4, SKY_COLOR * 0.6, uv.y);

    // ── Ocean depth color ──────────────────────────────────────────────────
    float depthFade = smoothstep(horizon, horizon - 0.3, uv.y);
    vec3  waterCol  = mix(SHALLOW_COLOR, DEPTH_COLOR, depthFade);

    // ── Specular on wave faces ────────────────────────────────────────────
    vec3  L    = normalize(vec3(0.5, 0.8, 1.2));
    vec3  H    = normalize(L + vec3(0.0, 0.0, 1.0));
    float spec = pow(max(dot(N, H), 0.0), 120.0) * length(grad) * 8.0;
    waterCol  += vec3(0.7, 0.9, 1.0) * spec * 0.8;

    // ── Foam at wave crests ────────────────────────────────────────────────
    float foam = smoothstep(0.55, 0.85, waveH) * FOAM_STR;
    waterCol   = mix(waterCol, vec3(0.85, 0.92, 0.96), foam);

    // ── Fresnel — shallow angle = more reflection ──────────────────────────
    float fresnel = pow(1.0 - max(dot(N, vec3(0.0, 0.0, 1.0)), 0.0), 3.0);
    waterCol = mix(waterCol, sky * 0.6, fresnel * 0.4);

    // ── Composite ─────────────────────────────────────────────────────────
    float surfMask = smoothstep(horizon - 0.01, horizon + 0.01, uv.y);
    vec3  color    = mix(waterCol, sky, surfMask);

    // Text overlaid — above horizon reads clean, below horizon refracts
    float textAlpha = textL * mix(0.5, 1.0, surfMask);
    color = mix(color, term + color * 0.2, textAlpha * 0.9);

    // ── Focus dim ─────────────────────────────────────────────────────────
    float focusT   = clamp((iTime - iTimeFocus) * 1.5, 0.0, 1.0);
    float focusMix = iFocus == 1 ? focusT : 1.0 - focusT;
    vec3  grey     = vec3(luma(color));
    color = mix(grey, color, mix(0.3, 1.0, focusMix)) * mix(0.55, 1.0, focusMix);

    fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
