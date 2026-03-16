// tattoo.glsl — skin as substrate, text as ink aging in dermis
//
// iChannel0 = terminal content
// iChannel2 = compute state (R = accumulated tan per pixel)
//
// Cursor UV encoded into output pixel (0,0) each frame so compute
// shader can read it from feedback next frame.
//
// Age model: age = (1.0 - uv.y) * BASE_AGE + iTime * DRIFT_RATE
// Posterized into bands: fresh / settled / aged / scattered / ghost
// Each band increases bleed radius and blue-shifts ink edges
//
// Skin derives continuously from terminal bg:
//   melanin  = 1 - bgLuma           (dark bg → more melanin)
//   undertone = bg chroma direction  (warm/cool independent of depth)
//
// Lighting: normal map from FBM + pore heightfield.
// Light position tracks iCurrentCursor — rake it across the skin.

// ── Tuning ────────────────────────────────────────────────────────────────────
#define BASE_AGE        1.5    // age range across full scroll height (years-ish)
#define DRIFT_RATE      0.012  // realtime aging rate (per second)
#define AGE_BANDS       5      // number of discrete age states
#define BLEED_MAX       2.5    // max pixel bleed radius at oldest age
#define BLUE_SHIFT_MAX  0.5    // how blue the fringe gets at oldest age
#define LIGHT_HEIGHT    1.2    // virtual z-distance of light above surface
#define DIFFUSE_STR     0.18   // Lambert diffuse strength
#define SPECULAR_STR    0.10   // Blinn-Phong specular strength
#define SPECULAR_EXP    32.0   // specular shininess (higher = tighter highlight)
#define AMBIENT         0.82   // ambient light floor
#define INK_DEPTH       0.6    // how much ink depresses the surface normal
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

