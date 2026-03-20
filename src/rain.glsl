// rain.glsl -- rain on the outside of waxed glass, solarpunk city behind
//
// You're inside, looking out through a window. Rain beads on the
// outside surface. Behind the rain: a blurry solarpunk skyline --
// dark silhouettes, green edges, occasional warm windows.
// Terminal text is on the inside, NOT refracted by the drops.
//
// iChannel0 = terminal content
// iChannel2 = compute state (R=water, G=trail, B=velocity)

// -- Tuning ----------------------------------------------------------
// Refraction (drops bend the back-pane text + city)
#define REFRACT_STRENGTH    0.18
#define REFRACT_MAGNIFY     0.35
#define CHROMA_SPREAD       0.50
#define NORMAL_SCALE        6.0
#define DROPLET_DEPTH       2.0

// Specular
#define SPECULAR            0.07
#define SPECULAR_TIGHT      48.0

// Appearance
#define EDGE_DARKEN         0.18
#define CITY_OPACITY        0.20     // city bleed through dry glass
#define TEXT_BRIGHTNESS     0.88     // front pane terminal

// Back pane -- blurry text projected behind the glass
#define BACK_PANE_ALPHA     0.40     // opacity of back-pane text
#define BACK_PANE_BLUR      14.0     // blur radius in pixels (very soft glow)
#define BACK_PANE_DIM       0.45     // much dimmer than front text
#define BACK_PANE_OFFSET    vec2(0.012, 0.018) // parallax shift (right and down)
#define MULLION_WIDTH       0.004    // window bar thickness
#define MULLION_DARK        0.04     // how dark the bars are
// ====================================================================

//@ include "common.glsl"

// Window frame -- dark mullion bars
// Returns 0.0 on glass, 1.0 on bar
float mullion(vec2 uv) {
    float bar = 0.0;
    bar = max(bar, 1.0 - smoothstep(0.0, MULLION_WIDTH, abs(uv.x - 0.5)));
    bar = max(bar, 1.0 - smoothstep(0.0, MULLION_WIDTH, abs(uv.y - 0.4)));
    float edge = MULLION_WIDTH * 1.5;
    bar = max(bar, 1.0 - smoothstep(0.0, edge, uv.x));
    bar = max(bar, 1.0 - smoothstep(0.0, edge, 1.0 - uv.x));
    bar = max(bar, 1.0 - smoothstep(0.0, edge, uv.y));
    bar = max(bar, 1.0 - smoothstep(0.0, edge, 1.0 - uv.y));
    return bar;
}

// -- Solarpunk city -- photorealistic bokeh blur ---------------------
vec3 city(vec2 uv) {
    vec3 sky = mix(vec3(0.78, 0.82, 0.92),
                   vec3(0.65, 0.70, 0.82),
                   smoothstep(0.0, 0.50, uv.y));
    float cloud = fbm(uv * vec2(1.2, 0.6) + vec2(iTime * 0.001, 0.0));
    sky += vec3(0.025, 0.015, -0.008) * (cloud - 0.5);

    float skyline = 0.42
        + 0.10 * noise(vec2(uv.x * 3.0, 3.0))
        + 0.06 * noise(vec2(uv.x * 7.0, 7.0))
        + 0.03 * noise(vec2(uv.x * 13.0, 11.0));
    float buildingMask = smoothstep(skyline - 0.12, skyline + 0.12, uv.y);

    float depth = fbm(vec2(uv.x * 2.5, 0.5));
    vec3 building = mix(vec3(0.22, 0.26, 0.34), vec3(0.42, 0.47, 0.56), depth * 0.5);
    building += vec3(0.01) * noise(uv * vec2(1.5, 4.0));

    float greenBand = smoothstep(skyline + 0.15, skyline - 0.03, uv.y)
                    * smoothstep(skyline - 0.10, skyline + 0.02, uv.y);
    float greenVar = fbm(uv * vec2(4.0, 2.5) + 20.0);
    vec3 green = mix(vec3(0.15, 0.28, 0.14), vec3(0.22, 0.38, 0.18), greenVar);
    building = mix(building, green, greenBand * 0.5);

    vec3 lights = vec3(0.0);
    for (int i = 0; i < 24; i++) {
        float fi = float(i);
        vec2 pos = vec2(
            fract(sin(fi * 127.1 + 3.7) * 43758.5),
            0.48 + fract(sin(fi * 311.7 + 1.3) * 43758.5) * 0.47
        );
        float maxR = 0.08;
        vec2 delta = uv - pos;
        if (abs(delta.x) > maxR || abs(delta.y) > maxR) continue;
        float dist = (pos.y - 0.45) / 0.55;
        float radius = mix(0.008, 0.04, dist * dist)
                     * (0.4 + 0.8 * fract(sin(fi * 73.1) * 1e4));
        float d = length(delta) / radius;
        if (d > 3.0) continue;
        float b = exp(-d * d * 2.5);
        float warmth = fract(sin(fi * 53.3) * 1e4);
        vec3 lc = mix(vec3(0.65, 0.50, 0.22), vec3(0.45, 0.52, 0.35), warmth * 0.35);
        float bright = (0.02 + 0.04 * fract(sin(fi * 91.7) * 1e4)) * (0.5 + 0.6 * dist);
        lights += lc * b * bright;
    }

    vec3 scene = mix(sky, building, buildingMask);
    scene += lights;
    scene = mix(scene, vec3(0.55, 0.62, 0.72), 0.05);
    return scene;
}

