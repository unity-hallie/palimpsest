// tattoo.glsl — skin as substrate, text as ink aging in dermis
//
// iChannel0 = terminal content
// iChannel2 = compute state (R = accumulated tan per pixel)
//
// Cursor UV encoded into output pixel (0,0) each frame so compute
// shader can read it from feedback next frame.
//
// Age: continuous — (1 - uv.y) * BASE_AGE + iTime * DRIFT_RATE
// Skin tone: continuous from iBackgroundColor (melanin + warmth axes)
// Lighting: normal map from FBM heightfield, cursor as light source

// ── Tuning ────────────────────────────────────────────────────────────────────
#define BASE_AGE        1.5    // age range across full scroll height
#define DRIFT_RATE      0.012  // realtime aging rate per second
#define BLEED_MAX       2.5    // max pixel bleed radius at oldest age
#define BLUE_SHIFT_MAX  0.5    // max blue shift at top of screen
#define LIGHT_HEIGHT    1.2    // virtual z-distance of light above surface
#define DIFFUSE_STR     0.10   // Lambert diffuse strength
#define SPECULAR_STR    0.06   // Blinn-Phong specular strength
#define SPECULAR_EXP    28.0   // specular shininess
#define AMBIENT         0.92   // ambient light floor
// ─────────────────────────────────────────────────────────────────────────────

float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i+vec2(1,0)), f.x),
               mix(hash(i+vec2(0,1)), hash(i+vec2(1,1)), f.x), f.y);
}

float fbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.1; a *= 0.5; }
    return v;
}

float skinHeight(vec2 p) {
    return fbm(p * 8.0) * 0.7 + fbm(p * 55.0) * 0.3;
}

