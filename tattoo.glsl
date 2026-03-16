// tattoo.glsl — skin as substrate, text as ink aging in dermis
//
// iChannel0 = terminal content
//
// Age model: age = (1.0 - uv.y) * BASE_AGE + iTime * DRIFT_RATE
// Posterized into bands: fresh / settled / aged / scattered / ghost
// Each band increases bleed radius and blue-shifts ink edges
//
// Skin derives continuously from terminal bg:
//   melanin  = 1 - bgLuma           (dark bg → more melanin)
//   undertone = bg chroma direction  (warm/cool independent of depth)

// ── Tuning ────────────────────────────────────────────────────────────────────
#define BASE_AGE        1.5    // age range across full scroll height (years-ish)
#define DRIFT_RATE      0.012  // realtime aging rate (per second)
#define AGE_BANDS       5      // number of discrete age states
#define BLEED_MAX       2.5    // max pixel bleed radius at oldest age
#define BLUE_SHIFT_MAX  0.5    // how blue the fringe gets at oldest age
// ─────────────────────────────────────────────────────────────────────────────

float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash(i), hash(i + vec2(1,0)), f.x),
        mix(hash(i + vec2(0,1)), hash(i + vec2(1,1)), f.x),
        f.y
    );
}

float fbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 5; i++) {
        v += a * noise(p);
        p *= 2.1;
        a *= 0.5;
    }
    return v;
}

