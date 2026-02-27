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
#define BLOOM_STR    1.0     // bloom intensity multiplier
#define REFRACT_STR  0.0016  // refraction offset strength
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

    // ── Hackers cityscape — camera flies over terminal-driven skyline ─────────
    // Building heights = terminal column luminance. Dense code = tall towers.
    // Left buildings: matrix-green windows. Right: ICE-blue/teal. Rooflines glow.
    {
        float vpX  = 0.50, vpY = 0.44;
        float camH = 0.30;   // camera height above ground
        float stW  = 0.28;   // half street width
        float BLEN = 0.50;   // building block depth
        float scrl = iTime * 0.08 + texture(iChannel2, vec2(0.5, 0.5)).a;
        float rdx  = uv.x - vpX;
        float rdy  = uv.y - vpY;
        vec3  city = vec3(0.0);

        float wzL = (rdx < -0.001) ? stW / (-rdx) : 1e6;
        float wzR = (rdx >  0.001) ? stW /   rdx  : 1e6;
        float wzG = (rdy < -0.001) ? camH / (-rdy) : 1e6;

        // Left buildings: matrix-green windows
        if (wzL < 1e5) {
            float wz     = wzL;
            float wy     = rdy * wz;
            float worldZ = scrl + wz;
            float bIdx   = floor(worldZ / BLEN);
            float tX     = fract(bIdx * 0.618 + 0.10);
            float bLuma  = (texture(iChannel0, vec2(tX, 0.20)).r +
                            texture(iChannel0, vec2(tX, 0.45)).r +
                            texture(iChannel0, vec2(tX, 0.70)).r) * 0.333;
            float bH     = 0.04 + bLuma * 0.40;
            float wyTop  = bH - camH;
            if (wzL < wzG && wy <= wyTop) {
                float fade  = exp(-wz * 0.07);
                float faceZ = fract(worldZ / BLEN);
                float faceY = (wy + camH) / bH;
                float wgZ   = abs(fract(faceZ * 6.0) - 0.5) * 2.0;
                float wgY   = abs(fract(faceY * 9.0) - 0.5) * 2.0;
                float win   = step(0.42, wgZ) * step(0.38, wgY);
                float winLum = texture(iChannel0, vec2(tX, 0.1 + faceY * 0.8)).r;
                vec3 winCol  = mix(vec3(0.12, 0.95, 0.50), vec3(0.52, 0.10, 1.00),
                                   fract(bIdx * 0.41)) * winLum;
                city += mix(vec3(0.02, 0.035, 0.07), winCol * 0.9, win) * fade;
                city += exp(-abs(wy - wyTop) * wz * 16.0) * 0.4 * vec3(0.70, 1.00, 0.85) * fade;
            }
        }

        // Right buildings: ICE-blue / teal windows
        if (wzR < 1e5) {
            float wz     = wzR;
            float wy     = rdy * wz;
            float worldZ = scrl + wz;
            float bIdx   = floor(worldZ / BLEN);
            float tX     = fract(bIdx * 0.618 + 0.60);
            float bLuma  = (texture(iChannel0, vec2(tX, 0.20)).r +
                            texture(iChannel0, vec2(tX, 0.45)).r +
                            texture(iChannel0, vec2(tX, 0.70)).r) * 0.333;
            float bH     = 0.04 + bLuma * 0.40;
            float wyTop  = bH - camH;
            if (wzR < wzG && wy <= wyTop) {
                float fade  = exp(-wz * 0.07);
                float faceZ = fract(worldZ / BLEN);
                float faceY = (wy + camH) / bH;
                float wgZ   = abs(fract(faceZ * 6.0) - 0.5) * 2.0;
                float wgY   = abs(fract(faceY * 9.0) - 0.5) * 2.0;
                float win   = step(0.42, wgZ) * step(0.38, wgY);
                float winLum = texture(iChannel0, vec2(tX, 0.1 + faceY * 0.8)).r;
                vec3 winCol  = mix(vec3(0.10, 0.58, 1.00), vec3(0.20, 1.00, 0.65),
                                   fract(bIdx * 0.53)) * winLum;
                city += mix(vec3(0.02, 0.035, 0.07), winCol * 0.9, win) * fade;
                city += exp(-abs(wy - wyTop) * wz * 16.0) * 0.4 * vec3(0.70, 1.00, 0.85) * fade;
            }
        }

        // Ground: city block grid
        if (wzG < wzL && wzG < wzR && rdy < -0.001) {
            float wz   = wzG;
            float wx   = rdx * wz;
            float fade = exp(-wz * 0.045) * smoothstep(0.0, 0.025, -rdy);
            float gx   = abs(fract(wx             * 2.2) - 0.5) * 2.0;
            float gz   = abs(fract((scrl + wz) * 2.2 / BLEN) - 0.5) * 2.0;
            float grid = max(1.0 - smoothstep(0.0, 0.07, gx),
                             1.0 - smoothstep(0.0, 0.07, gz));
            city += grid * fade * 0.10 * vec3(0.12, 0.95, 0.50);
        }

        // Horizon haze
        city += vec3(0.015, 0.025, 0.08) * exp(-abs(rdy) * 18.0) * 0.35;

        neonSrc += city;
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
