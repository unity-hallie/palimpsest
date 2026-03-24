// lichen.glsl -- slow color patches on dark stone
//
// No compute. Voronoi cells with drifting color, like watching
// a wall grow patina over centuries compressed into minutes.
// Text sits clean on top.
//
// iChannel0 = terminal content

// -- Tuning ----------------------------------------------------------
#define GROWTH_SPEED  0.008
#define CELL_SCALE    5.0
#define BG_COLOR      vec3(0.05, 0.05, 0.06)
// --------------------------------------------------------------------

float hash2(vec2 p) {
    p = fract(p * vec2(127.1, 311.7));
    p += dot(p, p.yx + 19.19);
    return fract(p.x * p.y);
}

vec2 hash2v(vec2 p) {
    return vec2(hash2(p), hash2(p + 71.3));
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

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    // -- Terminal -------------------------------------------------
    vec4 termRaw = texture(iChannel0, uv);
    vec3 term = termRaw.rgb;
    float textLuma = dot(term, vec3(0.299, 0.587, 0.114));
    float distFromBg = length(term - BG_COLOR);
    float textMask = smoothstep(0.03, 0.14, distFromBg);
    textMask = max(textMask, smoothstep(0.06, 0.20, textLuma));

    // -- Voronoi for lichen patches --------------------------------
    float t = iTime * GROWTH_SPEED;
    vec2 p = uv * CELL_SCALE;
    vec2 ip = floor(p);
    vec2 fp = fract(p);

    float minDist = 10.0;
    float secondDist = 10.0;
    vec2 nearestCell = vec2(0.0);

    for (int y = -1; y <= 1; y++) {
    for (int x = -1; x <= 1; x++) {
        vec2 neighbor = vec2(float(x), float(y));
        vec2 cellID = ip + neighbor;
        vec2 point = hash2v(cellID);
        // Cells drift very slowly
        point += 0.15 * sin(t * (0.5 + point) * 6.28);
        vec2 diff = neighbor + point - fp;
        float d = dot(diff, diff);
        if (d < minDist) {
            secondDist = minDist;
            minDist = d;
            nearestCell = cellID;
        } else if (d < secondDist) {
            secondDist = d;
        }
    }}

    minDist = sqrt(minDist);
    secondDist = sqrt(secondDist);

    // Edge detection -- border between cells
    float edge = smoothstep(0.0, 0.08, secondDist - minDist);

    // Per-cell color -- muted earth/moss tones
    float cellHash = hash2(nearestCell);
    float cellHash2 = hash2(nearestCell + 43.7);

    // Palette: moss green, ochre, slate blue, rust, sage
    vec3 col;
    float hue = cellHash;
    if (hue < 0.25) {
        col = vec3(0.12, 0.18, 0.08);  // dark moss
    } else if (hue < 0.45) {
        col = vec3(0.18, 0.14, 0.06);  // ochre
    } else if (hue < 0.60) {
        col = vec3(0.08, 0.10, 0.15);  // slate
    } else if (hue < 0.78) {
        col = vec3(0.15, 0.08, 0.06);  // rust
    } else {
        col = vec3(0.10, 0.14, 0.10);  // sage
    }

    // Brightness varies per cell, breathes slowly
    float breath = 0.7 + 0.3 * sin(t * 3.0 + cellHash2 * 20.0);
    col *= breath;

    // Stone texture underneath -- noise roughness
    float stone = noise(uv * 18.0) * 0.3 + 0.7;

    // Compose: stone + lichen patches, dark at edges
    vec3 stoneCol = BG_COLOR * stone;
    vec3 lichenCol = mix(stoneCol, col, edge * 0.85);

    // -- Text on top ----------------------------------------------
    vec3 color = mix(lichenCol, term, textMask);

    // -- Focus dim ------------------------------------------------
    float focusT   = clamp((iTime - iTimeFocus) * 1.5, 0.0, 1.0);
    float focusMix = iFocus == 1 ? focusT : 1.0 - focusT;
    float grey     = dot(color, vec3(0.299, 0.587, 0.114));
    color = mix(vec3(grey), color, mix(0.3, 1.0, focusMix)) * mix(0.55, 1.0, focusMix);

    fragColor = vec4(clamp(color, 0.0, 1.0), termRaw.a);
}
