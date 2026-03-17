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
#define DIFFUSE_STR     0.38   // Lambert diffuse strength
#define SPECULAR_STR    0.10   // Blinn-Phong specular strength
#define SPECULAR_EXP    28.0   // specular shininess
#define AMBIENT         0.55   // ambient light floor
#define INK_MIN_LUMA    0.55   // minimum ink brightness on dark skin
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
    for (int i = 0; i < 3; i++) { v += a * noise(p); p *= 2.1; a *= 0.5; }
    return v;
}

// Wrinkles: fine circumferential creases from cumulative breathing strain.
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

// Valley fold: existing FBM valleys deepen when compressed by breathing.
// Skin has its own texture — valleys are where surface area goes on exhale.
// No separate wrinkle pattern: the creases emerge from the skin's own structure.
float valleyFold(vec2 p, float asp, float br, float cycleCount) {
    float h = skinHeight(p);
    // How far below average is this point? (FBM mean ≈ 0.48)
    float valley = max(0.0, 0.48 - h);
    // Strain ring: folds concentrate where displacement gradient is steepest
    vec2  fromC = p - vec2(0.5, 0.68);
    float d     = length(fromC * vec2(asp, 1.0));
    float strain = d * exp(-d * d * 1.5) * 2.2;
    // Transient: valleys fold deeper on exhale, smooth on inhale
    float compression = max(0.0, -br);
    // Permanent scoring: same valleys score over many cycles (log plateau)
    float scoring = clamp(log(1.0 + cycleCount * 0.35) / 3.2, 0.0, 1.0);
    return -valley * strain * (compression * 0.9 + scoring * 0.35);
}

// Ink detection: how different is this pixel from the background?
float inkDetect(vec3 s, vec3 bg) {
    return smoothstep(0.04, 0.22, max(abs(luma(s) - luma(bg)), length(s - bg) * 0.7));
}

// Distance from p to line segment [a,b]
float segDist(vec2 p, vec2 a, vec2 b) {
    vec2 ab = b - a, ap = p - a;
    return length(ap - ab * clamp(dot(ap, ab) / dot(ab, ab), 0.0, 1.0));
}

// Parametric vein curve — traces a smooth meander from start to end.
// Multi-scale (fractal) sinusoidal displacement perpendicular to path axis:
//   octave 1: slow lazy bend  (full amplitude)
//   octave 2: medium ripple   (half amplitude)
//   octave 3: fine wiggle     (quarter amplitude)
// 40 samples → smooth continuous river appearance.
// Parametric vein curve — continuous distance field via segment-to-segment tracing.
// Meander is 3-octave fractal sinusoid perpendicular to the path axis.
// Wider gaussian (sigma = w*2) compensates for no external blur pass —
// soft subsurface look without the cost of multiple veinField calls.
float veinCurve(vec2 q, vec2 s, vec2 e, float amp, float freq, float w) {
    vec2 along = e - s;
    vec2 perp  = vec2(-along.y, along.x) / max(length(along), 0.001);
    float minD = 1e9;
    vec2 prev  = s;
    for (int i = 1; i < 24; i++) {
        float t   = float(i) / 23.0;
        float d   = amp      * sin(t * freq * 6.28318)
                  + amp*0.5  * sin(t * freq * 6.28318 * 2.0 + 1.7)
                  + amp*0.25 * sin(t * freq * 6.28318 * 4.0 + 3.1);
        vec2 cur  = s + along * t + perp * d;
        minD = min(minD, segDist(q, prev, cur));
        prev = cur;
    }
    return exp(-minD * minD / (w * w * 8.0));
}
float veinBranch(vec2 q, vec2 s, vec2 e, float amp, float freq, float w) {
    vec2 along = e - s;
    vec2 perp  = vec2(-along.y, along.x) / max(length(along), 0.001);
    float minD = 1e9;
    vec2 prev  = s;
    for (int i = 1; i < 12; i++) {
        float t   = float(i) / 11.0;
        float d   = amp      * sin(t * freq * 6.28318)
                  + amp*0.5  * sin(t * freq * 6.28318 * 2.0 + 2.3)
                  + amp*0.25 * sin(t * freq * 6.28318 * 4.0 + 0.8);
        vec2 cur  = s + along * t + perp * d;
        minD = min(minD, segDist(q, prev, cur));
        prev = cur;
    }
    return exp(-minD * minD / (w * w * 8.0));
}