// Ink detection: how different is this pixel from the background?
float inkDetect(vec3 s, vec3 bg) {
    return smoothstep(0.04, 0.22, max(abs(luma(s) - luma(bg)), length(s - bg) * 0.7));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv  = fragCoord / iResolution.xy;
    vec2 px  = 1.0 / iResolution.xy;
    float aspect = iResolution.x / iResolution.y;

    // ── Age — continuous, no bands ────────────────────────────────────────
    float age = clamp(((1.0 - uv.y) * BASE_AGE + iTime * DRIFT_RATE) / (BASE_AGE + 1.0), 0.0, 1.0);
    float bleedRadius = age * BLEED_MAX;

    // ── Terminal ink ──────────────────────────────────────────────────────
    vec3 term    = texture(iChannel0, uv).rgb;
    vec3 bgColor = iBackgroundColor.rgb;

    // Ink mask with 1px AA
    float inkMask = inkDetect(term, bgColor);
    float aaBlur = 0.0, aaW = 0.0;
    for (int i = -1; i <= 1; i++) {
        for (int j = -1; j <= 1; j++) {
            float w = 1.0 - length(vec2(i,j)) * 0.35;
            vec2 sUV = clamp(uv + vec2(i,j) * px, 0.001, 0.999);
            aaBlur += inkDetect(texture(iChannel0, sUV).rgb, bgColor) * w;
            aaW += w;
        }
    }
    inkMask = mix(inkMask, aaBlur / aaW, 0.4);

    // Bleed: radial gaussian — kernel size scales with age to save samples
    // fresh (age~0): skip entirely. mid: 3×3. old: 5×5.
    float bleedMask = inkMask;
    int bleedTaps = age < 0.25 ? 0 : (age < 0.6 ? 1 : 2);
    if (bleedTaps > 0 && bleedRadius > 0.5) {
        float bleedAcc = 0.0, bleedW = 0.0;
        float sigma2 = bleedRadius * bleedRadius;
        for (int i = -bleedTaps; i <= bleedTaps; i++) {
            for (int j = -bleedTaps; j <= bleedTaps; j++) {
                float dist2 = float(i*i + j*j);
                float r = sqrt(dist2);
                if (r > bleedRadius + 0.5) continue;
                float w = exp(-dist2 / (sigma2 * 0.5))
                        * smoothstep(bleedRadius + 0.5, bleedRadius - 0.5, r);
                vec2 sUV = clamp(uv + vec2(i,j) * px * bleedRadius, 0.001, 0.999);
                bleedAcc += inkDetect(texture(iChannel0, sUV).rgb, bgColor) * w;
                bleedW += w;
            }
        }
        bleedMask = clamp(bleedAcc / max(bleedW, 0.001), 0.0, 1.0);
    }

    // Ink color: blue-shift fades out in bottom third
    float blueShift = age * BLUE_SHIFT_MAX * smoothstep(0.65, 0.25, uv.y);
    float fringe = clamp(bleedMask - inkMask, 0.0, 1.0);
    vec3 inkColor = clamp(term + vec3(-1.0, 0.0, 1.0) * blueShift * (inkMask + fringe) * vec3(0.4, 0.0, 1.0), 0.0, 1.0);

    // ── Skin: continuous chromophore model ────────────────────────────────
    float bgLuma  = luma(bgColor);
    float melanin = 1.0 - bgLuma;
    float warmth  = clamp((bgColor.r - bgColor.b) * 2.0 + 0.5, 0.0, 1.0);

    // Tan disabled — TODO: revisit compute approach to avoid visible disc artifact

    float sssStrength = mix(0.55, 0.08, melanin);
    float skinGrain   = mix(0.25, 0.60, melanin);

    // Skin gamut: melanin × warmth
    // Three-point mix: fair → mid → deep, fully continuous
    vec3 fairTone = mix(vec3(0.94,0.88,0.86), vec3(0.96,0.90,0.80), warmth);
    vec3 midTone  = mix(vec3(0.62,0.46,0.40), vec3(0.70,0.52,0.34), warmth);
    vec3 deepTone = mix(vec3(0.28,0.18,0.16), vec3(0.35,0.22,0.12), warmth);
    vec3 skinBase = mix(fairTone, mix(midTone, deepTone, clamp(melanin*2.0-1.0, 0.0,1.0)),
                        smoothstep(0.0, 1.0, melanin));

    skinBase += (fbm(uv * 120.0) - 0.5) * 0.025 * skinGrain;

    // SSS — sum of 3 gaussians, each wider and redder
    // Narrow: surface detail. Mid: dermis blush. Wide: deep red scatter.
    // RGB weights per layer: red travels furthest, blue barely at all.
    vec3 sss = vec3(0.0);
    // Layer 1: narrow (2px), full spectrum
    vec3 n1 = vec3(0.0); float w1 = 0.0;
    for (int i = -2; i <= 2; i++) { for (int j = -2; j <= 2; j++) {
        float d2 = float(i*i+j*j); float w = exp(-d2 / 2.0);
        n1 += texture(iChannel0, clamp(uv+vec2(i,j)*px*2.0,0.001,0.999)).rgb * w;
        w1 += w; } }
    sss += (n1/w1) * vec3(1.20, 0.80, 0.70) * 0.40;
    // Layer 2: mid (6px), red-shifted
    vec3 n2 = vec3(0.0); float w2 = 0.0;
    for (int i = -2; i <= 2; i++) { for (int j = -2; j <= 2; j++) {
        float d2 = float(i*i+j*j); float w = exp(-d2 / 4.0);
        n2 += texture(iChannel0, clamp(uv+vec2(i,j)*px*6.0,0.001,0.999)).rgb * w;
        w2 += w; } }
    sss += (n2/w2) * vec3(1.50, 0.60, 0.40) * 0.35;
    // Layer 3: wide (14px), deep red only
    vec3 n3 = vec3(0.0); float w3 = 0.0;
    for (int i = -2; i <= 2; i++) { for (int j = -2; j <= 2; j++) {
        float d2 = float(i*i+j*j); float w = exp(-d2 / 6.0);
        n3 += texture(iChannel0, clamp(uv+vec2(i,j)*px*14.0,0.001,0.999)).rgb * w;
        w3 += w; } }
    sss += (n3/w3) * vec3(1.80, 0.30, 0.20) * 0.25;

    skinBase += sss * sssStrength * 0.18 * (1.0 - bleedMask);

    // ── Normal map — direct central differences ───────────────────────────
    float eps = 0.014;  // wider sample distance = smoother normals
    float hC = skinHeight(uv);
    float hR = skinHeight(uv + vec2(eps, 0.0));
    float hU = skinHeight(uv + vec2(0.0, eps));
    float normalScale = mix(0.10, 0.20, melanin);
    vec3 normal = normalize(vec3(
        (hC - hR) * normalScale * aspect,
        (hU - hC) * normalScale,
        1.0));

    // ── Lighting — offscreen sun, 2-minute day/night cycle ────────────────
    float sunT    = iTime / 120.0 * 6.28318;  // full cycle in 120s
    // Sun traces an arc: x swings across, y rises/sets (y=0 is top in UV)
    vec2  sunUV   = vec2(0.5 + 0.7 * cos(sunT), 0.5 - 0.55 * sin(sunT));
    float sunH    = sin(sunT);  // >0 = above horizon, <0 = below
    float dayness = smoothstep(-0.15, 0.25, sunH);  // smooth dawn/dusk

    vec3 lightDir  = normalize(vec3(sunUV - uv, LIGHT_HEIGHT));
    // Day: warm golden. Night: cool blue moonlight.
    vec3 dayColor  = mix(vec3(1.0,0.85,0.65), vec3(1.0,0.97,0.90), dayness);  // sunrise→noon
    vec3 nightColor = vec3(0.55, 0.65, 0.90);
    vec3 lightColor = mix(nightColor, dayColor, dayness);
    // Night ambient drops, day ambient is full
    float nightAmbient = AMBIENT * 0.45;
    float ambientLevel = mix(nightAmbient, AMBIENT, dayness);

    // Wrapped diffuse — terminator is a smooth sine wave, never fully dark
    // Sun contribution
    float diffuse  = (dot(normal, lightDir) * 0.5 + 0.5) * DIFFUSE_STR;
    vec3  halfDir  = normalize(lightDir + vec3(0,0,1));
    float specular = pow(max(dot(normal, halfDir), 0.0), SPECULAR_EXP)
                   * SPECULAR_STR * mix(1.0, 0.3, melanin)
                   * (1.0 - inkMask * 0.85);

    // Artificial light — fades in as sun sets
    float nightness = 1.0 - dayness;
    float flicker = 1.0
        + sin(iTime * 2.1)  * 0.025
        + sin(iTime * 3.7)  * 0.015
        + sin(iTime * 1.3)  * 0.035;
    vec2  lampUV   = vec2(0.72, 0.28);
    vec3  lampDir  = normalize(vec3(lampUV - uv, LIGHT_HEIGHT * 0.8));
    vec3  lampHalf = normalize(lampDir + vec3(0,0,1));
    float lampDiff = (dot(normal, lampDir) * 0.5 + 0.5) * DIFFUSE_STR * 2.2;
    float lampSpec = pow(max(dot(normal, lampHalf), 0.0), SPECULAR_EXP)
                   * SPECULAR_STR * mix(1.2, 0.3, melanin)
                   * (1.0 - inkMask * 0.85);
    vec3  lampColor   = vec3(1.0, 0.72, 0.38) * flicker;  // incandescent ~2700K
    float lampLighting = (lampDiff + lampSpec) * nightness;

    float lighting = clamp(ambientLevel + diffuse * dayness + specular * dayness + lampLighting, 0.0, 1.2);
    vec3 sunTint   = mix(vec3(1.0), lightColor, 0.4);
    vec3 lampTint  = mix(vec3(1.0), lampColor,  0.5);
    vec3 lightTint = mix(sunTint, lampTint, nightness * smoothstep(0.0, 0.3, nightness)) * lighting;

    // ── Composite ─────────────────────────────────────────────────────────
    vec3 color = mix(skinBase, mix(skinBase, skinBase * 0.82, 0.6), bleedMask);
    color = mix(color, mix(skinBase * inkColor * 1.6, inkColor, 0.55), inkMask);
    color *= (1.0 - inkMask * 0.05) * lightTint;

    // ── Focus dim ─────────────────────────────────────────────────────────
    float focusT   = clamp((iTime - iTimeFocus) * 1.5, 0.0, 1.0);
    float focusMix = iFocus == 1 ? focusT : 1.0 - focusT;
    float dim      = mix(0.6, 1.0, focusMix);
    float sat      = mix(0.4, 1.0, focusMix);
    color = mix(vec3(luma(color)), color, sat) * dim;

    // ── Encode sun UV into pixel (0,0) for compute shader (future tanning) ──
    if (fragCoord.x < 1.0 && fragCoord.y < 1.0) {
        fragColor = vec4(sunUV, 0.0, 1.0);
        return;
    }

    fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
