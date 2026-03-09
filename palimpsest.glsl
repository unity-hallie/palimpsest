// The Palimpsest v10 — physarum memory, squash & stretch, identity, focus

// ====== TUNE THESE ======
#define GLITTER_STRENGTH    0.75   // sparkle brightness
#define GLITTER_SPEED       0.5    // twinkle cycles/sec
#define GLITTER_CELL        14.0   // px between sparkle anchor points
#define SOAK_RADIUS         3.3    // px — ink absorption halo around strokes
#define SOAK_STRENGTH       0.22   // how strong the absorbed zone gets
#define GRAIN_STRENGTH      0.012
#define INK_BLEED           0.9
#define WARMTH_STRENGTH     0.025
#define VIGNETTE_STRENGTH   0.000
// Physarum ink memory (iChannel1 feedback)
#define PERSISTENCE         0.93
#define VEIN_ATTRACTION     0.6
#define VEIN_SHARPNESS      3.0
#define THIN_DECAY          0.010
#define BLEED_RADIUS        3.5
#define BLEED_AMOUNT        0.42
#define BLEED_NOISE         0.4
// Temporal halo (grows over session lifetime)
#define HALO_MATURITY_SECS  600.0
#define HALO_MIN            0.08
#define HALO_MAX            0.35
#define HALO_RADIUS_MIN     3.0
#define HALO_RADIUS_MAX     14.0
// Vein safety
#define VEIN_DARKNESS_CAP   0.82
#define TEXT_CLEAR_RADIUS   0.1
// Squash & stretch on keystrokes
#define STRETCH_AMOUNT      0.25    // vertical stretch magnitude
#define STRETCH_RADIUS      0.5     // influence in cell-heights
#define STRETCH_DECAY       9.0     // higher = snappier spring
// =========================

// Compile-time constants — named rather than scattered magic numbers
const float TAU        = 6.28318530718;   // 2π
const float TAU_3      = 2.09439510239;   // 2π/3  (hue wheel step)
const float TAU2_3     = 4.18879020479;   // 4π/3
const float ISQRT2     = 0.70710678118;   // 1/√2  (diagonal halo offsets)
const float HASH_SCALE = 43758.5453;
const vec2  HASH_A     = vec2(127.1,  311.7);
const vec2  HASH_B     = vec2( 12.9898, 78.233);
const vec3  LUMA       = vec3(0.299, 0.587, 0.114);  // perceptual luminance
const vec3  RCP3       = vec3(0.33333333);            // uniform RGB average

float hash21(vec2 p) { return fract(sin(dot(p, HASH_A)) * HASH_SCALE); }