// Vein network in aspect-corrected UV space.
float veinField(vec2 p, float asp) {
    vec2 q = vec2(p.x * asp, p.y);
    #define A(x) ((x)*asp)   // aspect-correct x
    float v = 0.0;

    // max() instead of += so overlapping veins don't compound
    #define VC(s,e,a,f,w) v = max(v, veinCurve(q,s,e,a,f,w))
    #define VB(s,e,a,f,w) v = max(v, veinBranch(q,s,e,a,f,w))

    // PRIMARY diagonal trunk — crosses right-to-left across the back
    VC(vec2(A(0.76),0.88), vec2(A(0.26),0.10), 0.055, 2.1, 0.013);

    // SECONDARY left — feeds in from below-left
    VC(vec2(A(0.22),0.85), vec2(A(0.40),0.35), 0.038, 2.8, 0.010);

    // SECONDARY right — different meander character
    VC(vec2(A(0.80),0.80), vec2(A(0.64),0.22), 0.042, 1.6, 0.010);

    // BRANCHES
    VB(vec2(A(0.58),0.55), vec2(A(0.74),0.62), 0.022, 2.2, 0.006);
    VB(vec2(A(0.48),0.42), vec2(A(0.31),0.50), 0.018, 2.5, 0.006);
    VB(vec2(A(0.66),0.70), vec2(A(0.84),0.65), 0.016, 2.8, 0.005);
    VB(vec2(A(0.30),0.65), vec2(A(0.14),0.60), 0.015, 2.6, 0.004);

    #undef VC
    #undef VB

    #undef A
    return clamp(v, 0.0, 1.0);
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
    vec2 rawWarp = totalW > 0.0 ? meshDisp / totalW : vec2(0.0);
    vec2 uvWarp  = uv + rawWarp;

    // ── Age — continuous, no bands ────────────────────────────────────────
    float age = clamp(((1.0 - uv.y) * BASE_AGE + iTime * DRIFT_RATE) / (BASE_AGE + 1.0), 0.0, 1.0);
    float bleedRadius = age * BLEED_MAX;

    // ── Terminal ink ──────────────────────────────────────────────────────
    vec3 bgColor = iBackgroundColor.rgb;

    // 2×2 rotated-grid supersample to kill warp moiré
    vec2 ssOff = px * 0.375;
    vec3 t0 = texture(iChannel0, uvWarp + vec2(-ssOff.x, ssOff.y)).rgb;
    vec3 t1 = texture(iChannel0, uvWarp + vec2( ssOff.x, ssOff.y)).rgb;
    vec3 t2 = texture(iChannel0, uvWarp + vec2(-ssOff.x,-ssOff.y)).rgb;
    vec3 t3 = texture(iChannel0, uvWarp + vec2( ssOff.x,-ssOff.y)).rgb;
    vec3 term = (t0 + t1 + t2 + t3) * 0.25;

    // Ink mask from supersampled detection
    float inkMask = (inkDetect(t0, bgColor) + inkDetect(t1, bgColor)
                   + inkDetect(t2, bgColor) + inkDetect(t3, bgColor)) * 0.25;

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
    // Blue shift: rotate hue toward cool/blue while preserving luma.
    // Mix toward a blue-tinted version, then rescale to original brightness.
    float shiftAmt = blueShift * clamp(inkMask + fringe, 0.0, 1.0) * mix(1.0, 0.4, 1.0 - luma(bgColor));
    vec3 termShifted = term * vec3(0.65, 0.88, 1.20);
    float termLuma   = max(luma(term), 0.001);
    termShifted *= termLuma / max(luma(termShifted), 0.001);  // luma-preserve
    vec3 inkColor = clamp(mix(term, termShifted, shiftAmt), 0.0, 1.0);

    // ── Skin: continuous chromophore model ────────────────────────────────
    float bgLuma  = luma(bgColor);
    float melanin = 1.0 - bgLuma;
    float warmth  = clamp((bgColor.r - bgColor.b) * 2.0 + 0.5, 0.0, 1.0);

    // Tan disabled — TODO: revisit compute approach to avoid visible disc artifact

    // ── Melanin spots — freckles & moles as local melanin concentration ───
    // Same chromophore, just denser. Small radius → freckle, large → mole.
    // Cluster toward center (backs have more spots mid-torso than edges).
    // Deepen on fair skin over time; barely visible on deep melanin.
    #define SPOT_COUNT 40
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

    float sssStrength = mix(0.35, 0.08, melanin);
    float skinGrain   = mix(0.25, 0.60, melanin);

    // Skin gamut: melanin × warmth — use localMelanin so spots shift through gamut
    // Three-point mix: fair → mid → deep, fully continuous
    vec3 fairTone = mix(vec3(0.93,0.88,0.865), vec3(0.94,0.89,0.855), warmth);
    vec3 midTone  = mix(vec3(0.62,0.46,0.40), vec3(0.70,0.52,0.34), warmth);
    vec3 deepTone = mix(vec3(0.16,0.10,0.09), vec3(0.20,0.13,0.08), warmth);
    vec3 skinBase = mix(fairTone, mix(midTone, deepTone, clamp(localMelanin*2.0-1.0, 0.0,1.0)),
                        smoothstep(0.0, 1.0, localMelanin));

    // Anchor skin brightness to actual background — dark bg stays dark
    skinBase *= mix(1.0, luma(skinBase) > 0.001 ? bgLuma / luma(skinBase) : 1.0, 0.4);
    skinBase += (fbm(uvWarp * 120.0) - 0.5) * 0.025 * skinGrain;

    // ── Veins — subsurface branching paths, scatter through SSS ──────────
    // Applied before SSS so the three gaussian passes blur and soften them —
    // they read as something seen through translucent tissue, not drawn lines.
    // Visible only on fair skin: (1-melanin)². Move with mesh via uvWarp.
    float veinFair = (1.0 - melanin) * (1.0 - melanin);
    // Slight organic warp so paths curve naturally rather than staying rigid
    float vMask = veinField(uvWarp, aspect) * veinFair * (1.0 - inkMask * 0.85);
    // Desaturated cool shadow — visible but not vivid
    skinBase += vMask * vec3(-0.018, -0.013, 0.034);

    // SSS — 4-tap cross pattern per layer (12 total, down from 75)
    // Cardinal directions only, ink-excluded.
    vec3 sss = vec3(0.0);
    for (int layer = 0; layer < 3; layer++) {
        float radius = (layer == 0) ? 2.0 : (layer == 1) ? 6.0 : 14.0;
        vec3 tint = (layer == 0) ? vec3(1.20, 0.80, 0.70) * 0.40
                  : (layer == 1) ? vec3(1.50, 0.60, 0.40) * 0.35
                  :                vec3(1.80, 0.30, 0.20) * 0.25;
        vec3 acc = vec3(0.0);
        for (int t = 0; t < 4; t++) {
            vec2 d = (t==0) ? vec2(1,0) : (t==1) ? vec2(-1,0) : (t==2) ? vec2(0,1) : vec2(0,-1);
            vec2 sUV = clamp(uvWarp + d * px * radius, 0.001, 0.999);
            vec3 s = texture(iChannel0, sUV).rgb;
            acc += mix(s, bgColor, inkDetect(s, bgColor));
        }
        sss += (acc * 0.25) * tint;
    }
    skinBase += sss * sssStrength * 0.18 * (1.0 - inkMask);

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

    // ── Ambient occlusion — 4 cardinal directions ─────────────────────────
    float aoR = 0.005;
    float ao = clamp((skinHeight(uvWarp+vec2(aoR,0.0)) - hC)
                   + (skinHeight(uvWarp-vec2(aoR,0.0)) - hC)
                   + (skinHeight(uvWarp+vec2(0.0,aoR)) - hC)
                   + (skinHeight(uvWarp-vec2(0.0,aoR)) - hC), 0.0, 1.0);
    ao = 1.0 - ao * 0.12;

    // ── Lighting — window light from top-left ──────────────────────────────
    vec2  sunUV = vec2(-0.3, -0.3);  // off-screen top-left (window)
    vec3 lightDir = normalize(vec3(sunUV - uv, LIGHT_HEIGHT * 2.5));

    float diffuse  = (dot(normal, lightDir) * 0.5 + 0.5) * DIFFUSE_STR;
    vec3  halfDir  = normalize(lightDir + vec3(0,0,1));
    float specular = pow(max(dot(normal, halfDir), 0.0), SPECULAR_EXP)
                   * SPECULAR_STR * mix(1.0, 0.3, melanin)
                   * (1.0 - inkMask * 0.85);

    float lighting = clamp(AMBIENT + diffuse + specular, 0.0, 1.15);
    vec3  lightTint = vec3(1.0, 0.99, 0.95) * lighting;  // warm window light

    // ── Composite ─────────────────────────────────────────────────────────
    // Bleed halo: ink color seeps subtly into surrounding skin
    vec3 bleedTint = mix(skinBase, inkColor, 0.15);  // skin tinted toward ink
    vec3 color = mix(skinBase, bleedTint, fringe * 0.5);
    color *= ao;
    // Ink embed: fair skin = ink tinted by dermis; deep skin = ink reads directly.
    // Also boost ink brightness on deep skin so mid-tone colors don't sink into substrate.
    float inkEmbed  = mix(0.55, 1.0, melanin);  // dark skin: pure ink, no multiply blend
    // Lift dark ink toward readable brightness on dark skin
    float inkLuma = luma(inkColor);
    float minLuma = melanin * INK_MIN_LUMA;
    float lift = max(0.0, minLuma - inkLuma) / max(inkLuma, 0.01);
    vec3  inkLifted = inkColor * (1.0 + lift);
    vec3  inkBoosted = mix(inkLifted, inkLifted + (inkLifted - skinBase) * 0.5, melanin);
    // Age fade: old ink ghosts back toward skin (top of screen = older)
    float fadeAmount = mix(0.28, 0.05, melanin);  // fair skin fades more, dark skin holds ink
    float inkFade = 1.0 - smoothstep(0.18, 0.92, 1.0 - uv.y) * fadeAmount;
    color = mix(color, mix(skinBase * inkBoosted * 1.6, inkBoosted, inkEmbed), inkMask * inkFade);
    // Mid-tone ink glows harder — saturated colors pop in the dermis
    float midPop = 1.0 + smoothstep(0.15, 0.4, inkLuma) * smoothstep(0.7, 0.4, inkLuma) * 1.5;
    // Ink luminosity — letters glow faintly on dark skin, as if lit from within
    float skinProximity = 1.0 - clamp(length(inkColor - skinBase) * 3.0, 0.0, 1.0);
    float inkGlow = inkMask * melanin * mix(0.2, 0.7, skinProximity) * midPop;
    color += inkBoosted * inkGlow;
    // Ink light sinks into surrounding skin through the bleed fringe
    float skinGlow = fringe * melanin * 0.35 * midPop;
    color += inkBoosted * skinGlow;
    // Light tint applies to skin; ink pixels get only a gentle tint so colors stay legible
    // Dark skin: ink resists both color tint and brightness variation from lighting
    float tintResist = inkMask * mix(0.5, 0.9, melanin);
    vec3 inkLightTint = mix(lightTint, vec3(luma(lightTint) * 0.5 + 0.5), tintResist);
    float lightResist = inkMask * melanin * 0.35;
    vec3 flatLight = mix(inkLightTint, vec3(1.0), lightResist);
    color *= (1.0 - inkMask * 0.05) * flatLight;

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
