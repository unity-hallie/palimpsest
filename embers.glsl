// embers.glsl — a field of burned-down ash
//
// The background is pure fractal noise with a hard threshold —
// no cells, no centers, no structure. Just texture all the way through,
// carved into ash and crevice by a luminance cutoff.
// Text sits on top, clean and readable.
//
// iChannel0 = terminal content
// iChannel2 = compute state (age field from embers.compute.msl)

// ── Tuning ──────────────────────────────────────────────────────────
#define ASH_SCALE        6.0    // scale of the ash texture
#define CREVICE_THRESHOLD 0.42  // fbm value below this = dark crevice
#define CREVICE_SOFT     0.08   // how hard the crevice edge is (smaller = harder)
#define COAL_BREATHE_SPD 0.12   // slow enough to read as breathing not shimmer
#define COAL_BREATHE_AMP 0.38   // wide enough to clearly cross the threshold
#define ASH_BRIGHT       0.55
#define ASH_COLOR        vec3(1.0, 0.70, 0.25)    // brighter amber peaks
#define EMBER_COLOR      vec3(0.70, 0.08, 0.01)  // deep red glow
#define PIT_COLOR        vec3(0.03, 0.008, 0.0)  // near-black crevice
// ════════════════════════════════════════════════════════════════════

float hash(vec2 p) {
    p = fract(p * vec2(127.1, 311.7));
    p += dot(p, p.yx + 19.19);
    return fract(p.x * p.y);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 5; i++) {
        v += a * noise(p);
        p *= 2.17;
        a *= 0.5;
    }
    return v;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    // ── Read terminal ───────────────────────────────────────────────
    vec4 termRaw = texture(iChannel0, uv);
    vec3 term = termRaw.rgb;
    vec3 bgRef = vec3(0.055, 0.035, 0.027);
    float textLuma = dot(term, vec3(0.299, 0.587, 0.114));
    float distFromBg = length(term - bgRef);
    float textMask = smoothstep(0.03, 0.12, distFromBg);
    textMask = max(textMask, smoothstep(0.08, 0.20, textLuma));

    // ── Ash field — pure fbm, no cells ──────────────────────────────
    vec2 p = uv * ASH_SCALE;

    // Two fbm layers at different scales/offsets — no center anywhere
    float f1 = fbm(p);
    float f2 = fbm(p * 1.7 + 3.4);
    float f3 = fbm(p * 0.5 + 7.1);  // large slow variation

    // The ash surface: combination of scales
    float surface = f1 * 0.5 + f2 * 0.3 + f3 * 0.2;

    // Hard threshold: below cutoff = crevice, above = glowing surface
    float ashAmount = smoothstep(
        CREVICE_THRESHOLD - CREVICE_SOFT,
        CREVICE_THRESHOLD + CREVICE_SOFT,
        surface
    );

    // Breathing: shifts the surface value itself so areas actually
    // flare brighter and dim — not just multiply, but cross the threshold
    float breathNoise = noise(p * 0.35 + iTime * COAL_BREATHE_SPD);
    float breathNoise2 = noise(p * 0.6 + iTime * COAL_BREATHE_SPD * 0.7 + 5.3);
    float breath = breathNoise * 0.6 + breathNoise2 * 0.4;  // 0-1

    // Add breath to surface before thresholding — areas flare and die
    float breathedSurface = surface + (breath - 0.5) * COAL_BREATHE_AMP;
    float ashAmountBreathed = smoothstep(
        CREVICE_THRESHOLD - CREVICE_SOFT,
        CREVICE_THRESHOLD + CREVICE_SOFT,
        breathedSurface
    );

    float heat = ashAmountBreathed * 0.9 + ashAmount * 0.1;

    // Color: crevice → ember → ash
    // Inflection pulled down — most surface lives in dark red, bright peaks rare
    float h = pow(heat, 2.2);   // gamma crush — most surface stays dark red, only peaks glow
    vec3 ashColor = PIT_COLOR;
    ashColor = mix(ashColor, EMBER_COLOR, smoothstep(0.0,  0.35, h));
    ashColor = mix(ashColor, ASH_COLOR,   smoothstep(0.55, 0.80, h));
    ashColor = mix(ashColor, vec3(1.0, 0.95, 0.85), smoothstep(0.82, 1.0, h));
    ashColor *= ASH_BRIGHT;

    // ── Compose ─────────────────────────────────────────────────────
    vec3 color = ashColor;
    color = mix(color, term, textMask);

    fragColor = vec4(clamp(color, 0.0, 1.0), termRaw.a);
}
