// lichen.glsl -- crustose lichen on dark stone
//
// No compute. Overlapping fbm patches with:
// - cracked areola interior texture (high-freq noise thresholded into cracks)
// - normal-mapped lighting from crack and surface geometry
// - vivid orange/yellow Caloplaca, grey Xanthoparmelia, green wet algal patches
// - stone grain underneath
//
// iChannel0 = terminal content

// -- Tuning ----------------------------------------------------------
#define GROWTH_SPEED  0.006
#define BG_COLOR      vec3(0.05, 0.05, 0.06)
#define LIGHT_DIR     vec3(0.4, -0.5, 0.75)
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

// Normal from heightmap via central differences
vec3 calcNormal(vec2 uv, float h, float eps) {
    float hR = noise(uv + vec2(eps, 0.0));
    float hU = noise(uv + vec2(0.0, eps));
    return normalize(vec3(h - hR, h - hU, eps * 8.0));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec2 px = 1.0 / iResolution.xy;

    // -- Terminal -------------------------------------------------
    vec4 termRaw = texture(iChannel0, uv);
    vec3 term = termRaw.rgb;
    float textLuma = dot(term, vec3(0.299, 0.587, 0.114));
    float distFromBg = length(term - BG_COLOR);
    float textMask = smoothstep(0.03, 0.14, distFromBg);
    textMask = max(textMask, smoothstep(0.06, 0.20, textLuma));

    float t = iTime * GROWTH_SPEED;
    vec3 L = normalize(LIGHT_DIR);

    // -- Stone base -----------------------------------------------
    float stoneH = noise(uv * 20.0);
    float stoneGrain = stoneH * 0.15 + noise(uv * 50.0) * 0.06;
    vec3 stoneN = calcNormal(uv * 20.0, stoneH, 0.02);
    float stoneDiff = max(dot(stoneN, L), 0.0) * 0.4 + 0.6;
    vec3 stone = (BG_COLOR + vec3(stoneGrain * 0.5, stoneGrain * 0.4, stoneGrain * 0.35)) * stoneDiff;

    // -- Heightmap accumulator for combined normal ----------------
    float totalH = stoneH * 0.3;
    float totalPatchMask = 0.0;

    // -- Lichen color accumulator ---------------------------------
    vec3 lichenColor = vec3(0.0);

    // -- Areola crack pattern (shared across patches) -------------
    // High-freq noise thresholded to make branching crack network
    float crackNoise = noise(uv * 80.0);
    float crackNoise2 = noise(uv * 55.0 + 33.0);
    float cracks = min(crackNoise, crackNoise2);
    // Cracks are where both noise values are low -- thin dark lines
    float crackMask = smoothstep(0.28, 0.35, cracks);
    // Cracks depress the heightmap
    float crackH = crackMask;

    // -- Layer 0: Caloplaca -- vivid orange sunburst lichen -------
    float n0 = fbm3(uv * vec2(4.0, 3.5) + vec2(t * 0.3, t * 0.1));
    float thresh0 = 0.44 + 0.08 * sin(t * 1.5) + noise(uv * 7.0 + t * 0.2) * 0.1;
    float patch0 = smoothstep(thresh0, thresh0 + 0.04, n0);
    // Edge fringe -- slightly brighter/yellower at growing edge
    float edge0 = smoothstep(thresh0 + 0.04, thresh0 + 0.01, n0) * patch0;
    vec3 col0core = vec3(0.55, 0.22, 0.03);   // deep orange center
    vec3 col0edge = vec3(0.65, 0.45, 0.05);   // yellow growing edge
    vec3 col0 = mix(col0core, col0edge, edge0);
    col0 *= 0.8 + 0.2 * noise(uv * 35.0 + 1.3);  // interior variation
    col0 *= crackMask * 0.5 + 0.5;                 // darken in cracks
    lichenColor += col0 * patch0;
    totalH += patch0 * 0.4 * crackH;
    totalPatchMask = max(totalPatchMask, patch0);

    // -- Layer 1: Xanthoparmelia -- pale grey-green ----------------
    float n1 = fbm3(uv * vec2(5.5, 4.5) + vec2(20.0 + t * 0.2, 10.0 - t * 0.15));
    float thresh1 = 0.46 + 0.06 * sin(t * 2.1 + 3.0) + noise(uv * 9.0 + 5.0) * 0.08;
    float patch1 = smoothstep(thresh1, thresh1 + 0.03, n1);
    float edge1 = smoothstep(thresh1 + 0.03, thresh1 + 0.008, n1) * patch1;
    vec3 col1core = vec3(0.18, 0.20, 0.16);   // grey-green
    vec3 col1edge = vec3(0.22, 0.25, 0.18);   // lighter rim
    vec3 col1 = mix(col1core, col1edge, edge1);
    col1 *= 0.75 + 0.25 * noise(uv * 40.0 + 8.7);
    col1 *= crackMask * 0.6 + 0.4;
    // Only show where orange isn't dominant
    float vis1 = patch1 * (1.0 - patch0 * 0.7);
    lichenColor += col1 * vis1;
    totalH += vis1 * 0.35 * crackH;
    totalPatchMask = max(totalPatchMask, vis1);

    // -- Layer 2: Candelaria -- bright yellow spots ----------------
    float n2 = fbm3(uv * vec2(9.0, 7.0) + vec2(40.0 - t * 0.4, 25.0 + t * 0.2));
    float thresh2 = 0.50 + 0.04 * sin(t * 1.8 + 7.0) + noise(uv * 11.0 + 12.0) * 0.06;
    float patch2 = smoothstep(thresh2, thresh2 + 0.025, n2);
    vec3 col2 = vec3(0.60, 0.52, 0.08);       // lemon yellow
    col2 *= 0.85 + 0.15 * noise(uv * 45.0 + 15.0);
    col2 *= crackMask * 0.4 + 0.6;
    float vis2 = patch2 * (1.0 - totalPatchMask * 0.6);
    lichenColor += col2 * vis2;
    totalH += vis2 * 0.3 * crackH;
    totalPatchMask = max(totalPatchMask, vis2);

    // -- Layer 3: dark Buellia -- nearly black crustose -----------
    float n3 = fbm3(uv * vec2(7.0, 6.0) + vec2(60.0 + t * 0.1, 40.0));
    float thresh3 = 0.48 + noise(uv * 13.0 + 20.0) * 0.06;
    float patch3 = smoothstep(thresh3, thresh3 + 0.02, n3);
    vec3 col3 = vec3(0.04, 0.04, 0.03);
    col3 *= crackMask * 0.7 + 0.3;
    float vis3 = patch3 * (1.0 - totalPatchMask * 0.5);
    lichenColor += col3 * vis3;
    totalH += vis3 * 0.2 * crackH;
    totalPatchMask = max(totalPatchMask, vis3);

    // -- Normal from combined heightmap ---------------------------
    float eps = px.x * 2.0;
    // Recompute height at offset positions for finite differences
    // Use the dominant contributor: crack pattern + patch presence
    float hC = totalH;
    // Approximate: shift uv slightly, recompute cracks at offset
    float crR = min(noise((uv + vec2(eps, 0.0)) * 80.0), noise((uv + vec2(eps, 0.0)) * 55.0 + 33.0));
    float crU = min(noise((uv + vec2(0.0, eps)) * 80.0), noise((uv + vec2(0.0, eps)) * 55.0 + 33.0));
    float hR = totalPatchMask * 0.35 * smoothstep(0.28, 0.35, crR) + noise((uv + vec2(eps, 0.0)) * 20.0) * 0.3;
    float hU = totalPatchMask * 0.35 * smoothstep(0.28, 0.35, crU) + noise((uv + vec2(0.0, eps)) * 20.0) * 0.3;

    vec3 N = normalize(vec3(hC - hR, hC - hU, eps * 12.0));

    // Diffuse + subtle specular
    float diff = max(dot(N, L), 0.0) * 0.5 + 0.5;
    vec3 H = normalize(L + vec3(0.0, 0.0, 1.0));
    float spec = pow(max(dot(N, H), 0.0), 30.0) * 0.15;

    // -- Compose --------------------------------------------------
    vec3 color = mix(stone, lichenColor * diff + spec, totalPatchMask * 0.92);

    // -- Text on top ----------------------------------------------
    color = mix(color, term, textMask);

    // -- Focus dim ------------------------------------------------
    float focusT   = clamp((iTime - iTimeFocus) * 1.5, 0.0, 1.0);
    float focusMix = iFocus == 1 ? focusT : 1.0 - focusT;
    float grey     = dot(color, vec3(0.299, 0.587, 0.114));
    color = mix(vec3(grey), color, mix(0.3, 1.0, focusMix)) * mix(0.55, 1.0, focusMix);

    fragColor = vec4(clamp(color, 0.0, 1.0), termRaw.a);
}
