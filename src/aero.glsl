// aero.glsl -- breath on cold glass
//
// You're looking through a window. Someone breathes on it. Fog blooms,
// condensation beads in the humid center, the world behind goes soft
// and bright. Between breaths, the glass clears from the edges in.
//
// iChannel0 = terminal content
// iChannel2 = compute state (R=fog, G=water, B=temperature)

// -- Tuning ----------------------------------------------------------
#define FOG_BLUR            0.50     // how much fog tints the background (not text)
#define FOG_WHITE           0.92     // fog brightness -- warm bright white, not grey

#define REFRACT_STRENGTH    0.10
#define NORMAL_SCALE        5.0
#define DROPLET_DEPTH       1.6

#define SPECULAR            0.16     // glossy condensation highlights
#define SPECULAR_TIGHT      24.0

#define EDGE_DARKEN         0.10
#define TEXT_BRIGHTNESS     0.93
#define CLEAR_TEXT_BOOST    1.0      // text is crispest where glass is clear

// Background -- iMac blue sky meets greenhouse
#define BG_WARM             vec3(0.72, 0.92, 0.98)  // bright sky-aqua center
#define BG_COOL             vec3(0.55, 0.82, 0.70)  // green at edges
// ====================================================================

//@ include "common.glsl"

// -- The world behind the glass --------------------------------------
// Not a scene. Just light. Warm, diffuse, the way everything looks
// when you can't quite see through the fog.
vec3 behindGlass(vec2 uv, float fog) {
    // Base: bright green-white center, aqua edges
    float vignette = length(uv - vec2(0.5)) * 1.3;
    vec3 light = mix(BG_WARM, BG_COOL, smoothstep(0.0, 1.0, vignette));
    // Vertical: bluer sky at top, greener at bottom
    light += vec3(-0.04, -0.02, 0.06) * smoothstep(1.0, 0.0, uv.y);  // blue up top
    light += vec3(0.02, 0.08, 0.02) * smoothstep(0.0, 1.0, uv.y);    // green below

    // Dappled light -- sun through leaves and water
    float n = noise(uv * 4.0 + vec2(iTime * 0.003, iTime * 0.002));
    float n2 = noise(uv * 7.0 + vec2(-iTime * 0.002, 0.5));
    light += vec3(-0.02, 0.05, 0.06) * (n - 0.4);   // aqua dapple
    light += vec3(0.01, 0.06, 0.02) * (n2 - 0.5);   // green shift

    // Fog scatters to bright white-blue
    light = mix(light, vec3(0.92, 0.96, 0.98), fog * 0.35);

    return light;
}

// ====================================================================

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2  uv = fragCoord / iResolution.xy;
    vec2  px = 1.0 / iResolution.xy;

    // -- Compute state ----------------------------------------------
    vec4  state = texture(iChannel2, uv);
    float fog   = state.r;
    float water = state.g;
    float temp  = state.b;

    // -- Fog: sample neighborhood for soft visual blur --------------
    float fogBlur = 0.0;
    float samples = 0.0;
    for (int x = -2; x <= 2; x++) {
        for (int y = -2; y <= 2; y++) {
            vec2 off = vec2(float(x), float(y)) * px * 3.0;
            fogBlur += texture(iChannel2, uv + off).r;
            samples += 1.0;
        }
    }
    fogBlur /= samples;
    float visFog = max(fog, fogBlur * 0.8); // smoothed fog for visual

    // -- Water normal -----------------------------------------------
    float wL = texture(iChannel2, uv + vec2(-px.x, 0.0)).g;
    float wR = texture(iChannel2, uv + vec2( px.x, 0.0)).g;
    float wU = texture(iChannel2, uv + vec2(0.0, -px.y)).g;
    float wD = texture(iChannel2, uv + vec2(0.0,  px.y)).g;
    vec2  grad = vec2(wR - wL, wD - wU) * NORMAL_SCALE;

    float isWet = smoothstep(0.02, 0.10, water);
    float beadHeight = water * water * DROPLET_DEPTH;

    // -- Terminal text ----------------------------------------------
    vec3 terminal = texture(iChannel0, uv).rgb * TEXT_BRIGHTNESS;

    // -- Background light through glass -----------------------------
    vec3 bg = behindGlass(uv, visFog);

    // -- Text mask -- detect where terminal has text vs background ----
    vec3 bgColor = vec3(0.839, 0.941, 0.961);  // #D6F0F5
    float distFromBg = length(texture(iChannel0, uv).rgb - bgColor);
    float textMask = smoothstep(0.03, 0.12, distFromBg);

    // -- Background layer: fog tints the bg, not the text ----------
    vec3 fogColor = vec3(FOG_WHITE) * (0.92 + 0.08 * temp);
    vec3 glass = mix(bg, fogColor, visFog * FOG_BLUR);
    // Add subtle bright glow in fog center
    glass += vec3(0.06, 0.04, 0.02) * visFog * temp;

    // -- Condensation droplets on the background layer --------------
    if (isWet > 0.01) {
        vec2 safeGrad = grad;
        float gMag = length(grad);
        if (gMag > 3.0) safeGrad *= 3.0 / gMag;

        vec2 refractUV = clamp(uv + safeGrad * REFRACT_STRENGTH * beadHeight, 0.001, 0.999);
        vec3 throughDrop = behindGlass(refractUV, visFog * 0.2);

        vec3 dropScene = throughDrop * 0.6;

        // Fresnel edge
        float edgeDist = gMag / max(water, 0.01);
        float fresnel = smoothstep(0.0, 8.0, edgeDist);
        dropScene *= 1.0 - fresnel * EDGE_DARKEN;

        // Glossy specular
        float nMag = length(safeGrad);
        vec2  nDir = safeGrad / max(nMag, 0.001);
        vec2  light1 = normalize(vec2(-0.3, -0.5));
        float s1 = pow(max(dot(nDir, light1), 0.0), SPECULAR_TIGHT) * nMag * SPECULAR * beadHeight;
        dropScene += vec3(1.0, 0.98, 0.95) * s1;

        vec2  light2 = normalize(vec2(0.4, -0.3));
        float s2 = pow(max(dot(nDir, light2), 0.0), 16.0) * nMag * 0.05 * beadHeight;
        dropScene += vec3(0.9, 0.92, 0.95) * s2;

        glass = mix(glass, dropScene, isWet);
    }

    // -- Final compose: text ALWAYS on top, full strength ----------
    vec3 color = mix(glass, terminal, textMask);

    fragColor = vec4(clamp(color, 0.0, 1.0), texture(iChannel0, uv).a);
}
