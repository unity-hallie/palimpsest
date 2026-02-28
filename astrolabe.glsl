// astrolabe.glsl — terminal as sepia ink on aged vellum
//
// iChannel0 = terminal content
//
// Background: faint astrolabe rings, azimuth lines, ecliptic arc, and an
// ink-dot star field — like da Vinci's astrogation tables drafted at night.
// Terminal text presses into the parchment as hand-inked marks.
// Grain is alive (slow iTime seed) so it never quite settles.

float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

float hash21(vec2 p) {
    p = fract(p * vec2(127.1, 311.7));
    p += dot(p, p.yx + 19.19);
    return fract(p.x * p.y);
}
float vnoise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i),          hash21(i + vec2(1,0)), f.x),
               mix(hash21(i + vec2(0,1)), hash21(i + vec2(1,1)), f.x), f.y);
}
float fbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) { v += a * vnoise(p); p = p * 2.1 + vec2(1.7, 9.2); a *= 0.5; }
    return v;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2  uv  = fragCoord / iResolution.xy;
    vec2  px  = 1.0 / iResolution.xy;
    float asp = iResolution.x / iResolution.y;

    // Centered, aspect-corrected coords (r=0.5 = half screen height)
    vec2  c   = (uv - 0.5) * vec2(asp, 1.0);
    float r   = length(c);
    float th  = atan(c.y, c.x);

    // ── Aged vellum ───────────────────────────────────────────────────────────
    vec3 vellum = vec3(0.924, 0.866, 0.715);
    vellum -= fbm(uv * 2.8 + vec2(3.71, 1.23)) * 0.090;
    vellum -= fbm(uv * 1.1 + vec2(0.31, 2.54)) * 0.045;
    // Horizon darkening — corners age faster
    vellum *= 0.87 + 0.13 * (1.0 - smoothstep(0.18, 0.62, length(uv - 0.5) * 1.5));
    // Paper fiber (very subtle horizontal weave)
    vellum += vnoise(uv * vec2(110.0, 4.0)) * 0.010 * vec3(0.9, 0.8, 0.6);
    // Living grain — slow seed shift prevents freeze-frame look
    vellum += (hash21(uv * iResolution.xy + iTime * 0.28) - 0.5) * 0.035;
    vellum  = clamp(vellum, 0.0, 1.0);

    vec3  inkD  = vec3(0.130, 0.080, 0.030);   // fresh dark sepia
    vec3  inkF  = vec3(0.590, 0.445, 0.260);   // faded/weathered ink
    float chart = 0.0;                          // chart ink accumulator [0,1]

    // ── Astrolabe rings ───────────────────────────────────────────────────────
    float rFade = smoothstep(0.0, 0.04, r);

    // Five major rings — middle one heavier (the "equator")
    chart = max(chart, smoothstep(0.0013, 0.0, abs(r - 0.11)) * rFade * 0.36);
    chart = max(chart, smoothstep(0.0013, 0.0, abs(r - 0.21)) * rFade * 0.33);
    chart = max(chart, smoothstep(0.0022, 0.0, abs(r - 0.32)) * rFade * 0.42); // equator
    chart = max(chart, smoothstep(0.0013, 0.0, abs(r - 0.41)) * rFade * 0.30);
    chart = max(chart, smoothstep(0.0013, 0.0, abs(r - 0.49)) * rFade * 0.26);

    // Fine tick rings every 0.024
    for (int i = 1; i <= 24; i++) {
        chart = max(chart, smoothstep(0.00055, 0.0, abs(r - float(i) * 0.024)) * rFade * 0.085);
    }

    // ── Azimuth / radial lines ────────────────────────────────────────────────
    float angStep = 6.28318 / 24.0;                          // 24 spokes = 15° each
    float nearAng = mod(th + angStep * 0.5, angStep) - angStep * 0.5;
    chart = max(chart, smoothstep(0.0038, 0.0, abs(nearAng)) * smoothstep(0.04, 0.08, r) * 0.18);

    // Cardinal axes (N/S/E/W) — heavier weight
    float cardAng = mod(th + 0.7854, 1.5708) - 0.7854;
    chart = max(chart, smoothstep(0.0052, 0.0, abs(cardAng)) * smoothstep(0.04, 0.08, r) * 0.38);

    // ── Ecliptic — tilted great-circle arc ────────────────────────────────────
    float tilt = 0.408; // ~23.4° (Earth's axial tilt)
    vec2  ecP  = mat2(cos(tilt), -sin(tilt), sin(tilt), cos(tilt)) * c;
    float ecR  = length(ecP * vec2(1.0, 1.28)); // slightly elliptical projection
    chart = max(chart, smoothstep(0.0016, 0.0, abs(ecR - 0.42)) * 0.30);

    // Second concentric ellipse (tropic of cancer / capricorn feel)
    float ecR2 = length(ecP * vec2(1.0, 1.28)) * 0.72;
    chart = max(chart, smoothstep(0.0010, 0.0, abs(ecR2 - 0.30)) * 0.18);

    // ── Ink star field ────────────────────────────────────────────────────────
    // Three dot layers: coarse → medium → fine — each progressively dimmer
    for (int i = 0; i < 3; i++) {
        float fi   = float(i);
        float dens = 26.0 + fi * 16.0;
        vec2  cell = floor(uv * dens);
        vec2  frac = fract(uv * dens);
        float h    = hash21(cell * (fi * 1.1 + 1.0));
        if (h > 0.895 - fi * 0.025) {
            vec2  ctr = vec2(fract(h * 13.73), fract(h * 7.19));
            float d   = length(frac - ctr);
            float sz  = (0.8 + h * 2.4) / dens;
            chart = max(chart, exp(-d * d / (sz * sz)) * (0.20 + h * 0.36) * (0.52 - fi * 0.09));
        }
    }

    // Bright navigation stars as tiny ink crosses (~40)
    for (int i = 0; i < 42; i++) {
        float h  = hash21(vec2(float(i) * 1.618, 17.3));
        float h2 = hash21(vec2(float(i) * 2.718,  7.9));
        if (h > 0.50) {
            vec2  sp  = vec2(h, h2);           // position in UV space
            vec2  d   = uv - sp;
            float sz  = 0.0006 + h * 0.0009;   // cross arm half-width
            float arm = max(
                smoothstep(sz, 0.0, abs(d.x)) * step(abs(d.y), sz * 2.8),
                smoothstep(sz, 0.0, abs(d.y)) * step(abs(d.x), sz * 2.8)
            );
            chart = max(chart, arm * (0.26 + h * 0.26));
        }
    }

    // ── Terminal content → pressed ink ───────────────────────────────────────
    float textL = luma(texture(iChannel0, uv).rgb);

    // Ink bleed: characters wick slightly into surrounding paper fibres
    float bleed = 0.0;
    for (int i = 0; i < 8; i++) {
        float a = 6.28318 * float(i) / 8.0;
        bleed += luma(texture(iChannel0, clamp(uv + vec2(cos(a), sin(a)) * px * 1.7, 0.001, 0.999)).rgb);
    }
    bleed /= 8.0;

    float inkDensity = clamp(textL + bleed * 0.30, 0.0, 1.0);

    // ── Composite ─────────────────────────────────────────────────────────────
    vec3 color = vellum;
    color = mix(color, inkF,  chart * 0.72);          // chart + stars in faded ink
    color = mix(color, inkD,  inkDensity * 0.93);      // text as dark pressed ink
    // Bleed halo — ink wicks out, edges lighter than core
    color = mix(color, mix(inkD, vellum, 0.45), (bleed - textL * 0.5) * 0.22);

    // Warm vignette (candle-lit corners)
    color *= 0.89 + 0.11 * (1.0 - smoothstep(0.28, 0.70, length(uv - 0.5) * 1.8));

    fragColor = vec4(clamp(color, 0.0, 1.0), texture(iChannel0, uv).a);
}
