// lichen.glsl -- crustose lichen on dark stone
//
// No compute. Overlapping fbm patches with:
// - cracked areola interior (min of two noise fields)
// - fake subsurface scattering at thin patch edges
// - ambient occlusion in cracks (no specular -- lichen is matte)
// - vivid Caloplaca, grey Xanthoparmelia, yellow Candelaria, dark Buellia
//
// iChannel0 = terminal content

// -- Tuning ----------------------------------------------------------
#define GROWTH_SPEED  0.006
#define BG_COLOR      vec3(0.05, 0.05, 0.06)
// --------------------------------------------------------------------

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

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    // -- Terminal -------------------------------------------------
    vec4 termRaw = texture(iChannel0, uv);
    vec3 term = termRaw.rgb;
    float textLuma = dot(term, vec3(0.299, 0.587, 0.114));
    float distFromBg = length(term - BG_COLOR);
    float textMask = smoothstep(0.03, 0.14, distFromBg);
    textMask = max(textMask, smoothstep(0.06, 0.20, textLuma));

    float t = iTime * GROWTH_SPEED;

    // -- Stone base -----------------------------------------------
    // Multi-scale grain: large weathering + fine crystal texture
    float grain0 = noise(uv * 18.0);
    float grain1 = noise(uv * 45.0);
    float grain2 = noise(uv * 90.0);
    float stoneGrain = grain0 * 0.12 + grain1 * 0.06 + grain2 * 0.03;
    vec3 stone = BG_COLOR + vec3(stoneGrain * 0.6, stoneGrain * 0.5, stoneGrain * 0.4);
    // Weathering darkens low spots
    stone *= 0.85 + 0.15 * grain0;

    // -- Areola crack network -------------------------------------
    // Two noise fields at different scales -- cracks where both are low
    float cr0 = noise(uv * 75.0);
    float cr1 = noise(uv * 52.0 + 33.0);
    float crackRaw = min(cr0, cr1);
    // Soft crack: 0 = deep crack, 1 = center of areola
    float crackSoft = smoothstep(0.22, 0.40, crackRaw);
    // Ambient occlusion: cracks trap light, darkening gradually
    // This is the key to looking organic vs metallic
    float crackAO = 0.4 + 0.6 * smoothstep(0.18, 0.50, crackRaw);

    // -- Shared patch helper values --------------------------------
    float totalPatchMask = 0.0;
    vec3 lichenColor = vec3(0.0);

    // -- Layer 0: Caloplaca -- vivid orange/rust sunburst ----------
    float n0 = fbm3(uv * vec2(4.0, 3.5) + vec2(t * 0.3, t * 0.1));
    float thresh0 = 0.44 + 0.08 * sin(t * 1.5) + noise(uv * 7.0 + t * 0.2) * 0.1;
    float patch0 = smoothstep(thresh0, thresh0 + 0.04, n0);
    // How deep into the patch: 0 at edge, 1 at center
    float depth0 = smoothstep(thresh0, thresh0 + 0.15, n0);
    // Subsurface: thin edges transmit warm light
    float sss0 = (1.0 - depth0) * patch0;
    // Base color deepens toward center
    vec3 col0 = mix(
        vec3(0.70, 0.40, 0.08),   // warm translucent edge
        vec3(0.50, 0.18, 0.03),   // deep opaque center
        depth0
    );
    // Interior variation -- chalky, powdery texture
    col0 *= 0.82 + 0.18 * noise(uv * 38.0 + 1.3);
    // SSS glow at edges
    col0 += vec3(0.15, 0.06, 0.01) * sss0;
    // Crack AO darkens cracks, no specular
    col0 *= crackAO;
    lichenColor += col0 * patch0;
    totalPatchMask = max(totalPatchMask, patch0);

    // -- Layer 1: Xanthoparmelia -- grey-green foliose-like ---------
    float n1 = fbm3(uv * vec2(5.5, 4.5) + vec2(20.0 + t * 0.2, 10.0 - t * 0.15));
    float thresh1 = 0.46 + 0.06 * sin(t * 2.1 + 3.0) + noise(uv * 9.0 + 5.0) * 0.08;
    float patch1 = smoothstep(thresh1, thresh1 + 0.03, n1);
    float depth1 = smoothstep(thresh1, thresh1 + 0.12, n1);
    float sss1 = (1.0 - depth1) * patch1;
    vec3 col1 = mix(
        vec3(0.22, 0.26, 0.14),   // thin edge -- greener
        vec3(0.15, 0.17, 0.13),   // thick center -- greyed
        depth1
    );
    col1 *= 0.78 + 0.22 * noise(uv * 42.0 + 8.7);
    col1 += vec3(0.04, 0.08, 0.02) * sss1;
    col1 *= crackAO;
    float vis1 = patch1 * (1.0 - patch0 * 0.7);
    lichenColor += col1 * vis1;
    totalPatchMask = max(totalPatchMask, vis1);

    // -- Layer 2: Candelaria -- bright yellow spots ----------------
    float n2 = fbm3(uv * vec2(9.0, 7.0) + vec2(40.0 - t * 0.4, 25.0 + t * 0.2));
    float thresh2 = 0.50 + 0.04 * sin(t * 1.8 + 7.0) + noise(uv * 11.0 + 12.0) * 0.06;
    float patch2 = smoothstep(thresh2, thresh2 + 0.025, n2);
    float depth2 = smoothstep(thresh2, thresh2 + 0.08, n2);
    vec3 col2 = mix(
        vec3(0.65, 0.55, 0.12),   // translucent yellow edge
        vec3(0.50, 0.42, 0.06),   // deeper center
        depth2
    );
    col2 *= 0.85 + 0.15 * noise(uv * 48.0 + 15.0);
    col2 += vec3(0.10, 0.08, 0.0) * (1.0 - depth2) * patch2;
    col2 *= crackAO;
    float vis2 = patch2 * (1.0 - totalPatchMask * 0.6);
    lichenColor += col2 * vis2;
    totalPatchMask = max(totalPatchMask, vis2);

    // -- Layer 3: Buellia -- dark crustose, almost black -----------
    float n3 = fbm3(uv * vec2(7.0, 6.0) + vec2(60.0 + t * 0.1, 40.0));
    float thresh3 = 0.48 + noise(uv * 13.0 + 20.0) * 0.06;
    float patch3 = smoothstep(thresh3, thresh3 + 0.02, n3);
    vec3 col3 = vec3(0.06, 0.055, 0.04);
    col3 *= 0.9 + 0.1 * noise(uv * 50.0 + 22.0);
    col3 *= crackAO;
    float vis3 = patch3 * (1.0 - totalPatchMask * 0.5);
    lichenColor += col3 * vis3;
    totalPatchMask = max(totalPatchMask, vis3);

    // -- Lighting: flat matte, AO only -----------------------------
    // Lichen is powdery and diffuse -- no directional shading.
    // All depth cues come from AO in cracks and SSS at edges.
    // Gentle hemisphere: slightly brighter at top (sky)
    float hemi = 0.7 + 0.3 * (1.0 - uv.y);
    float lighting = hemi;

    // -- Compose --------------------------------------------------
    vec3 color = mix(stone, lichenColor, totalPatchMask * 0.92);
    color *= lighting;

    // -- Text on top ----------------------------------------------
    color = mix(color, term, textMask);

    // -- Focus dim ------------------------------------------------
    float focusT   = clamp((iTime - iTimeFocus) * 1.5, 0.0, 1.0);
    float focusMix = iFocus == 1 ? focusT : 1.0 - focusT;
    float grey     = dot(color, vec3(0.299, 0.587, 0.114));
    color = mix(vec3(grey), color, mix(0.3, 1.0, focusMix)) * mix(0.55, 1.0, focusMix);

    fragColor = vec4(clamp(color, 0.0, 1.0), termRaw.a);
}
