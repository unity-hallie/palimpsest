// lichen.glsl -- crustose lichen colonies on dark stone
//
// No compute. Domain-warped noise for organic patch shapes.
// Sparse coverage -- mostly bare stone with a few distinct colonies.
//
// iChannel0 = terminal content

#define GROWTH_SPEED  0.005
#define COLONIZE_TIME 300.0   // seconds to reach full coverage (~5 min)
#define BG_COLOR      vec3(0.05, 0.05, 0.06)

float hash2(vec2 p) {
    p = fract(p * vec2(127.1, 311.7));
    p += dot(p, p.yx + 19.19);
    return fract(p.x * p.y);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash2(i);
    float b = hash2(i + vec2(1.0, 0.0));
    float c = hash2(i + vec2(0.0, 1.0));
    float d = hash2(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm3(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 3; i++) { v += a * noise(p); p *= 2.1; a *= 0.5; }
    return v;
}

// Domain warp: displace coordinates using fbm, then sample fbm again
// This creates organic, tendril-like shapes instead of round blobs
float warpedFbm(vec2 p, float warpStr) {
    vec2 q = vec2(fbm3(p), fbm3(p + vec2(5.2, 1.3)));
    return fbm3(p + q * warpStr);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    vec4 termRaw = texture(iChannel0, uv);
    vec3 term = termRaw.rgb;
    float textLuma = dot(term, vec3(0.299, 0.587, 0.114));
    float distFromBg = length(term - BG_COLOR);
    float textMask = smoothstep(0.03, 0.14, distFromBg);
    textMask = max(textMask, smoothstep(0.06, 0.20, textLuma));

    float t = iTime * GROWTH_SPEED;

    // -- Stone ----------------------------------------------------
    float grain0 = noise(uv * 18.0);
    float grain1 = noise(uv * 50.0);
    float stoneGrain = grain0 * 0.12 + grain1 * 0.05;
    vec3 stone = BG_COLOR + vec3(stoneGrain * 0.6, stoneGrain * 0.5, stoneGrain * 0.4);
    stone *= 0.85 + 0.15 * grain0;

    // -- Crack network (shared, but only visible inside patches) --
    float cr0 = noise(uv * 70.0);
    float cr1 = noise(uv * 48.0 + 33.0);
    float crackAO = 0.45 + 0.55 * smoothstep(0.20, 0.45, min(cr0, cr1));

    // -- Colonization curve ---------------------------------------
    // growth: 0 at t=0 (bare stone), 1 at COLONIZE_TIME (full)
    // Eases in slowly -- first specks appear around 20%, big patches by 60%
    float growth = clamp(iTime / COLONIZE_TIME, 0.0, 1.0);
    growth = growth * growth * (3.0 - 2.0 * growth);  // smoothstep shape

    vec3 lichenColor = vec3(0.0);
    float totalPatch = 0.0;

    // -- Colony 0: large Caloplaca -- orange, domain-warped -------
    // Appears ~30% into colonization, reaches full size last
    {
        float colGrowth = smoothstep(0.30, 0.90, growth);
        vec2 p0 = uv * vec2(2.8, 2.2) + vec2(t * 0.2, t * 0.08);
        float w0 = warpedFbm(p0, 1.2);
        // Threshold drops as colony grows -- starts invisible, expands
        float thresh = mix(0.85, 0.52, colGrowth) + 0.04 * sin(t * 1.2);
        float patch = smoothstep(thresh, thresh + 0.05, w0);
        float depth = smoothstep(thresh, thresh + 0.18, w0);
        // SSS at thin edges
        float sss = (1.0 - depth) * patch;
        vec3 col = mix(
            vec3(0.65, 0.38, 0.08),  // warm translucent edge
            vec3(0.45, 0.16, 0.03),  // deep opaque center
            depth
        );
        col *= 0.82 + 0.18 * noise(uv * 35.0 + 1.3);
        col += vec3(0.12, 0.05, 0.01) * sss;
        col *= mix(crackAO, 1.0, 0.3);  // cracks subtler on big colonies
        lichenColor += col * patch;
        totalPatch = max(totalPatch, patch);
    }

    // -- Colony 1: medium Xanthoparmelia -- grey-green, less warp --
    // Appears ~20% in
    {
        float colGrowth = smoothstep(0.20, 0.75, growth);
        vec2 p1 = uv * vec2(4.5, 3.8) + vec2(18.0 + t * 0.15, 9.0 - t * 0.1);
        float w1 = warpedFbm(p1, 0.9);
        float thresh = mix(0.82, 0.50, colGrowth) + 0.04 * sin(t * 1.8 + 3.0);
        float patch = smoothstep(thresh, thresh + 0.04, w1);
        float depth = smoothstep(thresh, thresh + 0.14, w1);
        float sss = (1.0 - depth) * patch;
        vec3 col = mix(
            vec3(0.20, 0.24, 0.13),
            vec3(0.13, 0.15, 0.11),
            depth
        );
        col *= 0.78 + 0.22 * noise(uv * 40.0 + 8.7);
        col += vec3(0.03, 0.06, 0.02) * sss;
        col *= crackAO;
        float vis = patch * (1.0 - totalPatch * 0.8);
        lichenColor += col * vis;
        totalPatch = max(totalPatch, vis);
    }

    // -- Colony 2: small scattered Candelaria -- yellow spots ------
    // First visible species -- tiny specks appear ~10% in
    {
        float colGrowth = smoothstep(0.10, 0.55, growth);
        vec2 p2 = uv * vec2(8.0, 6.5) + vec2(35.0 - t * 0.3, 20.0 + t * 0.15);
        float w2 = warpedFbm(p2, 0.5);
        float thresh = mix(0.80, 0.57, colGrowth) + noise(uv * 10.0 + 12.0) * 0.05;
        float patch = smoothstep(thresh, thresh + 0.03, w2);
        float depth = smoothstep(thresh, thresh + 0.08, w2);
        vec3 col = mix(
            vec3(0.60, 0.50, 0.10),
            vec3(0.45, 0.38, 0.05),
            depth
        );
        col *= 0.85 + 0.15 * noise(uv * 50.0 + 15.0);
        col += vec3(0.08, 0.06, 0.0) * (1.0 - depth) * patch;
        col *= crackAO;
        float vis = patch * (1.0 - totalPatch * 0.7);
        lichenColor += col * vis;
        totalPatch = max(totalPatch, vis);
    }

    // -- Colony 3: tiny dark Buellia specks -- nearly black --------
    // Pioneer species -- first to appear (~5%)
    {
        float colGrowth = smoothstep(0.05, 0.40, growth);
        vec2 p3 = uv * vec2(11.0, 9.0) + vec2(55.0, 38.0);
        float w3 = warpedFbm(p3, 0.3);
        float thresh = mix(0.78, 0.60, colGrowth) + noise(uv * 14.0 + 20.0) * 0.04;
        float patch = smoothstep(thresh, thresh + 0.02, w3);
        vec3 col = vec3(0.06, 0.055, 0.04) * (0.9 + 0.1 * noise(uv * 55.0));
        col *= crackAO;
        float vis = patch * (1.0 - totalPatch * 0.5);
        lichenColor += col * vis;
        totalPatch = max(totalPatch, vis);
    }

    // -- Lighting: flat matte hemisphere --------------------------
    float hemi = 0.7 + 0.3 * (1.0 - uv.y);

    // -- Compose --------------------------------------------------
    vec3 color = mix(stone, lichenColor, totalPatch * 0.92);
    color *= hemi;
    color = mix(color, term, textMask);

    // -- Focus dim ------------------------------------------------
    float focusT   = clamp((iTime - iTimeFocus) * 1.5, 0.0, 1.0);
    float focusMix = iFocus == 1 ? focusT : 1.0 - focusT;
    float grey     = dot(color, vec3(0.299, 0.587, 0.114));
    color = mix(vec3(grey), color, mix(0.3, 1.0, focusMix)) * mix(0.55, 1.0, focusMix);

    fragColor = vec4(clamp(color, 0.0, 1.0), termRaw.a);
}
