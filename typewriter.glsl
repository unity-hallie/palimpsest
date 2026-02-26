// Mycelium Typewriter — with memory and rain
// iChannel0 = terminal, iChannel1 = previous frame (feedback)
//
// Core halo:   organic bleed (0–3 px, domain-warped)
// Growth:      feedback-driven mycelium along fiber channels
// Stains:      warm watermarks that linger
// Water drops: occasional splashes that darken paper, spread ink, leave rings

float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }
float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1,311.7))) * 43758.5453); }
float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f*f*(3.0 - 2.0*f);
    return mix(mix(hash21(i),           hash21(i+vec2(1,0)), f.x),
               mix(hash21(i+vec2(0,1)), hash21(i+vec2(1,1)), f.x), f.y);
}
float fbm(vec2 p) {
    return noise(p)*.500 + noise(p*2.01+vec2(1.7,9.2))*.250
         + noise(p*4.03+vec2(8.3,2.8))*.125 + noise(p*8.07+vec2(3.1,7.4))*.063;
}
// Pseudopod edge: surface tension fingers reaching along paper fibers
float dropNoise(vec2 delta, float seed) {
    float angle = atan(delta.y, delta.x);
    // 3-5 dominant fingers — sharp peaks via pow(), each at its own angle
    float a1 = noise(vec2(seed * 13.1, seed * 7.3));  // finger count: 3–5
    float fingers = 3.0 + a1 * 2.0;
    float phase   = seed * 4.7;
    // Sharp fingers: raise sine lobes to a power so peaks are narrow
    float lobe = pow(max(0.0, sin(angle * fingers + phase)), 3.0);
    // Per-finger length variation
    float vary = noise(vec2(angle * 1.3 + seed * 9.1, seed * 2.3));
    // Fiber bias: slight stretch along paper grain (horizontal)
    float fiberBias = 0.15 * cos(angle * 2.0 + seed * 0.8);
    return (lobe * (0.4 + vary * 0.5) + fiberBias) * 0.5;
}
float inkness(vec2 uv) {
    return 1.0 - smoothstep(0.45, 0.72, luma(texture(iChannel0, uv).rgb));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec2 px = 1.0 / iResolution.xy;
    float t = iTime;
    float ar = iResolution.x / iResolution.y;

    // ── Water drops (before any sampling — they distort UVs) ──────────────
    vec2  sampleUV    = uv;
    vec2  feedbackUV  = uv;       // small per-frame warp → compounds in feedback loop
    float wetness     = 0.0;
    float waterRing   = 0.0;

    for (int i = 0; i < 3; i++) {
        float fi     = float(i);
        float period = 12.0 + hash21(vec2(fi, 0.0)) * 10.0;   // 12–22 sec apart
        float phase  = hash21(vec2(fi, 1.0)) * period;
        float age    = mod(t + phase, period);
        float life   = 14.0;

        if (age < life) {
            float cycle = floor((t + phase) / period);
            vec2 dropPos = clamp(
                vec2(hash21(vec2(cycle * 3.1, fi * 7.1 + 3.3)),
                     hash21(vec2(cycle * 3.1, fi * 3.7 + 11.3))),
                0.08, 0.92);

            vec2  delta = uv - dropPos;
            vec2  acDelta = delta * vec2(ar, 1.0);
            float dist  = length(acDelta);                       // aspect-corrected
            vec2  dir   = delta / max(length(delta), 0.001);     // raw UV direction

            float expand = smoothstep(0.0, 0.05, age);   // instant plop
            float dry    = smoothstep(life * 0.30, life, age);
            float maxR   = 0.10 + hash21(vec2(cycle, fi + 5.5)) * 0.08;  // 0.10–0.18

            // Irregular edge — fiber wicking makes water spread unevenly
            float edgeWarp = dropNoise(acDelta, cycle + fi) * maxR * 0.55;
            float r      = (maxR + edgeWarp) * expand * mix(1.0, 0.25, dry);

            // Wet interior — darker at rim, lighter at center (capillary wicking)
            float inDrop = smoothstep(r, r * 0.4, dist);
            float rimDark = smoothstep(r * 0.3, r, dist) * 0.6;  // rim emphasis
            float fibVar  = noise(fragCoord * 0.08 + vec2(cycle, fi)) * 0.3; // fiber variation
            float wet    = inDrop * (1.0 - dry) * (0.4 + rimDark + fibVar);
            wetness     += wet;

            // Water mark ring — also irregular
            float ringR     = (maxR + edgeWarp * 0.7) * expand * 0.80;
            float ringDist  = abs(dist - ringR);
            float ringWidth = maxR * 0.12 + 0.001;
            float ring      = exp(-ringDist * ringDist / (ringWidth * ringWidth));
            ring *= expand * (1.0 - dry * 0.70);
            waterRing += ring;

            // UV distortion: ink pushes outward + swirls from impact
            vec2 tangent = vec2(-dir.y, dir.x);  // perpendicular to radial
            float swirlPhase = noise(vec2(age * 0.8, cycle + fi)) - 0.5;
            vec2 push = dir + tangent * swirlPhase * 0.7;
            sampleUV   += push * wet * 0.003;
            // Feedback warp: tiny per-frame push that compounds over time
            feedbackUV += push * wet * 0.0004;
        }
    }
    // ── Downpour: ~50 drops over 30 seconds, every 3.5–5 minutes ────────
    // Triangular onset distribution: few drops at start/end, peak in the middle.
    // Eases in → several per second at peak → eases off.
    float stormPeriod = 210.0 + hash21(vec2(3.3, 7.7)) * 90.0;
    float stormAge    = mod(t, stormPeriod);
    float stormWindow = 30.0;

    if (stormAge < stormWindow + 14.0) {  // +14 for last drops to finish drying
        float stormCycle = floor(t / stormPeriod);
        for (int i = 0; i < 50; i++) {
            float fi = float(i);
            // Two randoms averaged → triangular distribution, clustered at center
            float r1 = hash21(vec2(fi * 2.3, stormCycle * 11.1 + 41.7));
            float r2 = hash21(vec2(fi * 3.7, stormCycle * 5.3 + 23.1));
            float onset = (r1 + r2) * 0.5 * stormWindow;

            float life = 7.0 + hash21(vec2(fi, stormCycle + 33.3)) * 5.0; // 7–12 sec
            float dAge = stormAge - onset;

            if (dAge > 0.0 && dAge < life) {
                vec2 dropPos = clamp(
                    vec2(hash21(vec2(stormCycle * 5.1, fi * 9.3 + 2.1)),
                         hash21(vec2(stormCycle * 5.1, fi * 4.7 + 17.3))),
                    0.05, 0.95);

                vec2  delta  = uv - dropPos;
                vec2  acDelta = delta * vec2(ar, 1.0);
                float dist   = length(acDelta);
                vec2  dir    = delta / max(length(delta), 0.001);

                float expand = smoothstep(0.0, 0.05, dAge);
                float dry    = smoothstep(life * 0.25, life, dAge);
                float maxR   = 0.04 + hash21(vec2(stormCycle, fi + 8.8)) * 0.09; // 0.04–0.13

                // Irregular edge — fiber wicking
                float edgeWarp = dropNoise(acDelta, stormCycle + fi * 1.7) * maxR * 0.55;
                float r      = (maxR + edgeWarp) * expand * mix(1.0, 0.25, dry);

                float inDrop = smoothstep(r, r * 0.4, dist);
                float rimDark = smoothstep(r * 0.3, r, dist) * 0.6;
                float fibVar  = noise(fragCoord * 0.08 + vec2(stormCycle, fi)) * 0.3;
                float wet    = inDrop * (1.0 - dry) * (0.4 + rimDark + fibVar);
                wetness     += wet;

                float ringR     = (maxR + edgeWarp * 0.7) * expand * 0.80;
                float ringDist  = abs(dist - ringR);
                float ringWidth = maxR * 0.12 + 0.001;
                float ring      = exp(-ringDist * ringDist / (ringWidth * ringWidth));
                ring *= expand * (1.0 - dry * 0.70);
                waterRing += ring;

                // Swirling distortion + feedback compounding
                vec2 tangent = vec2(-dir.y, dir.x);
                float swirlPhase = noise(vec2(dAge * 0.8, stormCycle + fi)) - 0.5;
                vec2 push = dir + tangent * swirlPhase * 0.7;
                sampleUV   += push * wet * 0.0024;
                feedbackUV += push * wet * 0.0003;
            }
        }
    }

    wetness   = clamp(wetness,   0.0, 1.0);
    waterRing = clamp(waterRing, 0.0, 1.0);

    // ── Paper (static grain) ──────────────────────────────────────────────
    vec2 gp = fragCoord * 0.13;
    float fib  = noise(gp)                              * 0.500;
    fib       += noise(gp * 2.10 + vec2(3.1, 7.4))      * 0.250;
    fib       += noise(gp * 5.70 + vec2(8.3, 2.8))      * 0.125;
    fib       += noise(gp * 14.0 + vec2(1.2, 5.1))      * 0.063;
    fib       += noise(gp * 38.0 + vec2(4.4, 9.2))      * 0.031;
    fib        = mix(fib, noise(vec2(fragCoord.x*0.045, fragCoord.y*4.0)), 0.18);

    // Laid finish: faint parallel lines from the paper mold
    float laid = sin(fragCoord.y * 0.95) * 0.004 + sin(fragCoord.y * 1.9) * 0.002;

    vec3 paper = vec3(0.952, 0.940, 0.918);    // cooler, cleaner white — heavy cotton stock
    paper += vec3( 0.010,  0.008, -0.003) * (fib - 0.5) * 1.4;   // subtler grain
    paper += vec3( 0.003,  0.003,  0.002) * (noise(fragCoord * 1.3) - 0.5);
    paper += laid;                              // laid finish lines
    vec2 vig = (uv - 0.5) * 2.0;
    float vigAmt = dot(vig*vig, vec2(0.040, 0.030));
    paper = paper * (1.0 - vigAmt) + vec3(0.016, 0.009, -0.009) * vigAmt;

    // Wet paper: darker, warmer
    paper *= 1.0 - wetness * 0.055;
    paper -= vec3(-0.005, 0.000, 0.010) * wetness;
    // Water ring stain
    paper -= vec3(0.022, 0.018, 0.012) * waterRing;

    float paperL = luma(paper);

    // ── Terminal (sampled with water-distorted UVs) ───────────────────────
    vec4  term = texture(iChannel0, sampleUV);
    float ink  = inkness(sampleUV);
    float wT   = t * 0.0045;
    vec2  ws   = fragCoord * 0.048;
    vec2  warp = vec2(fbm(ws + vec2(wT,  0.0)) - 0.5,
                      fbm(ws + vec2(0.0, wT) + vec2(4.3, 1.7)) - 0.5);

    // ── Core halo (0–3 px, more organic) ──────────────────────────────────
    float coreBleed = 0.0;
    vec3  coreCol   = vec3(0.0);
    float cwsum     = 0.0;
    for (int x = -2; x <= 2; x++) {
        for (int y = -2; y <= 2; y++) {
            vec2  off  = vec2(float(x), float(y));
            float dist = length(off);
            if (dist < 0.5 || dist > 2.5) continue;
            vec2  woff = off + warp * dist * 1.6;          // stronger warp
            float w    = exp(-dot(woff,woff) * 0.17);      // wider gaussian
            vec2  nuv  = sampleUV + woff * px;
            float ni   = inkness(nuv);
            vec3  nc   = texture(iChannel0, nuv).rgb;
            coreBleed += ni * w;
            coreCol   += mix(paper, nc*0.68 + vec3(0.11,0.07,0.02), 0.38) * ni * w;
            cwsum     += w;
        }
    }
    coreBleed /= max(cwsum, 0.001);
    coreCol   /= max(cwsum * coreBleed + 0.0001, 0.0001);

    // Ink runs on wet paper
    coreBleed = clamp(coreBleed * (1.0 + wetness * 2.5), 0.0, 1.0);

    // Fresh frame: paper + core halo + text
    float coreMask = smoothstep(0.04, 0.52, coreBleed) * (1.0 - ink);
    vec3  fresh    = paper;
    fresh = mix(fresh, coreCol, coreMask * 0.85);
    fresh -= 0.028 * smoothstep(0.01, 0.18, coreBleed) * (1.0-ink) * (1.0-coreMask);
    fresh = mix(fresh, term.rgb, ink);

    // ── Previous frame + adaptive fade ────────────────────────────────────
    // Read feedback at slightly warped UV while wet — compounds ink migration
    // When drops dry, feedbackUV == uv, so smeared ink freezes in place
    vec3 prev = texture(iChannel1, feedbackUV).rgb;
    if (iFrame < 3) prev = paper;

    // Rapid changes (cursor, scroll) fade fast; settled stains linger
    float rapidClear = smoothstep(0.0, 0.15, luma(term.rgb) - luma(prev));
    // How much darker than paper is this pixel? Deep stains = dissolved ink
    float stainDepth = clamp((paperL - luma(prev)) / 0.15, 0.0, 1.0);
    // Deep stains fade ~5x slower — dissolved ink soaked into fiber
    float baseFade   = mix(0.008, 0.0016, stainDepth);
    float dryFade    = mix(baseFade, 0.22, rapidClear);
    // Still even slower while actively wet
    float fadeRate   = mix(dryFade, dryFade * 0.15, wetness);

    vec3 warmPaper = paper + vec3(0.008, 0.004, -0.004);
    vec3 faded     = mix(prev, warmPaper, fadeRate);

    // ── Growth along fiber channels ───────────────────────────────────────
    float neighborStain = 0.0;
    vec3  stainCol      = vec3(0.0);
    float stainW        = 0.0;
    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            if (x == 0 && y == 0) continue;
            vec2  off = vec2(float(x), float(y)) + warp * 0.6;
            vec2  nuv = uv + off * px;
            vec3  ns  = texture(iChannel1, nuv).rgb;
            float nd  = max(0.0, paperL - luma(ns));
            float w   = 1.0 / (length(off) + 0.25);
            neighborStain += nd * w;
            float hasStain = step(0.003, nd);
            stainCol      += ns * w * hasStain;
            stainW        += w * hasStain;
        }
    }
    neighborStain /= 6.0;
    stainCol = (stainW > 0.001) ? stainCol / stainW : paper;

    vec2  fms = fragCoord * 0.040 + vec2(wT * 1.3, -wT * 0.65);
    float fil = smoothstep(0.42, 0.58, fbm(fms))
              + smoothstep(0.44, 0.60, noise(fragCoord*0.082 + vec2(wT*1.8, 0.0))) * 0.5;
    fil = smoothstep(0.15, 0.75, clamp(fil, 0.0, 1.0));

    // Growth: visible tendrils along fiber channels, faster in wet areas
    float baseGrowth = clamp(neighborStain * fil * 2.0, 0.0, 0.010);
    float wetGrowth  = clamp(neighborStain * 0.14, 0.0, 0.05) * wetness;
    vec3  withGrowth = mix(faded, stainCol, baseGrowth + wetGrowth);

    // ── Final composite ───────────────────────────────────────────────────
    // Stain floor scales with depth: light ghosts cap at 93%, deep dissolved ink at 78%
    // Active wetness pushes even lower (70%)
    float depthFloor    = mix(0.93, 0.78, stainDepth);
    vec3  stainFloor    = paper * mix(depthFloor, 0.70, wetness);
    vec3  clampedMemory = max(withGrowth, stainFloor);
    vec3  color         = min(fresh, clampedMemory);

    fragColor = vec4(color, term.a);
}