float ageBand(float age) {
    return floor(clamp(age, 0.0, 1.0) * float(AGE_BANDS)) / float(AGE_BANDS);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec2 px = 1.0 / iResolution.xy;

    // ── Age ───────────────────────────────────────────────────────────────
    float rawAge = (1.0 - uv.y) * BASE_AGE + iTime * DRIFT_RATE;
    float age = ageBand(clamp(rawAge / (BASE_AGE + 1.0), 0.0, 1.0));
    float bleedRadius = age * BLEED_MAX;

    // ── Terminal ink ──────────────────────────────────────────────────────
    vec3 term = texture(iChannel0, uv).rgb;
    vec3 bgColor = iBackgroundColor.rgb;

    // Detect ink by color distance from bg — catches colored text, not just dark
    float lumaDiff  = abs(luma(term) - luma(bgColor));
    float colorDiff = length(term - bgColor);
    float inkMask   = smoothstep(0.04, 0.22, max(lumaDiff, colorDiff * 0.7));

    // Tiny AA: soften the ink edge by one pixel
    float aaBlur = 0.0, aaW = 0.0;
    for (int i = -1; i <= 1; i++) {
        for (int j = -1; j <= 1; j++) {
            float w = 1.0 - length(vec2(i,j)) * 0.35;
            vec2 sUV = clamp(uv + vec2(i,j) * px, 0.001, 0.999);
            vec3 s = texture(iChannel0, sUV).rgb;
            float d = max(abs(luma(s)-luma(bgColor)), length(s-bgColor)*0.7);
            aaBlur += smoothstep(0.04, 0.22, d) * w;
            aaW += w;
        }
    }
    inkMask = mix(inkMask, aaBlur / aaW, 0.4);

    // Bleed: radial gaussian spread of ink mask — no square grid artifacts
    float bleedMask = inkMask;
    if (bleedRadius > 0.5) {
        float bleedAcc = 0.0, bleedW = 0.0;
        float sigma2 = bleedRadius * bleedRadius;
        for (int i = -3; i <= 3; i++) {
            for (int j = -3; j <= 3; j++) {
                float dist2 = float(i*i + j*j);
                float r = sqrt(dist2);
                if (r > bleedRadius + 0.5) continue;
                float w = exp(-dist2 / (sigma2 * 0.5))
                        * smoothstep(bleedRadius + 0.5, bleedRadius - 0.5, r);
                vec2 sUV = clamp(uv + vec2(i, j) * px * bleedRadius, 0.001, 0.999);
                vec3 s = texture(iChannel0, sUV).rgb;
                float d = max(abs(luma(s)-luma(bgColor)), length(s-bgColor)*0.7);
                bleedAcc += smoothstep(0.04, 0.22, d) * w;
                bleedW += w;
            }
        }
        bleedMask = clamp(bleedAcc / max(bleedW, 0.001), 0.0, 1.0);
    }

    // Ink color: preserve original terminal color, blue-shift fringe with age
    float blueShift = age * BLUE_SHIFT_MAX;
    float fringe = clamp(bleedMask - inkMask, 0.0, 1.0);
    vec3 inkColor = term;
    inkColor.b += blueShift * (inkMask + fringe);   // core color also ages
    inkColor.r -= blueShift * (inkMask + fringe) * 0.4;
    inkColor = clamp(inkColor, 0.0, 1.0);

    // ── Skin: continuous chromophore model ────────────────────────────────
    float bgLuma = luma(bgColor);
    float melanin = 1.0 - bgLuma;  // dark bg → more melanin

    // Chroma direction: how warm or cool the bg hue is
    // warm = (r-b) > 0, cool = (r-b) < 0
    float warmth = clamp((bgColor.r - bgColor.b) * 2.0 + 0.5, 0.0, 1.0);

    // Derive skin properties continuously from melanin + warmth
    float sssStrength  = mix(0.55, 0.08, melanin);   // translucency fades with melanin
    float skinGrain    = mix(0.25, 0.60, melanin);   // deeper skin, more texture

    // Skin base tone: interpolate across a perceptual skin gamut
    // axis 1: melanin (fair → deep)
    // axis 2: warmth (cool-pink ↔ warm-golden)
    vec3 fairCool  = vec3(0.97, 0.91, 0.89);  // Nordic pink, near-white
    vec3 fairWarm  = vec3(0.96, 0.90, 0.80);  // warm ivory, near-white
    vec3 midCool   = vec3(0.62, 0.46, 0.40);  // cool medium
    vec3 midWarm   = vec3(0.70, 0.52, 0.34);  // warm medium/olive
    vec3 deepCool  = vec3(0.28, 0.18, 0.16);  // cool deep
    vec3 deepWarm  = vec3(0.35, 0.22, 0.12);  // warm deep

    vec3 fairTone = mix(fairCool, fairWarm, warmth);
    vec3 midTone  = mix(midCool,  midWarm,  warmth);
    vec3 deepTone = mix(deepCool, deepWarm, warmth);

    // Two-stage mix: fair→mid, mid→deep
    vec3 skinBase;
    if (melanin < 0.5) {
        skinBase = mix(fairTone, midTone, melanin * 2.0);
    } else {
        skinBase = mix(midTone, deepTone, (melanin - 0.5) * 2.0);
    }

    // Grain — fine, high frequency only, no large patches
    float grain = (fbm(uv * 60.0) - 0.5) * 0.03 * skinGrain;
    skinBase += grain;

    // ── Subsurface scattering — tight blur, just a warm blush near ink ────
    // Small radius so it doesn't blob: 1px offset, 3x3 kernel
    vec3 sssBlur = vec3(0.0);
    float sssW = 0.0;
    for (int i = -1; i <= 1; i++) {
        for (int j = -1; j <= 1; j++) {
            float w = 1.0;
            vec2 sUV = clamp(uv + vec2(i, j) * px * 2.0, 0.001, 0.999);
            sssBlur += texture(iChannel0, sUV).rgb * w;
            sssW += w;
        }
    }
    sssBlur /= sssW;
    vec3 sssShift = mix(vec3(1.3, 0.7, 0.6), vec3(1.1, 0.9, 0.8), melanin);
    vec3 sssColor = sssBlur * sssShift;
    skinBase += sssColor * sssStrength * 0.15 * (1.0 - bleedMask);

    // ── Composite: ink into skin ──────────────────────────────────────────
    // Halo: ink sinks into skin around glyphs, thins out toward edge
    vec3 haloColor = mix(skinBase, skinBase * 0.82, bleedMask * 0.6);
    vec3 color = mix(skinBase, haloColor, bleedMask);

    // Core: terminal color always reads, embedded in skin (not on top)
    // Mix between skin-tinted ink and pure ink so color comes through
    vec3 inkEmbedded = mix(skinBase * inkColor * 1.6, inkColor, 0.55);
    color = mix(color, inkEmbedded, inkMask);
    color *= 1.0 - inkMask * 0.05;

    // ── Focus dim ─────────────────────────────────────────────────────────
    float focusT = clamp((iTime - iTimeFocus) * 1.5, 0.0, 1.0);
    float focusMix = iFocus == 1 ? focusT : 1.0 - focusT;
    float dimAmount = mix(0.6, 1.0, focusMix);
    float satAmount = mix(0.4, 1.0, focusMix);
    vec3 grey = vec3(luma(color));
    color = mix(grey, color, satAmount) * dimAmount;

    fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
