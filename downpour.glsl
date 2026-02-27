// Downpour v2 — feedback-driven rain on glass
//
// Beads fall down organic noise-driven paths (water finding its way
// down unevenly dirty glass). Thin drying trails follow behind.
// Feedback buffer handles grime that slowly re-accumulates (~90s).
// Subtle chromatic aberration through water.
//
// Grime = slight desaturation + warmth + softening (dirty monitor film).
//
// iChannel0 = terminal, iChannel1 = previous frame (feedback)

// ── Tuning ──────────────────────────────────────────────────────────
#define BEAD_COUNT         10
#define DROP_COUNT          6
#define REFRACT_STRENGTH    0.005
#define SPECULAR            0.06
#define CHROMA_SPREAD       0.09    // chromatic aberration range
#define GRIME_RATE          0.0004  // ~90s to full grime at 60fps
#define GRIME_DESAT         0.10    // max desaturation
#define GRIME_WARMTH        0.012   // warm color shift at max grime
#define GRIME_SOFTNESS      0.12    // blur mix into grime target
// ════════════════════════════════════════════════════════════════════

float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i),           hash21(i+vec2(1,0)), f.x),
               mix(hash21(i+vec2(0,1)), hash21(i+vec2(1,1)), f.x), f.y);
}

// Organic wander — broad lazy curves + smaller jitter
float pathX(float baseX, float seed, float y) {
    float broad = (noise(vec2(seed * 7.1, y * 1.8)) - 0.5) * 0.07;
    float fine  = (noise(vec2(seed * 13.3, y * 5.0)) - 0.5) * 0.02;
    return baseX + broad + fine;
}

