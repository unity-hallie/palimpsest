// lichen.glsl -- crustose lichen colonies on dark stone
//
// No compute. Domain-warped noise for organic patch shapes.
// Colonies grow in over ~5 minutes from bare stone.
//
// iChannel0 = terminal content

#define GROWTH_SPEED  0.005
#define COLONIZE_TIME 300.0
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

// Domain warp: organic tendril shapes
// Returns [0,1] -- raw fbm after warp is ~[0.03, 0.37], remapped
float warpedFbm(vec2 p, float warpStr) {
    vec2 q = vec2(fbm3(p), fbm3(p + vec2(5.2, 1.3)));
    float raw = fbm3(p + q * warpStr);
    return clamp((raw - 0.03) * 2.94, 0.0, 1.0);
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
    float growth = clamp(iTime / COLONIZE_TIME, 0.0, 1.0);
    growth = growth * growth * (3.0 - 2.0 * growth);

    // -- Stone --------------------------------------------------------
    float grain = noise(uv * 18.0) * 0.12 + noise(uv * 50.0) * 0.05;
    vec3 stone = BG_COLOR + vec3(grain * 0.6, grain * 0.5, grain * 0.4);

    // -- Crack network (only visible inside patches) ------------------
    float cr0 = noise(uv * 30.0);
    float cr1 = noise(uv * 22.0 + 33.0);
    float crackAO = 0.5 + 0.5 * smoothstep(0.22, 0.42, min(cr0, cr1));

    vec3 color = stone;
    float totalPatch = 0.0;

    // -- Colony 0: large Caloplaca -- vivid orange --------------------
    float g0 = smoothstep(0.30, 0.90, growth);
    float w0 = warpedFbm(uv * vec2(2.8, 2.2) + vec2(t * 0.2, t * 0.08), 1.2);
    float thresh0 = mix(1.05, 0.55, g0) + 0.04 * sin(t * 1.2);
    float patch0 = smoothstep(thresh0, thresh0 + 0.05, w0);
    float depth0 = smoothstep(thresh0, thresh0 + 0.20, w0);
    float sss0 = (1.0 - depth0) * patch0;
    vec3 col0 = mix(vec3(0.65, 0.38, 0.08), vec3(0.45, 0.16, 0.03), depth0);
    col0 *= 0.82 + 0.18 * noise(uv * 35.0 + 1.3);
    col0 += vec3(0.12, 0.05, 0.01) * sss0;
    col0 *= mix(crackAO, 1.0, 0.3);
    color = mix(color, col0, patch0 * 0.92);
    totalPatch = max(totalPatch, patch0);

    // -- Colony 1: Xanthoparmelia -- grey-green ------------------------
    float g1 = smoothstep(0.20, 0.75, growth);
    float w1 = warpedFbm(uv * vec2(4.5, 3.8) + vec2(18.0 + t * 0.15, 9.0 - t * 0.1), 0.9);
    float thresh1 = mix(1.05, 0.52, g1) + 0.03 * sin(t * 1.8 + 3.0);
    float patch1 = smoothstep(thresh1, thresh1 + 0.04, w1);
    float depth1 = smoothstep(thresh1, thresh1 + 0.15, w1);
    float sss1 = (1.0 - depth1) * patch1;
    vec3 col1 = mix(vec3(0.20, 0.24, 0.13), vec3(0.13, 0.15, 0.11), depth1);
    col1 *= 0.78 + 0.22 * noise(uv * 40.0 + 8.7);
    col1 += vec3(0.03, 0.06, 0.02) * sss1;
    col1 *= crackAO;
    float vis1 = patch1 * (1.0 - totalPatch * 0.8);
    color = mix(color, col1, vis1 * 0.90);
    totalPatch = max(totalPatch, vis1);

    // -- Colony 2: Candelaria -- bright yellow specks ------------------
    float g2 = smoothstep(0.10, 0.55, growth);
    float w2 = warpedFbm(uv * vec2(8.0, 6.5) + vec2(35.0 - t * 0.3, 20.0 + t * 0.15), 0.5);
    float thresh2 = mix(1.05, 0.62, g2) + noise(uv * 10.0 + 12.0) * 0.04;
    float patch2 = smoothstep(thresh2, thresh2 + 0.03, w2);
    float depth2 = smoothstep(thresh2, thresh2 + 0.10, w2);
    vec3 col2 = mix(vec3(0.60, 0.50, 0.10), vec3(0.45, 0.38, 0.05), depth2);
    col2 *= 0.85 + 0.15 * noise(uv * 50.0 + 15.0);
    col2 += vec3(0.08, 0.06, 0.0) * (1.0 - depth2) * patch2;
    col2 *= crackAO;
    float vis2 = patch2 * (1.0 - totalPatch * 0.7);
    color = mix(color, col2, vis2 * 0.88);
    totalPatch = max(totalPatch, vis2);

    // -- Colony 3: Buellia -- dark pioneer specks ----------------------
    float g3 = smoothstep(0.05, 0.40, growth);
    float w3 = warpedFbm(uv * vec2(11.0, 9.0) + vec2(55.0, 38.0), 0.3);
    float thresh3 = mix(1.05, 0.64, g3) + noise(uv * 14.0 + 20.0) * 0.03;
    float patch3 = smoothstep(thresh3, thresh3 + 0.02, w3);
    vec3 col3 = vec3(0.06, 0.055, 0.04);
    float vis3 = patch3 * (1.0 - totalPatch * 0.5);
    color = mix(color, col3, vis3 * 0.85);
    totalPatch = max(totalPatch, vis3);

    // -- Hemisphere lighting ------------------------------------------
    color *= 0.7 + 0.3 * (1.0 - uv.y);

    // -- Text on top --------------------------------------------------
    color = mix(color, term, textMask);

    // -- Focus dim ----------------------------------------------------
    float focusT   = clamp((iTime - iTimeFocus) * 1.5, 0.0, 1.0);
    float focusMix = iFocus == 1 ? focusT : 1.0 - focusT;
    float grey     = dot(color, vec3(0.299, 0.587, 0.114));
    color = mix(vec3(grey), color, mix(0.3, 1.0, focusMix)) * mix(0.55, 1.0, focusMix);

    fragColor = vec4(clamp(color, 0.0, 1.0), termRaw.a);
}
