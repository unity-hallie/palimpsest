// Glasshouse — frosted glass at night
// Looking through a frosted window at a garden in a storm.
// Rain rivulets run down the glass, clearing the frost, revealing the garden.
// Terminal text glows on the glass surface like a HUD.
//
// iChannel0 = terminal

// ── Tuning ──────────────────────────────────────────────────────────
#define FROST_OPACITY     0.72    // How opaque the glass film is (0 = clear, 1 = white)
#define RIVULET_COUNT     50      // Number of rain rivulet paths
#define STORM_PERIOD      90.0    // Primary storm cycle (seconds)
#define GLOW_RADIUS       5.0     // Text bloom radius (pixels)
#define GLOW_STRENGTH     0.28    // How much text glows into frost
// =========================

float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }
float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i),           hash21(i+vec2(1,0)), f.x),
               mix(hash21(i+vec2(0,1)), hash21(i+vec2(1,1)), f.x), f.y);
}
float fbm(vec2 p) {
    return noise(p)*.5000 + noise(p*2.01+vec2(1.7,9.2))*.2500
         + noise(p*4.03+vec2(8.3,2.8))*.1250 + noise(p*8.07+vec2(3.1,7.4))*.0625
         + noise(p*16.1+vec2(5.4,1.2))*.0313;
}

vec3 garden(vec2 uv, float ar, float t) {
    // Night garden — abstract, impressionistic
    vec3 sky    = vec3(0.012, 0.018, 0.048);
    vec3 ground = vec3(0.008, 0.025, 0.010);
    vec3 col    = mix(ground, sky, smoothstep(0.12, 0.72, uv.y));

    // Foliage masses
    float sway = sin(t * 0.3 + uv.y * 3.0) * 0.004;
    vec2 fuv = uv + vec2(sway, 0.0);
    float foliage = fbm(fuv * vec2(4.5, 3.0) + vec2(1.3, 7.4));
    float hedge = smoothstep(0.30, 0.55, foliage);
    vec3 green = mix(vec3(0.012, 0.045, 0.015), vec3(0.030, 0.100, 0.025), foliage);
    col = mix(col, green, hedge * smoothstep(0.08, 0.45, uv.y) * smoothstep(0.82, 0.55, uv.y));

    // Tree trunk
    float trunk = exp(-pow((uv.x - 0.58) * ar * 8.0, 2.0)) * smoothstep(0.15, 0.50, uv.y);
    col = mix(col, vec3(0.015, 0.012, 0.008), trunk * 0.5);

    // Warm lantern
    vec2 lamp = vec2(0.32, 0.26);
    float ld = length((uv - lamp) * vec2(ar, 1.0));
    col += vec3(0.28, 0.16, 0.04) * exp(-ld * ld * 10.0) * 0.70;

    // Second light
    vec2 lamp2 = vec2(0.76, 0.20);
    float ld2 = length((uv - lamp2) * vec2(ar, 1.0));
    col += vec3(0.09, 0.06, 0.02) * exp(-ld2 * ld2 * 18.0) * 0.30;

    return max(col, 0.0);
}

