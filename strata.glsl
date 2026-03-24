// strata.glsl -- geological sediment layers
//
// Horizontal bands warped by tectonic noise. Each layer a different
// mineral. Time compresses deep time -- layers shift imperceptibly.
// No compute. Cheap: a few noise lookups for warp + layer ID.
//
// iChannel0 = terminal content

#define BG_COLOR   vec3(0.04, 0.04, 0.05)
#define DRIFT      0.003
#define NUM_LAYERS 8.0
#define WARP_STR   0.12

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

    vec4 termRaw = texture(iChannel0, uv);
    vec3 term = termRaw.rgb;
    float textLuma = dot(term, vec3(0.299, 0.587, 0.114));
    float distFromBg = length(term - BG_COLOR);
    float textMask = smoothstep(0.03, 0.14, distFromBg);
    textMask = max(textMask, smoothstep(0.06, 0.20, textLuma));

    float t = iTime * DRIFT;

    // -- Tectonic warp ------------------------------------------------
    // Horizontal layers bent by slow noise -- folds and faults
    float warp = fbm3(vec2(uv.x * 2.0 + t * 0.3, uv.y * 0.5 + t * 0.1)) * WARP_STR;
    float warp2 = noise(vec2(uv.x * 5.0 + 10.0, uv.y * 1.5)) * 0.04;
    float warpedY = uv.y + warp + warp2;

    // -- Layer identification -----------------------------------------
    // Scale Y so we get NUM_LAYERS bands across the screen
    float layerF = warpedY * NUM_LAYERS;
    float layerID = floor(layerF);
    float inLayer = fract(layerF);

    // -- Per-layer color from mineral palette -------------------------
    // Each layer gets a deterministic color from its ID
    float h = hash2(vec2(layerID, 0.0));
    float h2 = hash2(vec2(layerID, 7.3));

    vec3 layerCol;
    if (h < 0.15) {
        layerCol = vec3(0.03, 0.03, 0.04);       // dark shale
    } else if (h < 0.30) {
        layerCol = vec3(0.14, 0.08, 0.04);        // rusty sandstone
    } else if (h < 0.45) {
        layerCol = vec3(0.12, 0.11, 0.08);        // mudstone
    } else if (h < 0.58) {
        layerCol = vec3(0.16, 0.15, 0.12);        // pale limestone
    } else if (h < 0.70) {
        layerCol = vec3(0.08, 0.06, 0.04);        // dark ironstone
    } else if (h < 0.82) {
        layerCol = vec3(0.10, 0.12, 0.10);        // greenish slate
    } else if (h < 0.92) {
        layerCol = vec3(0.18, 0.16, 0.14);        // quartz vein
    } else {
        layerCol = vec3(0.06, 0.04, 0.06);        // basalt
    }

    // Layer thickness variation -- some thin, some wide
    // Thin layers are brighter (compressed sediment = harder = more reflective)
    float thickness = 0.5 + h2 * 0.5;
    layerCol *= 0.85 + 0.15 * (1.0 - thickness);

    // -- Internal grain -----------------------------------------------
    // Each layer has its own grain texture
    float grain = noise(vec2(uv.x * 40.0, layerF * 8.0 + layerID * 20.0));
    float grain2 = noise(vec2(uv.x * 80.0 + 30.0, layerF * 15.0 + layerID * 50.0));
    layerCol *= 0.88 + 0.12 * grain;
    // Fine sparkle in some layers (mica/quartz)
    layerCol += vec3(0.02) * grain2 * grain2 * step(0.7, h);

    // -- Bedding planes (layer boundaries) ----------------------------
    // Darken at edges where layers meet
    float edgeDist = min(inLayer, 1.0 - inLayer);
    float bedding = smoothstep(0.0, 0.08, edgeDist);
    layerCol *= 0.6 + 0.4 * bedding;

    // -- Faint fault lines (vertical cracks) --------------------------
    float fault = noise(vec2(uv.x * 60.0, uv.y * 2.0 + 5.0));
    float faultLine = smoothstep(0.48, 0.50, fault) * smoothstep(0.52, 0.50, fault);
    layerCol *= 1.0 - faultLine * 0.3;

    // -- Color --------------------------------------------------------
    vec3 color = layerCol;

    // -- Text on top --------------------------------------------------
    color = mix(color, term, textMask);

    // -- Focus dim ----------------------------------------------------
    float focusT   = clamp((iTime - iTimeFocus) * 1.5, 0.0, 1.0);
    float focusMix = iFocus == 1 ? focusT : 1.0 - focusT;
    float grey     = dot(color, vec3(0.299, 0.587, 0.114));
    color = mix(vec3(grey), color, mix(0.3, 1.0, focusMix)) * mix(0.55, 1.0, focusMix);

    fragColor = vec4(clamp(color, 0.0, 1.0), termRaw.a);
}