// inkness: 0 = paper, 1 = fully saturated ink
float inkness(vec3 col) {
    float d  = 1.0 - dot(col,              RCP3);
    float pd = 1.0 - dot(iBackgroundColor, RCP3);
    return clamp((d - pd) / (1.0 - pd + 0.001), 0.0, 1.0);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2  uv    = fragCoord / iResolution.xy;
    vec2  px    = 1.0 / iResolution.xy;
    float t     = iTime * 0.08;
    vec3  paper = iBackgroundColor;

    // --- Session age ---
    float age      = clamp(iTime / HALO_MATURITY_SECS, 0.0, 1.0);
    age            = age * age * (3.0 - 2.0 * age);          // smoothstep
    float halo_str = mix(HALO_MIN, HALO_MAX, age);
    float halo_r   = mix(HALO_RADIUS_MIN, HALO_RADIUS_MAX, age);

    // --- Terminal personality ---
    // Seed from screen content: terminals in different dirs hash differently.
    // Stored at screen center — far from all corners, corner stain has minimal reach there.
    vec2  seedUV    = vec2(0.5, 0.5);
    float seedDelta = texture(iChannel1, seedUV).r - paper.r;
    float isFirst   = step(abs(seedDelta), 0.003);
    float c0 = dot(texture(iChannel0, vec2(0.08, 0.5)).rgb, RCP3);
    float c1 = dot(texture(iChannel0, vec2(0.22, 0.5)).rgb, RCP3);
    float c2 = dot(texture(iChannel0, vec2(0.38, 0.5)).rgb, RCP3);
    float c3 = dot(texture(iChannel0, vec2(0.52, 0.5)).rgb, RCP3);
    float paperLum    = dot(paper, RCP3);
    float hasContent  = step(0.01, abs(c0 + c1 + c2 + c3 - 4.0 * paperLum));
    float contentHash = fract(sin(c0 * HASH_A.x + c1 * HASH_A.y
                                + c2 * 74.7      + c3 * 269.5
                                + iResolution.x  * 13.7) * HASH_SCALE);
    float resSeed     = fract(sin(dot(iResolution.xy, HASH_A)) * HASH_SCALE);
    float freshSeed   = mix(resSeed, contentHash, hasContent);
    float seed        = mix(clamp(seedDelta / 0.055, 0.0, 1.0), freshSeed, isFirst);
    float seed2       = fract(seed * 7.31 + 0.37);
    float hueAngle    = seed * TAU;
    vec3  personality = vec3(cos(hueAngle),
                             cos(hueAngle + TAU_3),
                             cos(hueAngle + TAU2_3)) * 0.026;
    vec2  corner      = vec2(step(0.5, seed2)              * 2.0 - 1.0,
                             step(0.5, fract(seed2 * 3.7)) * 2.0 - 1.0);

    // --- Squash & stretch ---
    // iTimeCursorChange: absolute time of last cursor move.
    // Guard: only active once cursor has actually been set (iTimeCursorChange > 0).
    // Cell size: use cursor dimensions if available, fallback to reasonable defaults.
    float timeSinceType = iTime - iTimeCursorChange;
    float hasCursor     = step(0.001, iTimeCursorChange);
    float spring        = exp(-timeSinceType * STRETCH_DECAY) * STRETCH_AMOUNT * hasCursor;

    vec2  cellSizePx = max(iCurrentCursor.zw, vec2(8.0, 16.0));   // pixels, with fallback
    vec2  glyphPx    = iPreviousCursor.xy + cellSizePx * 0.5;      // center of typed cell
    vec2  glyphUV    = glyphPx / iResolution.xy;

    // Influence: falls off over STRETCH_RADIUS cell-heights from typed position
    float dist_cells = length((fragCoord - glyphPx) / cellSizePx.y);
    float sf         = spring * smoothstep(STRETCH_RADIUS, 0.0, dist_cells);

    // Scale UV around glyph center:
    //   y scale < 1 → sample narrower vertical range → content appears taller
    //   x scale > 1 → sample wider horizontal range → content appears narrower
    vec2  scale    = vec2(1.0 + sf * 0.25, 1.0 - sf * 0.45);
    vec2  sampleUV = clamp(glyphUV + (uv - glyphUV) * scale, vec2(0.0), vec2(1.0));

    // --- Terminal sample ---
    vec4 terminal = texture(iChannel0, sampleUV);

    // --- Physarum: ink memory from iChannel1 ---
    vec3  prev    = texture(iChannel1, uv).rgb;
    float prevInk = inkness(prev);

    vec3  bleedAccum  = vec3(0.0);
    float bleedWeight = 0.0;
    const float GOLDEN_ANGLE = 2.39996323;
    for (int i = 0; i < 16; i++) {
        float fi      = float(i);
        float angle   = fi * GOLDEN_ANGLE + fract(sin(dot(fragCoord * 0.05 + fi * 3.7 + iTime * 0.001,
                                      HASH_A)) * HASH_SCALE) * 0.5;
        float r       = sqrt((fi + 0.5) / 16.0);
        vec2  dir     = vec2(cos(angle), sin(angle));
        float reach   = BLEED_RADIUS * (0.7 + 0.3 * r) * (0.7 + 0.6 * r * BLEED_NOISE);
        vec3  samp    = texture(iChannel1, uv + dir * reach * px).rgb;
        float sampInk = inkness(samp);
        float w       = 1.0 + pow(sampInk + 0.01, VEIN_SHARPNESS) * VEIN_ATTRACTION * 10.0;
        bleedAccum  += samp * w;
        bleedWeight += w;
    }
    vec3 bleedColor = bleedAccum / bleedWeight;

    float edgeZone  = 4.0 * prevInk * (1.0 - prevInk);
    vec3  withBleed = mix(prev, bleedColor, BLEED_AMOUNT * (0.3 + 0.7 * edgeZone));
    float thinness  = 1.0 - smoothstep(0.0, 0.3, inkness(withBleed));
    withBleed       = mix(withBleed, paper, THIN_DECAY * thinness);

    // Clear zone: suppress accumulation near actual text, before persistence
    float r       = TEXT_CLEAR_RADIUS * px.x;
    float nearInk = inkness(texture(iChannel0, uv).rgb);
    nearInk = max(nearInk, inkness(texture(iChannel0, uv + vec2( r,  0.0)).rgb));
    nearInk = max(nearInk, inkness(texture(iChannel0, uv + vec2(-r,  0.0)).rgb));
    nearInk = max(nearInk, inkness(texture(iChannel0, uv + vec2( 0.0,  r)).rgb));
    nearInk = max(nearInk, inkness(texture(iChannel0, uv + vec2( 0.0, -r)).rgb));
    withBleed = mix(withBleed, paper, smoothstep(0.08, 0.4, nearInk));

    vec3  trail    = mix(withBleed, paper, 1.0 - PERSISTENCE);
    float trailInk = inkness(trail);
    trail = paper + (trail - paper) * min(1.0, VEIN_DARKNESS_CAP / max(trailInk, 0.001));
    // Rose-violet blush on vein midtones — edges pick up color, not just neutral dark
    trail += vec3(0.016, -0.004, 0.012) * trailInk * (1.0 - trailInk) * 3.5;
    // Freeze trail when unfocused — stops physarum noise from flickering the corner stain
    trail = mix(prev, trail, float(iFocus));

    // --- Letterform softening (golden-angle disc) ---
    vec4  blur = terminal * 0.45;
    float blurW = 0.45;
    for (int i = 0; i < 8; i++) {
        float fi = float(i);
        float r  = sqrt((fi + 0.5) / 8.0);
        float a  = fi * GOLDEN_ANGLE;
        vec2 off = vec2(cos(a), sin(a)) * r * px;
        float w  = 1.0 - r * 0.35;  // center-weighted
        blur  += texture(iChannel0, sampleUV + off) * w;
        blurW += w;
    }
    blur /= blurW;
    float inkDensity = 1.0 - dot(terminal.rgb, LUMA);
    vec4  inked      = mix(terminal, blur, inkDensity * INK_BLEED);

    // --- Temporal halo ---
    float bpx = halo_r * px.x, bpy = halo_r * px.y;
    float halo = 0.0;
    halo += 1.0 - dot(texture(iChannel0, uv + vec2( bpx,         0.0)).rgb, LUMA);
    halo += 1.0 - dot(texture(iChannel0, uv + vec2(-bpx,         0.0)).rgb, LUMA);
    halo += 1.0 - dot(texture(iChannel0, uv + vec2( 0.0,         bpy)).rgb, LUMA);
    halo += 1.0 - dot(texture(iChannel0, uv + vec2( 0.0,        -bpy)).rgb, LUMA);
    halo += 1.0 - dot(texture(iChannel0, uv + vec2( bpx*ISQRT2,  bpy*ISQRT2)).rgb, LUMA);
    halo += 1.0 - dot(texture(iChannel0, uv + vec2(-bpx*ISQRT2,  bpy*ISQRT2)).rgb, LUMA);
    halo += 1.0 - dot(texture(iChannel0, uv + vec2( bpx*ISQRT2, -bpy*ISQRT2)).rgb, LUMA);
    halo += 1.0 - dot(texture(iChannel0, uv + vec2(-bpx*ISQRT2, -bpy*ISQRT2)).rgb, LUMA);
    halo /= 8.0;
    float seep = halo * halo_str * (0.92 + 0.08 * sin(t * 2.0 + uv.x * 5.0 + uv.y * 3.0));

    // --- Composite: trail as substrate, text fully on top ---
    float textMask = smoothstep(0.05, 0.35, terminal.a);
    float edgeMask = smoothstep(0.0,  0.05, terminal.a) * (1.0 - textMask);

    vec3 color = trail;
    color = mix(color, mix(trail, inked.rgb, 0.5), edgeMask);
    color = mix(color, inked.rgb, textMask);

    // Ink absorption: paper tints toward deep purple around strokes as ink soaks in
    float sR    = SOAK_RADIUS * px.x;
    float soak  = inkDensity;
    soak = max(soak, inkness(texture(iChannel0, uv + vec2( sR,  0.0)).rgb));
    soak = max(soak, inkness(texture(iChannel0, uv + vec2(-sR,  0.0)).rgb));
    soak = max(soak, inkness(texture(iChannel0, uv + vec2( 0.0,  sR)).rgb));
    soak = max(soak, inkness(texture(iChannel0, uv + vec2( 0.0, -sR)).rgb));
    vec3  soakCol    = vec3(0.16, 0.06, 0.26);  // deep purple floor — never goes to black
    float soakFactor = smoothstep(0.15, 0.55, soak) * (1.0 - inkDensity) * SOAK_STRENGTH;
    color = mix(color, soakCol, soakFactor);

    // Halo seep — ink darkens paper near dense text
    color -= seep * vec3(0.55, 0.50, 0.90);

    // Agar warmth — deepens with age
    float stain     = pow(sin(uv.x * 1.5 + uv.y + t * 0.8) * 0.5 + 0.5, 2.0);
    float warmthAge = mix(0.6, 1.0, age);
    color += vec3(1.0, 0.42, -0.15) * stain * WARMTH_STRENGTH * warmthAge;

    // Paper grain
    float fiber = sin(fragCoord.x * 0.3 + fragCoord.y * 0.7 + t * 0.4) * 0.5
                + sin(fragCoord.x * 0.7 - fragCoord.y * 0.4 + t * 0.3) * 0.3
                + sin((fragCoord.x + fragCoord.y) * 0.15   + t * 0.2) * 0.4;
    fiber *= GRAIN_STRENGTH;
    float fine = (fract(sin(dot(floor(fragCoord * 1.5), HASH_B)) * HASH_SCALE) - 0.5) * 0.0075;
    color += fiber + fine;

    // Glitter ink — iridescent flecks twinkling within text strokes
    // Distance in pixels so radius is physical regardless of GLITTER_CELL size.
    // Gated by inkDensity (text darkness) rather than terminal.a which may be unreliable.
    vec2  gcell    = floor(fragCoord / GLITTER_CELL);
    vec2  gcellPx  = fract(fragCoord / GLITTER_CELL) * GLITTER_CELL;
    vec2  gpos     = vec2(hash21(gcell + 3.7), hash21(gcell + 11.3)) * GLITTER_CELL;
    float gspot    = smoothstep(4.5, 0.0, length(gcellPx - gpos));  // 4.5px physical radius
    float gphase   = hash21(gcell + 57.1) * TAU;
    float gspeed   = GLITTER_SPEED * (0.7 + 0.6 * hash21(gcell + 83.9));
    float gtwinkle = pow(max(0.0, sin(iTime * gspeed + gphase)), 2.0);
    float ghue     = hash21(gcell + 71.9) * TAU;
    // Purple-violet-magenta range only (hue 0.68–0.90 normalized)
    float ghueN   = 0.68 + hash21(gcell + 71.9) * 0.22;
    vec3  gcol    = clamp(abs(fract(ghueN + vec3(0.0, 1.0/3.0, 2.0/3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
    // Gate by raw terminal (iChannel0) — stable, doesn't feed back into physarum
    vec2  gposUV = (gcell * GLITTER_CELL + gpos) / iResolution.xy;
    float gink   = 1.0 - dot(texture(iChannel0, gposUV).rgb, LUMA);
    color += gspot * gtwinkle * gcol * smoothstep(0.05, 0.3, gink) * GLITTER_STRENGTH * float(iFocus);

    // Vignette
    color *= 1.0 - VIGNETTE_STRENGTH * pow(length((uv - 0.5) * vec2(1.2, 0.8)), 2.0);

    // Focus: dim + desaturate when unfocused, smooth transition
    float timeSinceFocus = iTime - iTimeFocus;
    float focusT         = clamp(timeSinceFocus * 3.0, 0.0, 1.0);
    float focusFactor    = mix(1.0 - float(iFocus), float(iFocus), focusT);
    float lum            = dot(color, LUMA);
    color = mix(mix(vec3(lum), color, 0.65), color, focusFactor);
    color *= mix(0.85, 1.0, focusFactor);

    // Corner character: applied after focus so it sits on top of the grey overlay cleanly
    float cornerProx = 1.0 - smoothstep(0.0, 1.6, length(uv * 2.0 - 1.0 - corner));
    color *= 1.0 - cornerProx * age * 0.18;
    color += personality * cornerProx * age;
    color += personality * (1.0 - textMask) * 0.75;

    // Store identity seed at screen center pixel
    float isSeedPx = step(abs(fragCoord.x - iResolution.x * 0.5), 0.5)
                   * step(abs(fragCoord.y - iResolution.y * 0.5), 0.5);
    color = mix(color, vec3(paper.r + seed * 0.055, paper.gb), isSeedPx);

    fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
