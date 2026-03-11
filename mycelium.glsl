// mycelium.glsl — competing bioluminescent molds
//
// iChannel0 = terminal
// iChannel1 = previous render output (feedback for temporal smoothing)
// iChannel2 = state (R=food, G=cell, B=heading, A=hue/species)

// ── Tuning ──────────────────────────────────────────────────────────────────
#define TEXT_OPACITY   1.15
#define TEXT_TINT      0.30
#define STRAND_DIM     0.28
#define VIGNETTE       0.16
// ────────────────────────────────────────────────────────────────────────────

float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

// Hue → color. Saturation driven by food — vivid near letters, gray at distant strands.
vec3 speciesColor(float hue, float food) {
    vec3 c = clamp(abs(fract(hue + vec3(0.0, 2.0, 1.0) / 3.0) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
    float sat = mix(0.12, 0.88, smoothstep(0.2, 0.8, food));
    return mix(vec3(1.0), c, sat);
}

bool isTip(float g)    { return g > 0.5; }
bool isStrand(float g) { return g > 0.04 && g <= 0.5; }

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    vec3  term  = texture(iChannel0, uv).rgb;
    vec4  state = texture(iChannel2, uv);
    float food  = state.r;
    float cell  = state.g;
    float hue   = state.a;

    // ── Terminal text ─────────────────────────────────────────────────────
    float textL  = luma(term);
    vec3  water  = vec3(0.000, 0.008, 0.018);
    vec3  tinted = vec3(textL * 0.60, textL * 0.92, textL);
    vec3  base   = mix(water, mix(term, tinted, TEXT_TINT), textL * TEXT_OPACITY);

    // ── Strand body ───────────────────────────────────────────────────────
    vec3 strandCol = vec3(0.0);
    if (isStrand(cell) || isTip(cell)) {
        strandCol = speciesColor(hue, food) * min(cell, 0.5) * STRAND_DIM;
    }

    // ── Composite ─────────────────────────────────────────────────────────
    vec3 color = base + strandCol;
    color *= 1.0 - VIGNETTE * pow(length((uv - 0.5) * vec2(1.0, 0.85)), 2.2);

    // ── Temporal smoothing — gated by text presence ───────────────────────
    vec3  prev      = texture(iChannel1, uv).rgb;
    float blendRate = mix(0.18, 0.55, smoothstep(0.05, 0.3, textL));
    color = mix(prev, color, blendRate);

    fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