// One generation of a rivulet: bead + refreezing trail
float rivuletGen(vec2 uv, float ar, float age, float genSeed, float baseSpeed) {
    // Path: mostly vertical with gentle S-curve hesitation
    float baseX = 0.05 + hash21(vec2(genSeed, 5.5)) * 0.90;
    float rawWander = noise(vec2(genSeed * 7.1, uv.y * 3.5));
    float wander = (pow(rawWander, 0.6) - 0.5) * 0.07;
    float fine   = (noise(vec2(genSeed * 11.3, uv.y * 15.0)) - 0.5) * 0.006;
    float pathX  = baseX + wander + fine;

    float dx = abs((uv.x - pathX) * ar);
    float width = 0.003 + hash21(vec2(genSeed, 6.6)) * 0.004;
    float inPath = exp(-dx * dx / (width * width));

    float beadY = -0.02 + age * baseSpeed;

    // Bead: visible only while on screen
    float beadPathX = baseX
        + (pow(noise(vec2(genSeed * 7.1, beadY * 3.5)), 0.6) - 0.5) * 0.07
        + (noise(vec2(genSeed * 11.3, beadY * 15.0)) - 0.5) * 0.006;
    float beadDist = length((uv - vec2(beadPathX, beadY)) * vec2(ar, 1.0));
    float onScreen = step(0.0, beadY) * step(beadY, 1.04);
    float bead = smoothstep(0.007, 0.001, beadDist) * onScreen;

    // Trail: only where bead has passed (uv.y between 0 and beadY)
    // timeSinceBead drives the gradual refreeze
    float passed = step(0.0, beadY - uv.y) * step(uv.y, 1.0);
    float timeSinceBead = max(0.0, beadY - uv.y) / max(baseSpeed, 0.001);
    float refreeze = smoothstep(14.0, 0.0, timeSinceBead);
    float trail = passed * refreeze * 0.50;

    return clamp(inPath * (trail + bead), 0.0, 1.0);
}

