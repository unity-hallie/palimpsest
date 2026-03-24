// lichen.glsl -- slow organic patches on dark stone
//
// No compute. Overlapping noise layers with different scales
// and colors, thresholded to create irregular patches that
// grow and recede. No voronoi -- just fbm with hard edges.
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
    float stoneGrain = noise(uv * 22.0) * 0.15 + noise(uv * 45.0) * 0.08;
    vec3 stone = BG_COLOR + vec3(stoneGrain * 0.6, stoneGrain * 0.5, stoneGrain * 0.4);

    // -- Lichen layers --------------------------------------------
    // Each layer: fbm at a different scale/offset, thresholded
    // to make irregular patches. Threshold drifts with time so
    // patches grow and recede. Different color per layer.
    vec3 color = stone;

    // Layer 0: large slow moss -- dark green
    float n0 = fbm3(uv * vec2(4.0, 3.5) + vec2(t * 0.3, t * 0.1));
    // Warp the threshold with another noise for irregular edges
    float thresh0 = 0.44 + 0.08 * sin(t * 1.5) + noise(uv * 7.0 + t * 0.2) * 0.1;
    float patch0 = smoothstep(thresh0, thresh0 + 0.04, n0);
    // Fuzzy interior texture
    float interior0 = noise(uv * 30.0 + 1.3) * 0.3 + 0.7;
    vec3 col0 = vec3(0.08, 0.14, 0.06) * interior0;
    color = mix(color, col0, patch0 * 0.9);

    // Layer 1: medium ochre/gold patches
    float n1 = fbm3(uv * vec2(6.0, 5.0) + vec2(20.0 + t * 0.2, 10.0 - t * 0.15));
    float thresh1 = 0.46 + 0.06 * sin(t * 2.1 + 3.0) + noise(uv * 9.0 + t * 0.15 + 5.0) * 0.08;
    float patch1 = smoothstep(thresh1, thresh1 + 0.03, n1);
    float interior1 = noise(uv * 35.0 + 8.7) * 0.25 + 0.75;
    vec3 col1 = vec3(0.16, 0.12, 0.04) * interior1;
    color = mix(color, col1, patch1 * 0.85);

    // Layer 2: small scattered pale sage
    float n2 = fbm3(uv * vec2(9.0, 7.0) + vec2(40.0 - t * 0.4, 25.0 + t * 0.2));
    float thresh2 = 0.48 + 0.05 * sin(t * 1.8 + 7.0) + noise(uv * 11.0 + t * 0.1 + 12.0) * 0.07;
    float patch2 = smoothstep(thresh2, thresh2 + 0.025, n2);
    float interior2 = noise(uv * 40.0 + 15.0) * 0.2 + 0.8;
    vec3 col2 = vec3(0.10, 0.13, 0.08) * interior2;
    color = mix(color, col2, patch2 * 0.8);

    // Layer 3: tiny rust/orange specks -- highest frequency
    float n3 = fbm3(uv * vec2(13.0, 10.0) + vec2(60.0 + t * 0.15, 40.0));
    float thresh3 = 0.50 + noise(uv * 14.0 + 20.0) * 0.06;
    float patch3 = smoothstep(thresh3, thresh3 + 0.02, n3);
    vec3 col3 = vec3(0.14, 0.06, 0.03);
    color = mix(color, col3, patch3 * 0.7);

    // -- Text on top ----------------------------------------------
    color = mix(color, term, textMask);

    // -- Focus dim ------------------------------------------------
    float focusT   = clamp((iTime - iTimeFocus) * 1.5, 0.0, 1.0);
    float focusMix = iFocus == 1 ? focusT : 1.0 - focusT;
    float grey     = dot(color, vec3(0.299, 0.587, 0.114));
    color = mix(vec3(grey), color, mix(0.3, 1.0, focusMix)) * mix(0.55, 1.0, focusMix);

    fragColor = vec4(clamp(color, 0.0, 1.0), termRaw.a);
}