// Skin heightfield: coarse topology + fine pores
float skinHeight(vec2 p) {
    return fbm(p * 8.0) * 0.7           // coarse skin surface
         + fbm(p * 55.0) * 0.3;         // pore-scale detail
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec2 px = 1.0 / iResolution.xy;
    float aspect = iResolution.x / iResolution.y;

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

    // Bleed: radial gaussian spread of ink mask
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

    // Ink color: preserve original terminal color, blue-shift with age
    float blueShift = age * BLUE_SHIFT_MAX;
    float fringe = clamp(bleedMask - inkMask, 0.0, 1.0);
    vec3 inkColor = term;
    inkColor.b += blueShift * (inkMask + fringe);
    inkColor.r -= blueShift * (inkMask + fringe) * 0.4;
    inkColor = clamp(inkColor, 0.0, 1.0);

    // ── Skin: continuous chromophore model ────────────────────────────────
    float bgLuma = luma(bgColor);
    float melanin = 1.0 - bgLuma;
    float warmth  = clamp((bgColor.r - bgColor.b) * 2.0 + 0.5, 0.0, 1.0);

    // ── Tan: accumulated per-pixel exposure from compute ──────────────────
    float tan = texture(iChannel2, uv).r;
    // Fair skin tans more dramatically; deep skin barely changes
    float tanInfluence = tan * mix(0.5, 0.05, melanin);
    melanin = clamp(melanin + tanInfluence, 0.0, 0.95);
    // Tanning also warms the undertone slightly
    warmth = clamp(warmth + tan * mix(0.3, 0.05, melanin), 0.0, 1.0);

    float sssStrength = mix(0.55, 0.08, melanin);
    float skinGrain   = mix(0.25, 0.60, melanin);

    vec3 fairCool = vec3(0.98, 0.94, 0.93);  // deep Nordic — cool porcelain
    vec3 fairWarm = vec3(0.96, 0.90, 0.80);
    vec3 midCool  = vec3(0.62, 0.46, 0.40);
    vec3 midWarm  = vec3(0.70, 0.52, 0.34);
    vec3 deepCool = vec3(0.28, 0.18, 0.16);
    vec3 deepWarm = vec3(0.35, 0.22, 0.12);

    vec3 fairTone = mix(fairCool, fairWarm, warmth);
    vec3 midTone  = mix(midCool,  midWarm,  warmth);
    vec3 deepTone = mix(deepCool, deepWarm, warmth);

    vec3 skinBase;
    if (melanin < 0.5) {
        skinBase = mix(fairTone, midTone, melanin * 2.0);
    } else {
        skinBase = mix(midTone, deepTone, (melanin - 0.5) * 2.0);
    }

    // Fine grain
    float grain = (fbm(uv * 60.0) - 0.5) * 0.03 * skinGrain;
    skinBase += grain;

    // ── Subsurface scattering ─────────────────────────────────────────────
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
    skinBase += sssBlur * sssShift * sssStrength * 0.15 * (1.0 - bleedMask);

    // ── Normal map from skin heightfield ─────────────────────────────────
    // Blur the heightfield over a small neighborhood to soften pocking
    float eps = 3.0 * px.x;
    float hC = 0.0, hR = 0.0, hU = 0.0;
    float hW = 0.0;
    for (int i = -1; i <= 1; i++) {
        for (int j = -1; j <= 1; j++) {
            float w = 1.0 - length(vec2(i,j)) * 0.3;
            vec2 o = vec2(i, j) * eps;
            hC += skinHeight(uv          + o) * w;
            hR += skinHeight(uv + vec2(eps, 0.0) + o) * w;
            hU += skinHeight(uv + vec2(0.0, eps) + o) * w;
            hW += w;
        }
    }
    hC /= hW; hR /= hW; hU /= hW;

    // Ink depresses the surface
    float inkDepression = bleedMask * INK_DEPTH * 0.08;
    hC -= inkDepression;
    hR -= inkDepression;
    hU -= inkDepression;

    // Reduced normal scale = less height difference = smoother surface
    float normalScale = mix(0.35, 0.7, melanin);
    vec3 normal = normalize(vec3(
        (hC - hR) * normalScale * aspect,
        (hC - hU) * normalScale,
        1.0
    ));

    // ── Lighting — cursor as light source ─────────────────────────────────
    // iCurrentCursor.xy = pixel position of cursor
    vec2 cursorUV = iCurrentCursor.xy / iResolution.xy;
    vec3 lightPos = vec3(cursorUV.x, cursorUV.y, LIGHT_HEIGHT);
    vec3 lightDir = normalize(lightPos - vec3(uv, 0.0));

    // Warm light color, slightly warmer for fair skin
    vec3 lightColor = mix(vec3(1.0, 0.95, 0.88), vec3(1.0, 0.90, 0.78), melanin);

    // Lambert diffuse
    float diffuse = max(dot(normal, lightDir), 0.0) * DIFFUSE_STR;

    // Blinn-Phong specular — skin has a subtle sheen
    vec3 viewDir = vec3(0.0, 0.0, 1.0); // orthographic view
    vec3 halfDir = normalize(lightDir + viewDir);
    float spec = pow(max(dot(normal, halfDir), 0.0), SPECULAR_EXP);
    // Fair skin: more specular. Deep skin: less, more matte.
    float specStr = SPECULAR_STR * mix(1.0, 0.3, melanin);
    float specular = spec * specStr;

    // Ink is matte — suppress specular where ink is
    specular *= (1.0 - inkMask * 0.85);

    float lighting = AMBIENT + diffuse + specular;
    vec3 lightTint = mix(vec3(lighting), lightColor * lighting, 0.4);

    // ── Composite: ink into skin ──────────────────────────────────────────
    vec3 haloColor = mix(skinBase, skinBase * 0.82, bleedMask * 0.6);
    vec3 color = mix(skinBase, haloColor, bleedMask);

    vec3 inkEmbedded = mix(skinBase * inkColor * 1.6, inkColor, 0.55);
    color = mix(color, inkEmbedded, inkMask);
    color *= 1.0 - inkMask * 0.05;

    // Apply lighting — skin gets it, ink gets it less (ink absorbs light)
    color *= lightTint;

    // ── Focus dim ─────────────────────────────────────────────────────────
    float focusT = clamp((iTime - iTimeFocus) * 1.5, 0.0, 1.0);
    float focusMix = iFocus == 1 ? focusT : 1.0 - focusT;
    float dimAmount = mix(0.6, 1.0, focusMix);
    float satAmount = mix(0.4, 1.0, focusMix);
    vec3 grey = vec3(luma(color));
    color = mix(grey, color, satAmount) * dimAmount;

    // ── Encode cursor UV into pixel (0,0) for compute shader ─────────────
    // Compute reads this from feedback next frame to know light position
    vec2 cursorUV = iCurrentCursor.xy / iResolution.xy;
    if (fragCoord.x < 1.0 && fragCoord.y < 1.0) {
        fragColor = vec4(cursorUV, 0.0, 1.0);
        return;
    }

    fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
