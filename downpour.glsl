// Downpour v3 — cellular automata rain on dirty glass
//
// Water + grime state lives in iChannel2 (compute shader).
// This shader just reads the state and renders:
//   - Water: refraction + chromatic aberration + specular from gradient normals
//   - Grime: slight desaturation + warmth + softening (dirty monitor film)
//
// iChannel0 = terminal
// iChannel2 = compute state (R=water, G=grime)

// ── Tuning ──────────────────────────────────────────────────────────
#define REFRACT_STRENGTH    0.008
#define CHROMA_SPREAD       0.09
#define SPECULAR            0.08
#define NORMAL_SCALE        4.0      // amplify gradient → normal
#define GRIME_VIS_DESAT     0.15     // max visual desaturation from grime
#define GRIME_VIS_WARMTH    0.015    // max warm shift from grime
#define GRIME_VIS_BLUR      0.12     // max blur mix from grime
// ════════════════════════════════════════════════════════════════════

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2  uv = fragCoord / iResolution.xy;
    vec2  px = 1.0 / iResolution.xy;

    // ── Read compute state ───────────────────────────────────────────
    vec4  state = texture(iChannel2, uv);
    float water = state.r;
    float grime = state.g;

    vec3 terminal = texture(iChannel0, uv).rgb;

    // ── Water normal from gradient ───────────────────────────────────
    float wL = texture(iChannel2, uv + vec2(-px.x, 0.0)).r;
    float wR = texture(iChannel2, uv + vec2( px.x, 0.0)).r;
    float wU = texture(iChannel2, uv + vec2(0.0, -px.y)).r;
    float wD = texture(iChannel2, uv + vec2(0.0,  px.y)).r;
    vec2  wN = vec2(wR - wL, wD - wU) * NORMAL_SCALE;

    float isWet = smoothstep(0.02, 0.12, water);

    // ── Refraction + chromatic aberration ────────────────────────────
    vec2  refract = wN * REFRACT_STRENGTH;
    float spread  = CHROMA_SPREAD * 0.5;
    vec3 clean = vec3(
        texture(iChannel0, clamp(uv + refract * (1.0 - spread), 0.001, 0.999)).r,
        texture(iChannel0, clamp(uv + refract,                  0.001, 0.999)).g,
        texture(iChannel0, clamp(uv + refract * (1.0 + spread), 0.001, 0.999)).b
    );

    // ── Specular ─────────────────────────────────────────────────────
    float nMag  = length(wN);
    vec2  safeN = wN / max(nMag, 0.001);
    float spec  = max(dot(safeN, vec2(-0.5, -0.8)), 0.0);
    spec = spec * spec * nMag * SPECULAR;
    vec3 wetColor = clean + vec3(1.0, 0.97, 0.90) * spec;

    // ── Grime visual effect ──────────────────────────────────────────
    float luma = dot(terminal, vec3(0.299, 0.587, 0.114));

    // Desaturation
    vec3 grimy = mix(terminal, vec3(luma), grime * GRIME_VIS_DESAT);

    // Warmth
    grimy += vec3(1.0, 0.45, -0.25) * grime * GRIME_VIS_WARMTH;

    // Slight softening
    vec3 blurred = (
        texture(iChannel0, uv + vec2(px.x, 0.0)).rgb +
        texture(iChannel0, uv - vec2(px.x, 0.0)).rgb +
        texture(iChannel0, uv + vec2(0.0, px.y)).rgb +
        texture(iChannel0, uv - vec2(0.0, px.y)).rgb
    ) * 0.25;
    grimy = mix(grimy, blurred, grime * GRIME_VIS_BLUR);

    // ── Compose ──────────────────────────────────────────────────────
    vec3 color = mix(grimy, wetColor, isWet);

    fragColor = vec4(clamp(color, 0.0, 1.0), texture(iChannel0, uv).a);
}