// ── Bead + drying trail ── returns vec3(height, normal.x, normal.y)
vec3 rivulet(vec2 uv, float ar, float t, float seed) {
    float speed   = 0.03 + hash21(vec2(seed, 3.3)) * 0.04;
    float fallDur = 1.15 / speed;
    float pause   = 2.0 + hash21(vec2(seed, 9.9)) * 5.0;
    float cycle   = fallDur + pause;

    float offset = hash21(vec2(seed, 2.2)) * cycle;
    float age    = mod(t + offset, cycle);
    float epoch  = floor((t + offset) / cycle);

    // Stable column with slight epoch drift
    float baseX = 0.04 + hash21(vec2(seed, 5.5)) * 0.92;
    baseX += (hash21(vec2(seed, epoch * 3.1)) - 0.5) * 0.025;

    // Bead Y: falls top → bottom
    float by = age * speed - 0.02;
    float onScreen = step(0.0, by) * step(by, 1.05);

    // Bead X: organic path at bead's current Y
    float pathSeed = seed + epoch * 0.1;
    float bx = pathX(baseX, pathSeed, by);

    // ── Bead (dome, slightly elongated vertically) ──
    vec2  bd    = (uv - vec2(bx, by)) * vec2(ar * 1.1, 0.85);
    float bdist = length(bd);
    float br    = 0.006 + hash21(vec2(seed, 6.6)) * 0.005;
    float bh    = smoothstep(br, br * 0.1, bdist) * onScreen;
    vec2  bn    = -bd / max(bdist, 0.0001) * bh;

    // ── Trail (thin, drying behind the bead) ──
    float trailDist = by - uv.y;               // positive = behind bead
    float behind    = step(0.0, trailDist) * onScreen;
    float trailAge  = trailDist / max(speed, 0.001);
    float dryTime   = 1.5 + hash21(vec2(seed, 7.7)) * 2.0;
    float trailFade = behind * smoothstep(dryTime, 0.0, trailAge);

    // Trail follows the same organic path at this pixel's Y
    float tx  = pathX(baseX, pathSeed, uv.y);
    float dx  = uv.x - tx;
    float tw  = 0.003 + hash21(vec2(seed, 8.8)) * 0.002;
    float th  = exp(-dx * dx / (tw * tw)) * trailFade;
    float trx = -2.0 * (dx / tw) * th;

    // Combine: bead dominates, trail is thinner/subtler
    float totalH = max(bh, th * 0.35);
    vec2  totalN = bn + vec2(trx * 0.25, 0.0) * trailFade;

    return vec3(totalH, totalN);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2  uv = fragCoord / iResolution.xy;
    float ar = iResolution.x / iResolution.y;
    vec2  px = 1.0 / iResolution.xy;

    // ── Water ────────────────────────────────────────────────────────
    float wH = 0.0;
    vec2  wN = vec2(0.0);

    for (int i = 0; i < BEAD_COUNT; i++) {
        vec3 r = rivulet(uv, ar, iTime, float(i) * 1.37);
        wH += r.x;
        wN += r.yz;
    }

    // Stationary dome drops
    for (int i = 0; i < DROP_COUNT; i++) {
        float fi   = float(i);
        float life = 8.0 + hash21(vec2(fi, 88.8)) * 20.0;
        float ph   = hash21(vec2(fi, 77.7)) * life;
        float age  = mod(iTime + ph, life);
        float fade = smoothstep(0.0, 1.0, age) * smoothstep(life, life * 0.3, age);

        float epoch = floor((iTime + ph) / life);
        vec2 pos = vec2(
            hash21(vec2(fi * 3.1, epoch * 5.3)),
            hash21(vec2(fi * 7.3, epoch * 2.1))
        );
        float dr   = 0.004 + hash21(vec2(fi, 66.6)) * 0.008;
        vec2  dd   = (uv - pos) * vec2(ar, 1.0);
        float dist = length(dd);
        float dh   = smoothstep(dr, dr * 0.1, dist) * fade;
        vec2  dn   = -dd / max(dist, 0.0001) * dh;
        wH += dh;
        wN += dn;
    }

    wH = clamp(wH, 0.0, 1.0);
    float isWet = smoothstep(0.01, 0.08, wH);

    // ── Terminal + chromatic aberration through water ─────────────────
    vec3 terminal = texture(iChannel0, uv).rgb;
    vec2 refract  = wN * REFRACT_STRENGTH;

    float spread = CHROMA_SPREAD * 0.5;
    vec3 clean = vec3(
        texture(iChannel0, clamp(uv + refract * (1.0 - spread), 0.001, 0.999)).r,
        texture(iChannel0, clamp(uv + refract,                  0.001, 0.999)).g,
        texture(iChannel0, clamp(uv + refract * (1.0 + spread), 0.001, 0.999)).b
    );

    // Subtle specular
    float nMag  = length(wN);
    vec2  safeN = wN / max(nMag, 0.01);
    float spec  = max(dot(safeN, vec2(-0.5, -0.8)), 0.0);
    spec = spec * spec * nMag * SPECULAR;
    vec3 wetColor = clean + vec3(1.0, 0.97, 0.90) * spec;

    // ── Feedback ─────────────────────────────────────────────────────
    vec3 prev = texture(iChannel1, uv).rgb;

    if (iFrame < 3) {
        fragColor = vec4(terminal, texture(iChannel0, uv).a);
        return;
    }

    // Content change → reset to clean terminal
    float diff  = length(prev - terminal);
    float reset = step(0.15, diff);
    vec3  base  = mix(prev, terminal, reset);

    // ── Grime target ─────────────────────────────────────────────────
    float gNoise   = noise(fragCoord * 0.02) * 0.6
                   + noise(fragCoord * 0.08) * 0.4;
    float edgeDust = smoothstep(0.35, 1.0, length((uv - 0.5) * 2.0));

    float localDesat  = GRIME_DESAT  * (0.5 + edgeDust * 0.4 + gNoise * 0.3);
    float localWarmth = GRIME_WARMTH * (0.6 + edgeDust * 0.3 + gNoise * 0.2);

    float luma = dot(terminal, vec3(0.299, 0.587, 0.114));
    vec3  grimy = mix(terminal, vec3(luma), localDesat);
    grimy += vec3(localWarmth, localWarmth * 0.45, -localWarmth * 0.25);

    // Slight softening
    vec3 blurred = (
        texture(iChannel0, uv + vec2(px.x, 0.0)).rgb +
        texture(iChannel0, uv - vec2(px.x, 0.0)).rgb +
        texture(iChannel0, uv + vec2(0.0, px.y)).rgb +
        texture(iChannel0, uv - vec2(0.0, px.y)).rgb
    ) * 0.25;
    grimy = mix(grimy, blurred, GRIME_SOFTNESS);

    // ── Compose ──────────────────────────────────────────────────────
    float localRate = GRIME_RATE * (0.7 + gNoise * 0.6);
    vec3  dryResult = mix(base, grimy, localRate);
    vec3  color     = mix(dryResult, wetColor, isWet);

    fragColor = vec4(clamp(color, 0.0, 1.0), texture(iChannel0, uv).a);
}