// Rivulet slot: runs two overlapping generations so there's never a pop
float rivulet(vec2 uv, float ar, float t, float seed) {
    float baseSpeed = 0.05 + hash21(vec2(seed, 3.3)) * 0.05;
    float fallTime  = 1.06 / baseSpeed;
    float cycleLen  = fallTime + 16.0;

    float rawTime = t + hash21(vec2(seed, 2.2)) * cycleLen;
    float gen     = floor(rawTime / cycleLen);
    float age     = rawTime - gen * cycleLen;

    // Current generation
    float genSeed0 = hash21(vec2(seed, gen * 5.1 + 3.3));
    float r0 = rivuletGen(uv, ar, age, genSeed0, baseSpeed);

    // Previous generation (still refreezing)
    float genSeed1 = hash21(vec2(seed, (gen - 1.0) * 5.1 + 3.3));
    float r1 = rivuletGen(uv, ar, age + cycleLen, genSeed1, baseSpeed);

    return max(r0, r1);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2  uv = fragCoord / iResolution.xy;
    vec2  px = 1.0 / iResolution.xy;
    float ar = iResolution.x / iResolution.y;
    float t  = iTime;

    // ── Storm intensity (multi-scale weather) ───────────────────────
    float w1 = sin(t * 6.2832 / STORM_PERIOD) * 0.5 + 0.5;
    float w2 = sin(t * 6.2832 / (STORM_PERIOD * 2.7) + 2.1) * 0.5 + 0.5;
    float w3 = sin(t * 6.2832 / (STORM_PERIOD * 6.5) + 5.3) * 0.5 + 0.5;
    float stormIntensity = pow(w1 * w2, 1.5) * smoothstep(0.25, 0.65, w3);

    // ── Rain rivulets (procedural, no feedback needed) ──────────────
    float water = 0.0;
    // Active rivulet count scales with storm intensity
    int activeCount = int(float(RIVULET_COUNT) * (0.15 + stormIntensity * 0.85));

    for (int i = 0; i < RIVULET_COUNT; i++) {
        if (i >= activeCount) break;
        water += rivulet(uv, ar, t, float(i) * 1.37);
    }
    water = clamp(water, 0.0, 1.0);

    // Stationary drops: small beads that sit on the glass between rivulets
    for (int i = 0; i < 6; i++) {
        float fi = float(i);
        float dropLife = 10.0 + hash21(vec2(fi, 88.8)) * 15.0;
        float dropAge = mod(t + hash21(vec2(fi, 77.7)) * dropLife, dropLife);
        float fade = smoothstep(0.0, 0.5, dropAge) * smoothstep(dropLife, dropLife * 0.6, dropAge);
        vec2 dropPos = vec2(
            hash21(vec2(fi * 3.1, floor((t + hash21(vec2(fi, 77.7)) * dropLife) / dropLife) * 5.3)),
            hash21(vec2(fi * 7.3, floor((t + hash21(vec2(fi, 77.7)) * dropLife) / dropLife) * 2.1))
        );
        float dist = length((uv - dropPos) * vec2(ar, 1.0));
        float dropR = 0.006 + hash21(vec2(fi, 66.6)) * 0.010;
        water += smoothstep(dropR, dropR * 0.3, dist) * fade * 0.7;
    }
    water = clamp(water, 0.0, 1.0);

    // ── Frost: uniform translucent film ─────────────────────────────
    // Just a flat semi-opaque layer — like real frosted glass
    // Only texture is very fine grain from the glass surface itself
    float fineGrain = noise(fragCoord * 0.15) * 0.04;
    float frost = FROST_OPACITY + fineGrain;

    // Rain clears the frost where rivulets flow
    float frostClear = smoothstep(0.05, 0.45, water);
    frost *= (1.0 - frostClear * 0.85);

    // Slightly thicker at edges (window frame is colder)
    float edgeDist = length((uv - 0.5) * 2.0);
    frost += smoothstep(0.5, 1.3, edgeDist) * 0.08;
    frost = clamp(frost, 0.0, 1.0);

    // ── Garden (behind glass) ───────────────────────────────────────
    vec2 gardenUV = uv;
    // Slight refraction through the glass
    gardenUV += vec2(
        noise(uv * 18.0) - 0.5,
        noise(uv * 18.0 + vec2(5.5, 3.3)) - 0.5
    ) * 0.008;
    // Water drops act as tiny lenses
    gardenUV += vec2(
        noise(uv * 14.0 + t * 0.06) - 0.5,
        noise(uv * 14.0 + vec2(3.1, 7.4) + t * 0.06) - 0.5
    ) * water * 0.012;

    vec3 gardenCol = garden(gardenUV, ar, t);

    // ── Compositing ─────────────────────────────────────────────────
    // Frost film: translucent blue-grey wash over the garden
    vec3 frostTint = vec3(0.14, 0.17, 0.22);  // the color of the frosted film
    vec3 color = mix(gardenCol, frostTint, frost);

    // Wet glass: where water is, slightly darker and clearer
    color = mix(color, color * 0.92 + vec3(0.004, 0.007, 0.014), water * 0.30);

    // Fine condensation grain
    float grain = (noise(fragCoord * 0.28) - 0.5) * 0.008;
    color += grain;

    // ── Terminal text: glowing HUD ──────────────────────────────────
    vec4  term    = texture(iChannel0, uv);
    float textVal = luma(term.rgb);

    // 8-tap glow halo
    float gR  = GLOW_RADIUS * px.x;
    float gRy = GLOW_RADIUS * px.y;
    float glow = 0.0;
    glow += luma(texture(iChannel0, uv + vec2(-gR,   0.0)).rgb);
    glow += luma(texture(iChannel0, uv + vec2( gR,   0.0)).rgb);
    glow += luma(texture(iChannel0, uv + vec2( 0.0, -gRy)).rgb);
    glow += luma(texture(iChannel0, uv + vec2( 0.0,  gRy)).rgb);
    glow += luma(texture(iChannel0, uv + vec2(-gR,  -gRy)).rgb) * 0.7;
    glow += luma(texture(iChannel0, uv + vec2( gR,  -gRy)).rgb) * 0.7;
    glow += luma(texture(iChannel0, uv + vec2(-gR,   gRy)).rgb) * 0.7;
    glow += luma(texture(iChannel0, uv + vec2( gR,   gRy)).rgb) * 0.7;
    glow /= 5.6;

    vec3 glowCol = vec3(0.50, 0.60, 0.80);

    // Text glow scatters in the frosted film
    color += glowCol * glow * GLOW_STRENGTH * (0.3 + frost * 0.7);

    // Text on glass surface
    color = mix(color, term.rgb, textVal * 0.94);
    // Soft bloom
    color += glowCol * glow * 0.10 * (1.0 - textVal);

    // ── Window frame vignette ───────────────────────────────────────
    float vig = 1.0 - 0.25 * pow(length((uv - 0.5) * vec2(1.1, 0.9)), 2.0);
    color *= vig;

    fragColor = vec4(clamp(color, 0.0, 1.0), term.a);
}
