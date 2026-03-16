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

// Body macro-shape: small-of-back concave dip at lower-center, flat at edges.
// Negative = surface dips away from viewer (concave bowl).
float bodyHeight(vec2 p) {
    float cx  = p.x - 0.5;
    float cy  = p.y - 0.68;                       // dip center in lower half
    // Envelope: falls to zero at all four edges
    float ex  = 1.0 - smoothstep(0.15, 0.46, abs(cx));
    float ey  = smoothstep(0.10, 0.35, p.y) * (1.0 - smoothstep(0.72, 0.96, p.y));
    float env = ex * ey;
    // Convex dome shape — small of back rises toward viewer
    float bowl = exp(-(cx*cx * 9.0 + cy*cy * 5.5)) * 0.55;
    // Slight side-to-side convex ridge away from dip (the flanks of the back)
    float flanks = exp(-cx*cx * 1.8) * 0.08 * smoothstep(0.0, 0.4, p.y);
    return (bowl + flanks) * env;
}

float skinHeight(vec2 p) {
    return fbm(p * 8.0) * 0.7 + fbm(p * 55.0) * 0.3 + bodyHeight(p) * 0.8;
}

// Ink detection: how different is this pixel from the background?
float inkDetect(vec3 s, vec3 bg) {
    return smoothstep(0.04, 0.22, max(abs(luma(s) - luma(bg)), length(s - bg) * 0.7));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv  = fragCoord / iResolution.xy;
    vec2 px  = 1.0 / iResolution.xy;
    float aspect = iResolution.x / iResolution.y;

    // ── Breath waveform — computed once, used per node ────────────────────
    float breathPeriod = 30.0;
    float tau = 6.28318 / breathPeriod;
    float raw = sin(iTime * tau) * 0.72
              + sin(iTime * tau * 2.0 + 1.1) * 0.18
              + sin(iTime * tau * 3.0 + 0.5) * 0.06;
    float breath = clamp((raw - 0.14) / 0.82, -1.0, 1.0);

    // ── Body mesh deformation ─────────────────────────────────────────────
    // 8×6 grid. Boundary nodes pinned → edges stay flat.
    // Interior nodes breathe radially from the back's center.
    #define MESH_COLS 8
    #define MESH_ROWS 6
    vec2  dipCenter = vec2(0.5, 0.68);
    vec2  meshDisp  = vec2(0.0);
    float totalW    = 0.0;
    float bEps      = 0.02;
    for (int mi = 0; mi < MESH_COLS; mi++) {
        for (int mj = 0; mj < MESH_ROWS; mj++) {
            vec2 nodeUV = vec2(float(mi) / float(MESH_COLS - 1),
                               float(mj) / float(MESH_ROWS - 1));
            bool onEdge = (mi == 0 || mi == MESH_COLS-1 || mj == 0 || mj == MESH_ROWS-1);
            // Base: follow bodyHeight gradient so text wraps the shape
            float gx = (bodyHeight(nodeUV + vec2(bEps,0.0)) - bodyHeight(nodeUV - vec2(bEps,0.0))) / (2.0*bEps);
            float gy = (bodyHeight(nodeUV + vec2(0.0,bEps)) - bodyHeight(nodeUV - vec2(0.0,bEps))) / (2.0*bEps);
            vec2 baseDisp = -vec2(gx, gy) * 0.018;
            vec2 drift = vec2(0.0);
            if (!onEdge) {
                // Breath: radial from dip center, falls off with distance
                vec2  toNode    = nodeUV - dipCenter;
                float cDist     = length(toNode * vec2(1.0, 1.2));
                float breathEnv = exp(-cDist * cDist * 1.2);
                vec2  breathDir = cDist > 0.001 ? normalize(toNode) : vec2(0.0, 1.0);
                drift = breathDir * breath * breathEnv * 0.028;
                // Small per-node muscle fidget
                float seed  = float(mi * 7 + mj * 13);
                float freq  = 0.04 + hash(vec2(seed, seed*0.7)) * 0.025;
                float fphase = hash(vec2(seed*1.3, seed*0.4)) * 6.283;
                vec2  dir   = normalize(vec2(hash(vec2(seed, 1.0)) - 0.5,
                                             hash(vec2(seed, 2.0)) - 0.5));
                drift += dir * 0.002 * sin(iTime * freq + fphase);
            }
            float d2 = dot(uv - nodeUV, uv - nodeUV);
            float w  = exp(-d2 * 28.0);
            meshDisp += (baseDisp + drift) * w;
            totalW   += w;
        }
    }
    vec2 uvWarp = uv + (totalW > 0.0 ? meshDisp / totalW : vec2(0.0));

    // ── Age — continuous, no bands ────────────────────────────────────────
    float age = clamp(((1.0 - uv.y) * BASE_AGE + iTime * DRIFT_RATE) / (BASE_AGE + 1.0), 0.0, 1.0);
    float bleedRadius = age * BLEED_MAX;

    // ── Terminal ink ──────────────────────────────────────────────────────
    vec3 term    = texture(iChannel0, uvWarp).rgb;
    vec3 bgColor = iBackgroundColor.rgb;

    // Ink mask with 1px AA
    float inkMask = inkDetect(term, bgColor);
    float aaBlur = 0.0, aaW = 0.0;
    for (int i = -1; i <= 1; i++) {
        for (int j = -1; j <= 1; j++) {
            float w = 1.0 - length(vec2(i,j)) * 0.35;
            vec2 sUV = clamp(uvWarp + vec2(i,j) * px, 0.001, 0.999);
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
                vec2 sUV = clamp(uvWarp + vec2(i,j) * px * bleedRadius, 0.001, 0.999);
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

    // ── Melanin spots — freckles & moles as local melanin concentration ───
    // Same chromophore, just denser. Small radius → freckle, large → mole.
    // Cluster toward center (backs have more spots mid-torso than edges).
    // Deepen on fair skin over time; barely visible on deep melanin.
    #define SPOT_COUNT 90
    float spotAge  = clamp(iTime / 60.0, 0.0, 1.0);
    float spotFair = (1.0 - melanin) * (1.0 - melanin);  // quadratic: strong on fair only
    float spotMelanin = 0.0;
    for (int si = 0; si < SPOT_COUNT; si++) {
        vec2  s    = vec2(float(si) * 1.618, float(si) * 2.399);
        // Cluster toward center: map uniform random to center-weighted distribution
        vec2  raw  = vec2(hash(s), hash(s + 7.3));
        vec2  sUV  = 0.5 + (raw - 0.5) * vec2(0.78, 0.82);
        float rRaw = hash(s + 3.1);
        // Power law: most are tiny freckles, a few larger moles
        float fR   = mix(0.0018, 0.010, rRaw * rRaw * rRaw);
        float fDist= length((uvWarp - sUV) * vec2(aspect, 1.0));
        float spot = smoothstep(fR, fR * 0.15, fDist);
        // Larger spots darker, smaller ones lighter
        spotMelanin += spot * mix(0.06, 0.28, rRaw);
    }
    spotMelanin *= spotFair * spotAge;

    float localMelanin = clamp(melanin + spotMelanin, 0.0, 1.0);

    float sssStrength = mix(0.55, 0.08, melanin);
    float skinGrain   = mix(0.25, 0.60, melanin);

    // Skin gamut: melanin × warmth — use localMelanin so spots shift through gamut
    // Three-point mix: fair → mid → deep, fully continuous
    vec3 fairTone = mix(vec3(0.94,0.88,0.86), vec3(0.96,0.90,0.80), warmth);
    vec3 midTone  = mix(vec3(0.62,0.46,0.40), vec3(0.70,0.52,0.34), warmth);
    vec3 deepTone = mix(vec3(0.28,0.18,0.16), vec3(0.35,0.22,0.12), warmth);
    vec3 skinBase = mix(fairTone, mix(midTone, deepTone, clamp(localMelanin*2.0-1.0, 0.0,1.0)),
                        smoothstep(0.0, 1.0, localMelanin));

    skinBase += (fbm(uvWarp * 120.0) - 0.5) * 0.025 * skinGrain;

    // SSS — sum of 3 gaussians, each wider and redder
    // Narrow: surface detail. Mid: dermis blush. Wide: deep red scatter.
    // RGB weights per layer: red travels furthest, blue barely at all.
    vec3 sss = vec3(0.0);
    // Layer 1: narrow (2px), full spectrum
    vec3 n1 = vec3(0.0); float w1 = 0.0;
    for (int i = -2; i <= 2; i++) { for (int j = -2; j <= 2; j++) {
        float d2 = float(i*i+j*j); float w = exp(-d2 / 2.0);
        n1 += texture(iChannel0, clamp(uvWarp+vec2(i,j)*px*2.0,0.001,0.999)).rgb * w;
        w1 += w; } }
    sss += (n1/w1) * vec3(1.20, 0.80, 0.70) * 0.40;
    // Layer 2: mid (6px), red-shifted
    vec3 n2 = vec3(0.0); float w2 = 0.0;
    for (int i = -2; i <= 2; i++) { for (int j = -2; j <= 2; j++) {
        float d2 = float(i*i+j*j); float w = exp(-d2 / 4.0);
        n2 += texture(iChannel0, clamp(uvWarp+vec2(i,j)*px*6.0,0.001,0.999)).rgb * w;
        w2 += w; } }
    sss += (n2/w2) * vec3(1.50, 0.60, 0.40) * 0.35;
    // Layer 3: wide (14px), deep red only
    vec3 n3 = vec3(0.0); float w3 = 0.0;
    for (int i = -2; i <= 2; i++) { for (int j = -2; j <= 2; j++) {
        float d2 = float(i*i+j*j); float w = exp(-d2 / 6.0);
        n3 += texture(iChannel0, clamp(uvWarp+vec2(i,j)*px*14.0,0.001,0.999)).rgb * w;
        w3 += w; } }
    sss += (n3/w3) * vec3(1.80, 0.30, 0.20) * 0.25;

    skinBase += sss * sssStrength * 0.18 * (1.0 - bleedMask);

    // ── Normal map — direct central differences ───────────────────────────
    float eps = 0.014;
    float hC = skinHeight(uvWarp);
    float hR = skinHeight(uvWarp + vec2(eps, 0.0));
    float hU = skinHeight(uvWarp + vec2(0.0, eps));
    float normalScale = mix(0.12, 0.22, melanin);
    vec3 normal = normalize(vec3(
        (hC - hR) * normalScale * aspect,
        (hU - hC) * normalScale,
        1.0));

    // ── Ambient occlusion — horizon sampling from heightfield ─────────────
    // Sample 8 directions, check if neighbors are higher (occluding)
    float ao = 0.0;
    float aoRadius = 0.005;
    for (int i = 0; i < 8; i++) {
        float a = float(i) * 0.7854;
        vec2 dir = vec2(cos(a), sin(a)) * aoRadius;
        float hN = skinHeight(uvWarp + dir);
        ao += clamp((hN - hC) * 1.5, 0.0, 1.0);
    }
    ao = 1.0 - ao / 8.0 * 0.12;

    // ── Lighting — offscreen sun, 2-minute day/night cycle ────────────────
    float sunT    = iTime / 120.0 * 6.28318;  // full cycle in 120s
    float sunH    = sin(sunT);                 // elevation: >0 above horizon
    float dayness = smoothstep(-0.15, 0.25, sunH);

    // Sun moves left→right as it rises, right→left as it sets
    vec2  sunUV = vec2(0.5 + 0.7 * cos(sunT), 0.5 - 0.55 * sunH);

    // Golden hour: warm when near horizon, white-blue at noon
    float elevation   = clamp(sunH, 0.0, 1.0);
    float goldenHour  = smoothstep(0.35, 0.0, elevation) * dayness;
    vec3  noonColor   = vec3(1.00, 0.97, 0.92);              // bright neutral
    vec3  goldenColor = vec3(1.00, 0.72, 0.35);              // deep golden
    vec3  dawnColor   = vec3(1.00, 0.55, 0.30);              // redder at horizon
    vec3  dayColor    = mix(noonColor, mix(goldenColor, dawnColor, goldenHour), goldenHour);
    vec3  nightColor  = vec3(0.55, 0.65, 0.90);              // cool moonlight
    vec3  lightColor  = mix(nightColor, dayColor, dayness);

    float nightAmbient = AMBIENT * 0.45;
    float ambientLevel = mix(nightAmbient, AMBIENT, dayness);

    vec3 lightDir = normalize(vec3(sunUV - uv, LIGHT_HEIGHT));

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
    vec2  lampUV   = vec2(1.15, 0.45);          // off-screen right, mid-height
    vec3  lampDir  = normalize(vec3(lampUV - uv, LIGHT_HEIGHT * 0.6));
    vec3  lampHalf = normalize(lampDir + vec3(0,0,1));
    float lampDiff = (dot(normal, lampDir) * 0.5 + 0.5) * DIFFUSE_STR * 3.2;
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
    color *= ao;
    color = mix(color, mix(skinBase * inkColor * 1.6, inkColor, 0.55), inkMask);
    color *= (1.0 - inkMask * 0.05) * lightTint;

    // ── Focus dim ─────────────────────────────────────────────────────────
    float focusT   = clamp((iTime - iTimeFocus) * 1.5, 0.0, 1.0);
    float focusMix = iFocus == 1 ? focusT : 1.0 - focusT;
    float dim      = mix(0.6, 1.0, focusMix);
    float sat      = mix(0.4, 1.0, focusMix);
    color = mix(vec3(luma(color)), color, sat) * dim;

    // ── Encode into reserved pixels ───────────────────────────────────────
    if (fragCoord.x < 1.0 && fragCoord.y < 1.0) {
        fragColor = vec4(sunUV, 0.0, 1.0);       // (0,0): sun UV for compute
        return;
    }

    fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
