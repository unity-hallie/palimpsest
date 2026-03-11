// ripple.glsl — viscoelastic fluid, Beer-Lambert depth, 1989 wireframe corridor
//
// iChannel0 = terminal content
// iChannel2 = wave state (R=u_curr, G=u_old, from ripple.compute.msl)
//
// Palette: deep navy void (#06081a), dusty neon teal text (#72d8c0).
// Typing creates neon blooms; still liquid is deep and dusty.
// Background: dim perspective-correct wireframe hallway, segment-based turns,
// T-junction flash every ~11 s — scrolls faster while typing.

// ── Tuning ────────────────────────────────────────────────────────────────────
#define BASE_DEPTH   0.032   // liquid depth at rest (metres, ~3 cm)
#define EXTINCTION   18.0    // Beer-Lambert σ: controls how fast light dies
#define SCATTER      5.5     // scatter coefficient: dusty veil thickness
#define BLOOM_STR    0.55    // bloom intensity multiplier
#define REFRACT_STR  0.0048  // refraction offset strength
#define SPEC_STR     0.22    // specular highlight intensity
#define VIGNETTE     0.28    // edge darkening
// ─────────────────────────────────────────────────────────────────────────────

float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

float hash21(vec2 p) {
    p = fract(p * vec2(127.1, 311.7));
    p += dot(p, p.yx + 19.19);
    return fract(p.x * p.y);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec2 px = 1.0 / iResolution.xy;

    // ── Wave state ────────────────────────────────────────────────────────────
    float u     = texture(iChannel2, uv).r;
    float u_old = texture(iChannel2, uv).g;

    // ── Surface gradient (refraction + specular normals) ─────────────────────
    float uL = texture(iChannel2, uv - vec2(px.x, 0.0)).r;
    float uR = texture(iChannel2, uv + vec2(px.x, 0.0)).r;
    float uU = texture(iChannel2, uv - vec2(0.0, px.y)).r;
    float uD = texture(iChannel2, uv + vec2(0.0, px.y)).r;
    vec2 grad = vec2(uR - uL, uD - uU);

    // ── Chromatic aberration refraction ───────────────────────────────────────
    float ref = REFRACT_STR;
    float ch  = 0.016;
    vec3 term = vec3(
        texture(iChannel0, clamp(uv + grad * ref * (1.0 - ch), 0.001, 0.999)).r,
        texture(iChannel0, clamp(uv + grad * ref,               0.001, 0.999)).g,
        texture(iChannel0, clamp(uv + grad * ref * (1.0 + ch), 0.001, 0.999)).b
    );

    // ── Beer-Lambert depth ────────────────────────────────────────────────────
    // Impulse pushes wave up → depth decreases → neon glow. Still water = dusty.
    float depth = max(BASE_DEPTH - u * 0.55, 0.004);

    // Per-channel extinction (R absorbed first, B last → warm→cool depth gradient)
    vec3 sigma = vec3(EXTINCTION * 1.20, EXTINCTION * 1.00, EXTINCTION * 0.72);
    vec3 T     = exp(-sigma * depth);   // transmittance

    // ── Neon tint: what colour the liquid tints light ─────────────────────────
    // Soft teal-cyan — dusty neon, not harsh
    vec3 neonTint = vec3(0.30, 0.88, 0.76);

    // ── Source: terminal text boosted as neon emitter ─────────────────────────
    vec3 neonSrc = term * vec3(1.08, 1.12, 1.16) + vec3(0.04, 0.04, 0.06);

    // ── Hyperspace starfield — slow zoom outward from center ─────────────────
    {
        vec2 center = vec2(0.50, 0.50);
        vec2 d      = uv - center;
        vec3 stars  = vec3(0.0);

        for (int i = 0; i < 5; i++) {
            float fi   = float(i);
            float seed = fi * 1.618;
            // z = lifecycle [0→1]: star born at center, drifts to edge, wraps
            float z    = fract(iTime * 0.018 * (1.0 + fi * 0.22) + seed);
            // Project pixel back to star-space (inverse of zoom transform)
            vec2  sv   = d / max(z, 0.01) * 0.5 + center;
            vec2  cell = floor(sv * 14.0);
            vec2  frac = fract(sv * 14.0);
            float h    = hash21(cell + seed * 19.3);
            if (h > 0.68) {
                vec2  ctr  = vec2(fract(h * 11.37), fract(h * 8.53));
                float dist = length(frac - ctr);
                float glow = exp(-dist * dist * 3000.0);
                float fade = smoothstep(0.0, 0.06, length(d))   // hide center singularity
                           * smoothstep(0.65, 0.40, length(d))  // fade at screen edge
                           * smoothstep(0.0,  0.12, z);         // fade in from center
                vec3  col  = mix(vec3(0.50, 0.72, 1.00), vec3(0.95, 0.98, 1.00), h * h);
                stars += glow * fade * h * col * 0.55;
            }
        }

        neonSrc += stars * 0.28;
    }

    // ── Direct transmitted light ──────────────────────────────────────────────
    vec3 direct = neonSrc * T;

    // ── Scattered ambient: dusty veil, grows with depth ───────────────────────
    float scatter  = 1.0 - exp(-SCATTER * depth);
    vec3  dustVeil = vec3(0.13, 0.11, 0.24) * scatter;

    vec3 color = direct + dustVeil;

    // ── Bloom: neon smoke — scatter drives diffusion radius ───────────────────
    vec3 bloom = vec3(0.0);
    for (int i = 0; i < 8; i++) {
        float a   = 6.28318530718 * float(i) * 0.125;
        vec2  dir = vec2(cos(a), sin(a));
        vec3  c1  = texture(iChannel0, clamp(uv + dir * px *  8.0, 0.001, 0.999)).rgb;
        vec3  c2  = texture(iChannel0, clamp(uv + dir * px * 18.0, 0.001, 0.999)).rgb;
        bloom += (c1 + c2 * 0.45) * neonTint;
    }
    bloom *= BLOOM_STR * 0.030 * (0.15 + scatter * 1.30);
    color += bloom;

    // ── Specular: wave facets catch neon light ────────────────────────────────
    float nMag = length(grad);
    vec3  N    = normalize(vec3(-grad * 5.0, 1.0));
    vec3  L    = normalize(vec3(-0.30, -0.60, 1.80));
    vec3  H    = normalize(L + vec3(0.0, 0.0, 1.0));
    float spec = pow(max(dot(N, H), 0.0), 80.0) * nMag * 10.0;
    color += vec3(0.28, 0.96, 0.82) * spec * SPEC_STR;

    // ── Vignette ──────────────────────────────────────────────────────────────
    color *= 1.0 - VIGNETTE * dot(uv - 0.5, uv - 0.5);

    fragColor = vec4(clamp(color, 0.0, 1.0), texture(iChannel0, uv).a);
}