// ====================================================================

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2  uv = fragCoord / iResolution.xy;
    vec2  px = 1.0 / iResolution.xy;

    vec4  state = texture(iChannel2, uv);
    float water = state.r;
    float trail = state.g;

    float wL = texture(iChannel2, uv + vec2(-px.x, 0.0)).r;
    float wR = texture(iChannel2, uv + vec2( px.x, 0.0)).r;
    float wU = texture(iChannel2, uv + vec2(0.0, -px.y)).r;
    float wD = texture(iChannel2, uv + vec2(0.0,  px.y)).r;
    vec2  grad = vec2(wR - wL, wD - wU) * NORMAL_SCALE;

    float isWet = smoothstep(0.03, 0.15, water);
    float beadHeight = water * water * DROPLET_DEPTH;

    vec3 terminal = texture(iChannel0, uv).rgb * TEXT_BRIGHTNESS;

    vec2 backUV = uv + BACK_PANE_OFFSET;
    float bR = BACK_PANE_BLUR;
    float bR2 = bR * 2.0;
    vec3 blurTerm = vec3(0.0);
    blurTerm += 2.0 * texture(iChannel0, backUV + vec2(-bR, -bR) * px).rgb;
    blurTerm += 2.0 * texture(iChannel0, backUV + vec2( 0.0, -bR) * px).rgb;
    blurTerm += 2.0 * texture(iChannel0, backUV + vec2( bR, -bR) * px).rgb;
    blurTerm += 2.0 * texture(iChannel0, backUV + vec2(-bR,  0.0) * px).rgb;
    blurTerm += 2.0 * texture(iChannel0, backUV).rgb;
    blurTerm += 2.0 * texture(iChannel0, backUV + vec2( bR,  0.0) * px).rgb;
    blurTerm += 2.0 * texture(iChannel0, backUV + vec2(-bR,  bR) * px).rgb;
    blurTerm += 2.0 * texture(iChannel0, backUV + vec2( 0.0,  bR) * px).rgb;
    blurTerm += 2.0 * texture(iChannel0, backUV + vec2( bR,  bR) * px).rgb;
    blurTerm += texture(iChannel0, backUV + vec2(-bR2, -bR2) * px).rgb;
    blurTerm += texture(iChannel0, backUV + vec2( 0.0, -bR2) * px).rgb;
    blurTerm += texture(iChannel0, backUV + vec2( bR2, -bR2) * px).rgb;
    blurTerm += texture(iChannel0, backUV + vec2(-bR2,  0.0) * px).rgb;
    blurTerm += texture(iChannel0, backUV + vec2( bR2,  0.0) * px).rgb;
    blurTerm += texture(iChannel0, backUV + vec2(-bR2,  bR2) * px).rgb;
    blurTerm += texture(iChannel0, backUV + vec2( 0.0,  bR2) * px).rgb;
    blurTerm += texture(iChannel0, backUV + vec2( bR2,  bR2) * px).rgb;
    blurTerm = blurTerm / 26.0 * BACK_PANE_DIM;

    vec2 safeGrad = grad;
    float gMag = length(grad);
    if (gMag > 3.0) safeGrad = safeGrad * (3.0 / gMag);

    vec2 lensUV = uv - safeGrad * REFRACT_MAGNIFY * beadHeight;
    vec2 refractOffset = safeGrad * REFRACT_STRENGTH * beadHeight;
    vec2 dropUV = clamp(lensUV + refractOffset, 0.001, 0.999);

    vec2 cityUV = mix(uv, dropUV, isWet);
    vec3 bg = city(cityUV);
    float mul = mullion(cityUV);
    bg = mix(bg, vec3(MULLION_DARK), mul);

    float spread = CHROMA_SPREAD * beadHeight;
    vec2 dropBackUV = dropUV + BACK_PANE_OFFSET;
    vec3 backThruDrop = vec3(
        texture(iChannel0, clamp(dropBackUV + safeGrad * spread * 0.02, 0.001, 0.999)).r,
        texture(iChannel0, clamp(dropBackUV, 0.001, 0.999)).g,
        texture(iChannel0, clamp(dropBackUV - safeGrad * spread * 0.02, 0.001, 0.999)).b
    ) * BACK_PANE_DIM;

    float dropMul = mullion(dropUV);
    vec3 dropScene = mix(bg * 0.2, backThruDrop, BACK_PANE_ALPHA);
    dropScene = mix(dropScene, vec3(MULLION_DARK), dropMul * 0.8);

    float edgeDist = length(grad) / max(water, 0.01);
    float fresnel  = smoothstep(0.0, 8.0, edgeDist);
    dropScene *= 1.0 - fresnel * EDGE_DARKEN * isWet;

    vec2  lightDir = normalize(vec2(-0.4, -0.7));
    float nMag  = length(safeGrad);
    vec2  nDir  = safeGrad / max(nMag, 0.001);
    float spec  = max(dot(nDir, lightDir), 0.0);
    spec = pow(spec, SPECULAR_TIGHT) * nMag * SPECULAR * beadHeight;
    dropScene += vec3(0.90, 0.90, 0.88) * spec;

    float dryMul = mullion(uv);
    vec3 dryBg = mix(bg, vec3(MULLION_DARK), dryMul);
    vec3 dryGlass = terminal + blurTerm * BACK_PANE_ALPHA + dryBg * CITY_OPACITY;

    float tL = texture(iChannel2, uv + vec2(-px.x, 0.0)).g;
    float tR = texture(iChannel2, uv + vec2( px.x, 0.0)).g;
    float tU = texture(iChannel2, uv + vec2(0.0, -px.y)).g;
    float tD = texture(iChannel2, uv + vec2(0.0,  px.y)).g;
    vec2  trailGrad = vec2(tR - tL, tD - tU);
    vec2  trailUV = clamp(uv + trailGrad * 0.004, 0.001, 0.999);
    vec3  trailBack = texture(iChannel0, trailUV).rgb * BACK_PANE_DIM;
    vec3  trailColor = terminal + mix(bg * CITY_OPACITY, trailBack, BACK_PANE_ALPHA);
    float isTrail = smoothstep(0.01, 0.06, trail) * (1.0 - isWet);

    vec3 behind = dryGlass;
    behind = mix(behind, trailColor, isTrail);
    behind = mix(behind, dropScene,  isWet);

    // Front pane text on top -- key out background (~#181B20)
    vec3 bgColor = vec3(0.094, 0.106, 0.125);
    float distFromBg = length(texture(iChannel0, uv).rgb - bgColor);
    float textMask = smoothstep(0.03, 0.15, distFromBg);
    vec3 color = mix(behind, terminal, textMask);

    fragColor = vec4(clamp(color, 0.0, 1.0), texture(iChannel0, uv).a);
}
