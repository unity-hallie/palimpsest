// CORRODING METAL — tectonic multi-layer, seasons
//
// State (feedback RGBA — survives round-trip):
//   R = copper concentration     [0,1] → verdigris tarnish
//   G = iron concentration       [0,1] → rust tarnish
//   B = crust thickness          [0,1]
//   A = heat / flow energy       [0,1]
//   silver = clamp(1-R-G, 0,1)   → sulfide black-gold tarnish
//
// MULTIPLE TECTONIC PLATES: the surface is divided into ~5 plate regions
// (via noise-based Voronoi). Each plate drifts in its own direction/speed.
// At plate boundaries, shear creates fractures and upwellings.
//
// MANTLE SEASONS: a slow sinusoidal cycle (period ~7 min) modulates heat
// energy. Hot season = eruptions, churning, fresh tarnish. Cold season =
// crust solidifies, colors deepen and darken.
//
// THREE MANTLE LAYERS at different depths, each with independent convection.
// Projected onto 2D with parallax: deep layers appear offset from surface.

// ── Tuning (from previewer session) ──────────────────────────────────────────

const float ADVECT_SPEED  = 1.55;
const float BUOYANCY      = 0.90;
const float TEXT_STIR     = 12.0;
const float TEXT_BOOST    = 3.0;
const float ALLOY_DIFFUSE = 0.09;
const float TEXT_DEPOSIT  = 0.09;
const float CRUST_GROW    = 0.040;
const float CRUST_SCOUR   = 0.30;
const float TEXT_BURN     = 0.205;
const float FLOW_DECAY    = 0.88;
const float ERUPT_SEEP    = 0.28;
const float ERUPT_SCOUR   = 0.20;
const float GRAIN_SCALE   = 5.5;
const float GRAIN_WARP    = 0.42;

// Eruption — season-modulated
const float ERUPT_THRESH_HOT  = 0.11;   // summer: erupts easily
const float ERUPT_THRESH_COLD = 0.58;   // winter: almost nothing breaks through
const float ERUPT_STR_HOT     = 2.00;
const float ERUPT_STR_COLD    = 0.40;

// Season period in seconds
const float SEASON_PERIOD = 430.0;    // ~7 min full cycle

// ── Spherical projection ──────────────────────────────────────────────────────
// The terminal viewport maps to the front face of a sphere.
// We compute (lat, lon) and use them to drive:
//  • local baseline heat (equator hot, poles cold)
//  • seasonal tilt (axial obliquity oscillates → N/S hemisphere seasons)
//  • plate drift bias (equatorial plates move E/W, polar plates circulate)
const float SPHERE_RADIUS = 1.30;    // bulge factor — 1.0 = hemisphere
const float AXIAL_TILT    = 0.42;    // radians of obliquity (~24°, Earth-like)

// Mantle layer depths (parallax offset scale)
const float DEPTH_SHALLOW = 0.008;
const float DEPTH_MID     = 0.022;
const float DEPTH_DEEP    = 0.048;

// Display
const float MANTLE_BRIGHT  = 1.20;
const float MANTLE_HOT     = 0.58;
const float SURFACE_DIM    = 0.75;
const float SHADOW_STR     = 0.68;
const float TEXT_MIN_LUMA  = 0.45;
const float VIGNETTE       = 0.28;

// ── Helpers ───────────────────────────────────────────────────────────────────

float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

float hash2(vec2 p) {
    p = fract(p * vec2(127.1, 311.7));
    p += dot(p, p.yx + 19.19);
    return fract(p.x * p.y);
}
float noise2(vec2 p) {
    vec2 i = floor(p); vec2 f = fract(p);
    f = f*f*(3.0-2.0*f);
    return mix(mix(hash2(i),           hash2(i+vec2(1,0)), f.x),
               mix(hash2(i+vec2(0,1)), hash2(i+vec2(1,1)), f.x), f.y);
}
float fnoise(vec2 p) {
    return noise2(p)*0.55 + noise2(p*2.1+vec2(5.2,1.3))*0.30
         + noise2(p*4.3+vec2(2.7,8.1))*0.15;
}
float damascus(vec2 uv, float warp) {
    vec2 p = uv * GRAIN_SCALE;
    p.x += sin(p.y*3.7 + warp*6.28*GRAIN_WARP)*0.45;
    p.y += cos(p.x*2.9 + warp*4.71*GRAIN_WARP)*0.30;
    float g = sin(p.x*6.283)*0.5+0.5;
    g = mix(g, sin(p.x*12.57+p.y*3.1)*0.5+0.5, 0.3);
    return smoothstep(0.35, 0.65, g);
}

// ── Plate tectonics ───────────────────────────────────────────────────────────
// Noise-based Voronoi: ~5 plate cells, each with its own drift velocity.
// Returns (vel.xy, boundary_strength) — boundary_strength [0,1] is high near
// plate edges (used to create shear fractures and upwellings).
vec3 plateDrift(vec2 uv, float t) {
    // Plate "seed" positions (static, in [0,1]^2)
    // We use 5 fixed seeds; each plate slowly rotates its direction over time.
    const vec2 S0 = vec2(0.18, 0.25);
    const vec2 S1 = vec2(0.72, 0.15);
    const vec2 S2 = vec2(0.45, 0.55);
    const vec2 S3 = vec2(0.15, 0.78);
    const vec2 S4 = vec2(0.80, 0.72);

    // Per-plate drift directions — very slowly rotating
    // Each plate has a distinct "base angle" so they diverge
    float a0 = 0.80  + sin(t*0.00041)*0.55;   // NW-ish drift
    float a1 = 2.50  + cos(t*0.00037)*0.60;   // ESE drift
    float a2 = 4.10  + sin(t*0.00029)*0.50;   // SSW drift
    float a3 = 1.10  + cos(t*0.00053)*0.45;   // NNE drift
    float a4 = 3.30  + sin(t*0.00047)*0.40;   // WSW drift

    float sp0 = 0.55, sp1 = 0.42, sp2 = 0.38, sp3 = 0.61, sp4 = 0.47;

    vec2 v0 = vec2(cos(a0), sin(a0)) * sp0;
    vec2 v1 = vec2(cos(a1), sin(a1)) * sp1;
    vec2 v2 = vec2(cos(a2), sin(a2)) * sp2;
    vec2 v3 = vec2(cos(a3), sin(a3)) * sp3;
    vec2 v4 = vec2(cos(a4), sin(a4)) * sp4;

    // Find the two closest plates (Voronoi)
    float d0 = length(uv - S0);
    float d1 = length(uv - S1);
    float d2 = length(uv - S2);
    float d3 = length(uv - S3);
    float d4 = length(uv - S4);

    // Sort to get closest and second-closest
    float minD  = min(min(min(d0, d1), min(d2, d3)), d4);
    float minD2 = 1e9;
    vec2 driftVel = vec2(0.0);

    // Interpolate velocity by proximity (soft Voronoi)
    float w0 = exp(-d0 * 8.0);
    float w1 = exp(-d1 * 8.0);
    float w2 = exp(-d2 * 8.0);
    float w3 = exp(-d3 * 8.0);
    float w4 = exp(-d4 * 8.0);
    float wSum = w0+w1+w2+w3+w4 + 1e-6;
    driftVel = (v0*w0 + v1*w1 + v2*w2 + v3*w3 + v4*w4) / wSum;

    // Boundary strength: the two closest plates differ in velocity
    // High where neighboring plates have very different velocities (shear zone)
    // Approximate: boundary ≈ where the top two distances are close
    // Re-find second min
    if (d0 > minD) minD2 = min(minD2, d0);
    if (d1 > minD) minD2 = min(minD2, d1);
    if (d2 > minD) minD2 = min(minD2, d2);
    if (d3 > minD) minD2 = min(minD2, d3);
    if (d4 > minD) minD2 = min(minD2, d4);
    float boundary = 1.0 - smoothstep(0.0, 0.09, minD2 - minD);

    return vec3(driftVel * 0.22, boundary); // scale velocity to px range
}

// ── Spherical mapping ─────────────────────────────────────────────────────────
// Map uv [0,1]^2 to a point on the front face of a sphere, return:
//   .x = latitude  [-PI/2, PI/2]   (negative = south pole)
//   .y = longitude [-PI,   PI  ]
//   .z = dot(surfaceNormal, sunDir) = local insolation  [0,1]
//
// The "sun" direction is fixed in space but the planet's axial tilt precesses
// over SEASON_PERIOD, so N hemisphere gets more sun at one phase, S at another.
vec3 sphereLatLon(vec2 uv, float t) {
    // Map uv to [-1,1]^2 and project onto sphere
    vec2 d = (uv - 0.5) * 2.0 / SPHERE_RADIUS;  // [-1/R, 1/R]
    float r2 = dot(d, d);
    if (r2 > 1.0) {
        // Outside the sphere silhouette — clamp to edge
        d = normalize(d) * 0.999;
        r2 = 0.998;
    }
    float z = sqrt(max(0.0, 1.0 - r2));  // z component on sphere surface

    // Sphere surface point (x right, y up, z toward viewer)
    vec3 P = vec3(d.x, d.y, z);

    // Latitude: asin of y component
    float lat = asin(clamp(P.y, -1.0, 1.0));
    // Longitude: atan2 of x,z
    float lon = atan(P.x, P.z);

    // Axial tilt: the planet's rotation axis is tilted toward the viewer
    // by AXIAL_TILT * sin(seasonPhase). This shifts which latitudes face the sun.
    float seasonPhase = t * (6.2832 / SEASON_PERIOD);
    float tiltNow     = AXIAL_TILT * sin(seasonPhase);

    // Sun direction (fixed in world space: comes from directly in front + slight up)
    // After tilt, the "effective latitude" receiving max sunlight is shifted.
    vec3 sunDir = normalize(vec3(0.0, sin(tiltNow), cos(tiltNow)));

    // Local insolation = dot(surface normal, sun direction), clamped to [0,1]
    float insolation = max(0.0, dot(P, sunDir));

    return vec3(lat, lon, insolation);
}

// ── Mantle layer sampler ───────────────────────────────────────────────────────
vec4 mantleLayer(vec2 uv, float depth, float speed, float phase, vec2 viewOff, float season) {
    vec2 parallax = viewOff * depth;
    vec2 p = uv + parallax;

    float t = iTime * speed + phase;
    float u = fnoise(p * 2.3 + vec2(t * 0.41, t * 0.29));
    float v = fnoise(p * 2.3 + vec2(t * 0.37 + 5.7, t * 0.31 + 3.1));

    float copper = fnoise(p * 1.7 + vec2(t*0.13, t*0.09 + 2.3));
    float iron   = fnoise(p * 1.5 + vec2(t*0.11 + 7.1, t*0.08 + 1.7));
    float silver = clamp(1.0 - copper - iron, 0.0, 1.0);

    // Season boosts heat in deep mantle during hot phase
    float heat = fnoise(p * 1.9 + vec2(t*0.19, t*0.15)) * 0.7
               + fnoise(p * 3.8 + vec2(t*0.27, t*0.22)) * 0.3;
    heat = mix(heat * 0.5, heat, season); // cold season dims the mantle

    return vec4(copper, iron, silver, heat);
}

// ── Main ──────────────────────────────────────────────────────────────────────

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec2 px = 1.0 / iResolution.xy;
    float t = iTime;

    // ── Spherical position ─────────────────────────────────────────────────────
    // Compute lat/lon and local insolation from spherical projection.
    // sphere.z = insolation [0,1] — this IS the local season for each pixel.
    vec3 sphere      = sphereLatLon(uv, t);
    float lat        = sphere.x;   // [-PI/2, PI/2]
    float lon        = sphere.y;   // [-PI, PI]
    float insolation = sphere.z;   // [0,1] — local sunlight hitting this point

    // ── Season ─────────────────────────────────────────────────────────────────
    // Global season phase [0,1] — used for mantle brightness, overall energy.
    // (Each pixel also has its own insolation that overrides locally.)
    float rawSeason = sin(t * (6.2832 / SEASON_PERIOD) - 1.5708);
    float season    = smoothstep(-0.6, 0.85, rawSeason);

    // LOCAL season = blend of global cycle + pixel's insolation
    // The equator always gets more heat, poles get less.
    // Axial tilt shifts which hemisphere gets the "summer" insolation peak.
    float localSeason = clamp(insolation * 1.3 * (0.4 + season * 0.8), 0.0, 1.0);

    // Season-modulated params (per-pixel, driven by local insolation)
    float eruptThresh = mix(ERUPT_THRESH_COLD, ERUPT_THRESH_HOT, localSeason);
    float eruptStr    = mix(ERUPT_STR_COLD,    ERUPT_STR_HOT,    localSeason);
    float crustGrow   = mix(CRUST_GROW * 1.8,  CRUST_GROW * 0.4, localSeason);
    float crustScour  = mix(CRUST_SCOUR* 0.5,  CRUST_SCOUR,      localSeason);

    // ── Read surface state ──────────────────────────────────────────────────────
    vec4  prev   = texture(iChannel1, uv);
    float sCu    = prev.r;
    float sFe    = prev.g;
    float crust  = prev.b;
    float flowE  = prev.a;
    float sAg    = clamp(1.0 - sCu - sFe, 0.0, 1.0);

    // Bootstrap first frame — chaotic initial state, no obvious blobs
    if (sCu + sFe + crust + flowE < 0.02) {
        // Use pixel-level hash for high-frequency base, then add multiple
        // independent noise scales — breaks the smooth large-blob look
        vec2 fp = fragCoord;
        float h0 = hash2(fp * 0.017 + vec2(13.7, 91.3));
        float h1 = hash2(fp * 0.031 + vec2(57.2, 23.8));
        float h2b = hash2(fp * 0.007 + vec2(38.1, 66.4));
        // Multi-scale noise: large regions + medium patches + fine grain
        float cu = fnoise(uv*3.1 + vec2(7.3,2.1))*0.5
                 + fnoise(uv*7.7 + vec2(1.1,8.8))*0.3
                 + h0*0.2;
        float fe = fnoise(uv*2.8 + vec2(4.4,9.2))*0.5
                 + fnoise(uv*6.3 + vec2(9.9,3.7))*0.3
                 + h1*0.2;
        // Normalize so metals share territory without obviously dividing screen
        float total = cu + fe + 0.35;
        sCu  = clamp(cu / total * 0.85, 0.0, 0.85);
        sFe  = clamp(fe / total * 0.85, 0.0, 1.0 - sCu);
        // Crust: uneven — some areas nearly bare, some thick
        crust = fnoise(uv*4.1 + vec2(2.2,7.7))*0.5
              + fnoise(uv*9.3 + vec2(5.5,1.9))*0.3
              + h2b*0.2;
        flowE = h0 * 0.08;  // small random initial heat
    }

    // ── Text ───────────────────────────────────────────────────────────────────
    vec3  term     = texture(iChannel0, uv).rgb;
    float termLuma = luma(term);
    float isText   = smoothstep(0.12, 0.38, termLuma);
    float warmth   = clamp((term.r - term.b)*2.0 + 0.5, 0.0, 1.0);

    // ── Neighbors ──────────────────────────────────────────────────────────────
    vec4 pN = texture(iChannel1, uv+vec2(0,    px.y));
    vec4 pS = texture(iChannel1, uv+vec2(0,   -px.y));
    vec4 pE = texture(iChannel1, uv+vec2( px.x, 0  ));
    vec4 pW = texture(iChannel1, uv+vec2(-px.x, 0  ));

    float nbErupt = (smoothstep(eruptThresh, 1.0, pN.a)
                   + smoothstep(eruptThresh, 1.0, pS.a)
                   + smoothstep(eruptThresh, 1.0, pE.a)
                   + smoothstep(eruptThresh, 1.0, pW.a)) * 0.25;

    // ── Surface velocity ───────────────────────────────────────────────────────
    float dCuX = pE.r - pW.r;
    float dCuY = pN.r - pS.r;
    float dFeX = pE.g - pW.g;
    float dFeY = pN.g - pS.g;
    vec2 vel = vec2(-(dCuY + dFeY*0.8), (dCuX + dFeX*0.8)) * BUOYANCY * px;
    vel *= (1.0 - crust*0.70);

    // Text stirring
    float tkN = luma(texture(iChannel0, uv+vec2(0,      px.y*4.0)).rgb);
    float tkS = luma(texture(iChannel0, uv+vec2(0,     -px.y*4.0)).rgb);
    float tkE = luma(texture(iChannel0, uv+vec2( px.x*4.0, 0    )).rgb);
    float tkW = luma(texture(iChannel0, uv+vec2(-px.x*4.0, 0    )).rgb);
    float textBoost = 1.0 + isText * (TEXT_BOOST - 1.0);
    vel += vec2(tkE-tkW, tkN-tkS) * TEXT_STIR * textBoost * px;

    // Erupting neighbors drive convective plume
    float dEN = smoothstep(eruptThresh,1.0,pN.a) - smoothstep(eruptThresh,1.0,pS.a);
    float dEX = smoothstep(eruptThresh,1.0,pE.a) - smoothstep(eruptThresh,1.0,pW.a);
    vel += vec2(-dEN, dEX) * 3.5 * px;

    // ── Plate tectonic drift ────────────────────────────────────────────────────
    // Each region of the surface belongs to a "plate" (soft Voronoi).
    // Local insolation scales vigour — hot pixels have more active tectonics.
    // Latitude also biases drift angle: near equator → predominantly E/W;
    // near poles → predominantly circular (Coriolis-like).
    vec3  plate        = plateDrift(uv, t);
    // Latitude bias: rotate plate velocity toward E/W at equator, circular at poles
    float latFrac      = abs(lat) / 1.5708;  // 0 at equator, 1 at poles
    float rotAngle     = latFrac * 1.2;      // rotate toward perpendicular at poles
    float cr = cos(rotAngle), sr = sin(rotAngle);
    vec2  biasedVel    = vec2(plate.x*cr - plate.y*sr, plate.x*sr + plate.y*cr);
    vec2  plateVel     = biasedVel * (0.7 + localSeason * 0.6);
    float plateBound   = plate.z;

    vel += plateVel * px;

    // Plate boundary: extra micro-turbulence in shear zones
    float bNoise = fnoise(uv*iResolution.xy*0.008 + vec2(t*0.019, t*0.013));
    vel += vec2(bNoise-0.5, fnoise(uv*iResolution.xy*0.008+vec2(t*0.011,t*0.017+3.1))-0.5)
           * plateBound * 0.25 * px;

    float velMag = length(vel);

    // ── Fracture ───────────────────────────────────────────────────────────────
    float shearCu  = length(vec2(pN.r-pS.r, pE.r-pW.r));
    float shearFe  = length(vec2(pN.g-pS.g, pE.g-pW.g));
    // Plate boundaries increase fracture likelihood
    float fracture = smoothstep(0.04, 0.15, max(shearCu, shearFe))
                   * smoothstep(0.28, 0.58, crust);
    fracture = max(fracture, plateBound * 0.35 * smoothstep(0.40, 0.80, crust));

    // ── Advect ─────────────────────────────────────────────────────────────────
    vec2 srcUV    = clamp(uv - vel*ADVECT_SPEED, px, 1.0-px);
    vec4 advected = texture(iChannel1, srcUV);

    // ── Alloy update ───────────────────────────────────────────────────────────
    float nbCu = (pN.r+pS.r+pE.r+pW.r)*0.25;
    float nbFe = (pN.g+pS.g+pE.g+pW.g)*0.25;
    float newCu = clamp(mix(advected.r, nbCu, ALLOY_DIFFUSE)
                + isText*warmth*TEXT_DEPOSIT - isText*(1.0-warmth)*TEXT_DEPOSIT*0.15,
                0.0, 1.0);
    float newFe = clamp(mix(advected.g, nbFe, ALLOY_DIFFUSE)
                + isText*(1.0-warmth)*0.5*TEXT_DEPOSIT,
                0.0, 1.0 - newCu);

    // ── Flow / heat ────────────────────────────────────────────────────────────
    float velN    = velMag / px.x;
    float newFlow = max(advected.a * FLOW_DECAY, velN*0.009);
    newFlow = max(newFlow, isText*0.93);
    newFlow = max(newFlow, nbErupt * ERUPT_SEEP);
    // Local insolation adds ambient heat — equator runs hotter, poles cooler
    newFlow = max(newFlow, localSeason * 0.14);

    // ── Mantle layers ──────────────────────────────────────────────────────────
    vec2 viewOff = vec2(
        sin(t*0.031)*0.5 + cos(t*0.019)*0.3,
        cos(t*0.027)*0.5 + sin(t*0.023)*0.3
    );

    vec4 mShallow = mantleLayer(uv, DEPTH_SHALLOW, 0.018, 0.0,  viewOff, localSeason);
    vec4 mMid     = mantleLayer(uv, DEPTH_MID,     0.011, 3.7,  viewOff, localSeason);
    vec4 mDeep    = mantleLayer(uv, DEPTH_DEEP,    0.006, 7.3,  viewOff, localSeason);

    // Eruption — season-gated
    float eruptNoise  = fnoise(uv*iResolution.xy*0.007 + t*0.008);
    float localThresh = eruptThresh * (0.65 + eruptNoise*0.60);
    float heatPress   = newFlow * (0.50 + eruptNoise*0.50);
    // Plate boundaries are weak points — lower local threshold there
    localThresh *= (1.0 - plateBound * 0.45);
    float upwelling   = smoothstep(localThresh, localThresh+0.30, heatPress)
                      * (1.0 - isText*0.75) * eruptStr;

    float eruptShallow = smoothstep(0.55, 0.85, mShallow.a) * upwelling;
    float eruptMid     = smoothstep(0.60, 0.90, mMid.a)     * upwelling * (1.0-eruptShallow);
    float eruptDeep    = smoothstep(0.65, 0.95, mDeep.a)    * upwelling * (1.0-eruptShallow) * (1.0-eruptMid);

    // ── Crust ──────────────────────────────────────────────────────────────────
    float newCrust = advected.b
                   + crustGrow  * (1.0-newFlow) * (1.0-isText)
                   - crustScour * newFlow * 0.07
                   - isText   * TEXT_BURN
                   - fracture * 0.07
                   - upwelling * ERUPT_SCOUR;
    newCrust = clamp(newCrust, 0.0, 1.0);

    float newAg = clamp(1.0 - newCu - newFe, 0.0, 1.0);

    // ═══════════════════════════════════════════════════════════════════════════
    // RENDER
    // ═══════════════════════════════════════════════════════════════════════════

    float fold = damascus(uv, (newCu+newFe)*0.35 + newCrust*0.28);

    // ── Mantle colors ──────────────────────────────────────────────────────────
    // Local insolation: equatorial mantles are brighter, polar mantles dimmer
    float mBrightMod = mix(0.55, MANTLE_BRIGHT, localSeason);

    // Mantle palette: soft blue-green — patinated, not lava.
    // Shallow: verdigris glow from below — teal-green
    vec3 mColShallow = mix(
        vec3(0.18, 0.48, 0.38),   // copper-zone melt: soft teal
        mix(vec3(0.14, 0.32, 0.42), vec3(0.28, 0.44, 0.36), mShallow.z),
        1.0 - mShallow.x
    );
    mColShallow *= (0.70 + mShallow.w * 0.50) * mBrightMod;

    // Mid: deeper teal-blue, like deep patina
    vec3 mColMid = mix(
        vec3(0.10, 0.28, 0.38),   // iron-zone: deep slate-blue
        vec3(0.20, 0.36, 0.40),   // silver-zone: muted cyan
        mMid.z
    );
    mColMid = mix(mColMid, vec3(0.08, 0.22, 0.30), mMid.y*0.6);
    mColMid *= (0.65 + mMid.w * 0.45) * mBrightMod * 0.85;

    // Deep: dark ocean blue-green
    vec3 mColDeep = vec3(0.06, 0.14, 0.18) * (0.60 + mDeep.w*0.50) * mBrightMod * 0.75;
    mColDeep = mix(mColDeep, vec3(0.12, 0.28, 0.32), mDeep.x*0.6);

    // ── Surface metal ──────────────────────────────────────────────────────────
    // Surface metals: cool blue-grey base — think wet steel, not hot copper
    vec3 COL_CU = vec3(0.38, 0.42, 0.35);  // oxidised copper: grey-green
    vec3 COL_FE = vec3(0.26, 0.30, 0.32);  // blue-grey steel
    vec3 COL_AG = vec3(0.52, 0.58, 0.64);  // cool silver

    vec3 metalColor = COL_FE;
    metalColor = mix(metalColor, COL_AG, smoothstep(0.06, 0.38, newAg));
    metalColor = mix(metalColor, COL_CU, smoothstep(0.06, 0.42, newCu));

    // Plate boundary seams: a slightly different tone at shear zones
    float seam = plateBound * smoothstep(0.55, 0.75, crust);
    metalColor = mix(metalColor, vec3(0.12, 0.10, 0.09), seam * 0.35);

    vec3 foldDark   = vec3(0.09, 0.08, 0.07);
    vec3 foldBright = vec3(0.50, 0.44, 0.34);
    metalColor = mix(metalColor, mix(foldDark,foldBright,fold), newAg*0.35 + (1.0-newCu-newFe)*0.25);

    float gloss = (1.0-newCrust)*smoothstep(0.0,0.25,newFlow);
    metalColor += vec3(0.22,0.15,0.08)*gloss*(fold*0.5+0.5);
    metalColor *= 0.86 + fnoise(uv*iResolution.xy*0.019)*0.25;
    metalColor = mix(metalColor, metalColor*1.9+vec3(0.09,0.06,0.02),
                     fracture*(1.0-isText)*0.80);

    // ── Tarnish ────────────────────────────────────────────────────────────────
    // Winter: tarnish is darker, more aged (colors shift toward old end)
    // Summer: fresh, vivid tarnish erupts to surface
    // Polar pixels → old aged tarnish; equatorial → fresh vivid tarnish
    float ageShift = 1.0 - localSeason * 0.5;

    // VERDIGRIS
    float verAge  = smoothstep(0.20, 0.75, newCrust) * ageShift;
    vec3 VERDIGRIS = mix(vec3(0.18, 0.68, 0.48),
                         vec3(0.10, 0.42, 0.36),
                         verAge);
    float verTex = noise2(uv*iResolution.xy*0.035 + vec2(13.7, 42.1))
                 * noise2(uv*iResolution.xy*0.021 + vec2(81.3, 23.7));
    float verHue = noise2(uv*iResolution.xy*0.012 + vec2(44.4, 17.2));
    VERDIGRIS = mix(VERDIGRIS, VERDIGRIS * vec3(0.6, 0.9, 1.3), verHue*0.4);
    VERDIGRIS *= 0.55 + verTex*0.90;

    // RUST
    float rustAge = smoothstep(0.15, 0.70, newCrust) * ageShift;
    vec3 RUST = mix(vec3(0.72, 0.32, 0.06),
                    vec3(0.38, 0.14, 0.03),
                    rustAge);
    float rustTex    = fnoise(uv*iResolution.xy*0.028 + vec2(57.3, 91.1));
    float rustStreak = noise2(uv*iResolution.xy*0.015 + vec2(22.2, 66.6));
    RUST = mix(RUST, RUST*vec3(1.4, 1.1, 0.5), rustStreak*0.35);
    RUST *= 0.50 + rustTex*0.80;

    // SULFIDE (silver tarnish)
    float agAge  = smoothstep(0.15, 0.70, newCrust) * ageShift;
    vec3 SULFIDE = mix(vec3(0.55, 0.48, 0.12),
                       vec3(0.12, 0.08, 0.10),
                       agAge);
    float agTex = noise2(uv*iResolution.xy*0.024 + vec2(33.1, 71.7));
    SULFIDE *= 0.65 + agTex*0.60;

    vec3 BLACK_BASE = vec3(0.028, 0.022, 0.018);

    float cuWeight = smoothstep(0.07, 0.40, newCu);
    float feWeight = smoothstep(0.07, 0.40, newFe) * (1.0 - cuWeight*0.8);
    float agWeight = smoothstep(0.07, 0.38, newAg) * (1.0 - cuWeight*0.8) * (1.0 - feWeight*0.8);

    float boundCuFe = cuWeight * feWeight * 4.0;
    float boundCuAg = cuWeight * agWeight * 4.0;
    vec3 BRONZE_TARNISH = vec3(0.28, 0.42, 0.14);
    vec3 CUAG_TARNISH   = vec3(0.30, 0.52, 0.32);

    vec3 tarnish = BLACK_BASE;
    tarnish = mix(tarnish, RUST,          feWeight);
    tarnish = mix(tarnish, SULFIDE,       agWeight);
    tarnish = mix(tarnish, VERDIGRIS,     cuWeight);
    tarnish = mix(tarnish, BRONZE_TARNISH,clamp(boundCuFe, 0.0, 1.0));
    tarnish = mix(tarnish, CUAG_TARNISH,  clamp(boundCuAg, 0.0, 1.0));

    float edgeSat = smoothstep(0.70, 0.08, newCrust)*0.4 + fracture*0.5;
    tarnish = mix(tarnish * 0.35, tarnish, 0.45 + edgeSat*0.55 + smoothstep(0.3,0.0,newCrust)*0.3);

    float tarnishAmt = newCrust * mix(0.48, 1.0, 1.0-fold*0.40);
    vec3 surface = mix(metalColor, tarnish, tarnishAmt);

    // ── Composite mantle ───────────────────────────────────────────────────────
    float visShallow = max(eruptShallow*1.0, fracture*0.30) * (1.0-isText);
    float visMid     = max(eruptMid*0.80,    fracture*0.18) * (1.0-isText);
    float visDeep    = max(eruptDeep*0.55,   fracture*0.08) * (1.0-isText);
    float seepVis    = nbErupt * 0.30 * (1.0-isText);
    // Plate boundary upwellings: show deep mantle along seam lines
    float boundVis   = plateBound * smoothstep(0.45, 0.75, newFlow) * (1.0-isText);

    // textHeat also bleeds molten color into surrounding surface
    float textMoltenVis = textHeat * 0.80 * (1.0 - isText);

    vec3 mantleComp = surface;
    mantleComp = mix(mantleComp, mColDeep,   clamp(visDeep   + seepVis*0.4 + boundVis*0.5 + textMoltenVis*0.4, 0.0, 1.0));
    mantleComp = mix(mantleComp, mColMid,    clamp(visMid    + seepVis*0.6 + boundVis*0.3 + textMoltenVis*0.6, 0.0, 1.0));
    mantleComp = mix(mantleComp, mColShallow,clamp(visShallow                              + textMoltenVis*0.9, 0.0, 1.0));
    surface = mantleComp;

    // Surface dim — equator glows slightly brighter, poles darker
    surface *= mix(SURFACE_DIM * 0.75, SURFACE_DIM * 1.20, localSeason);

    // ── Text penumbra ──────────────────────────────────────────────────────────
    float h1=luma(texture(iChannel0,uv+vec2(0,     px.y*2.0)).rgb);
    float h2=luma(texture(iChannel0,uv+vec2(0,    -px.y*2.0)).rgb);
    float h3=luma(texture(iChannel0,uv+vec2( px.x*2.0,0    )).rgb);
    float h4=luma(texture(iChannel0,uv+vec2(-px.x*2.0,0    )).rgb);
    float nearText=smoothstep(0.08,0.38,max(max(h1,h2),max(h3,h4)));
    float h5=luma(texture(iChannel0,uv+vec2(0,     px.y*5.0)).rgb);
    float h6=luma(texture(iChannel0,uv+vec2(0,    -px.y*5.0)).rgb);
    float h7=luma(texture(iChannel0,uv+vec2( px.x*5.0,0    )).rgb);
    float h8=luma(texture(iChannel0,uv+vec2(-px.x*5.0,0    )).rgb);
    float farText=smoothstep(0.08,0.38,max(max(h5,h6),max(h7,h8)));
    float shadow=(nearText*0.75+farText*0.25)*(1.0-isText);
    surface *= (1.0 - shadow * SHADOW_STR);

    // ── Neon text ──────────────────────────────────────────────────────────────
    // Cool blue-green text glow — soft, easy on the eyes
    vec3 glowTerm = term*1.20 + vec3(0.00,0.04,0.06);  // push toward cyan-teal
    float gLuma   = luma(glowTerm);
    if (gLuma < TEXT_MIN_LUMA) glowTerm *= TEXT_MIN_LUMA/max(gLuma,0.001);
    glowTerm = clamp(glowTerm, 0.0, 1.0);

    float eN=luma(texture(iChannel0,uv+vec2(0,  px.y)).rgb);
    float eS=luma(texture(iChannel0,uv+vec2(0, -px.y)).rgb);
    float eE=luma(texture(iChannel0,uv+vec2( px.x,0 )).rgb);
    float eW=luma(texture(iChannel0,uv+vec2(-px.x,0 )).rgb);
    float rim=isText*smoothstep(0.0,0.4,max(0.0,isText-(eN+eS+eE+eW)*0.25));
    glowTerm += vec3(0.05,0.14,0.16)*rim;  // teal-cyan rim

    // ── Text-driven molten zone ───────────────────────────────────────────────
    // Letters act as electrodes — sample text at wider radius to build a
    // heat bloom around each glyph. This drives strong local flow/upwelling.
    float r1 = luma(texture(iChannel0, uv+vec2( px.x*3.0,  0        )).rgb)
             + luma(texture(iChannel0, uv+vec2(-px.x*3.0,  0        )).rgb)
             + luma(texture(iChannel0, uv+vec2( 0,          px.y*3.0)).rgb)
             + luma(texture(iChannel0, uv+vec2( 0,         -px.y*3.0)).rgb);
    float r2 = luma(texture(iChannel0, uv+vec2( px.x*7.0,  0        )).rgb)
             + luma(texture(iChannel0, uv+vec2(-px.x*7.0,  0        )).rgb)
             + luma(texture(iChannel0, uv+vec2( 0,          px.y*7.0)).rgb)
             + luma(texture(iChannel0, uv+vec2( 0,         -px.y*7.0)).rgb);
    float r3 = luma(texture(iChannel0, uv+vec2( px.x*14.0, 0        )).rgb)
             + luma(texture(iChannel0, uv+vec2(-px.x*14.0, 0        )).rgb)
             + luma(texture(iChannel0, uv+vec2( 0,          px.y*14.0)).rgb)
             + luma(texture(iChannel0, uv+vec2( 0,         -px.y*14.0)).rgb);
    // textHeat: strong right at letter, fades over ~14px radius
    float textHeat = smoothstep(0.0, 0.5, r1*0.25)*0.65
                   + smoothstep(0.0, 0.4, r2*0.25)*0.25
                   + smoothstep(0.0, 0.3, r3*0.25)*0.10;
    textHeat *= (1.0 - isText);  // don't apply to the letter pixel itself

    // Inject heat into flow — makes the mantle erupt around letters
    newFlow = max(newFlow, textHeat * 0.88);
    // Also scour crust near hot letters
    newCrust = clamp(newCrust - textHeat * 0.35, 0.0, 1.0);

    float shimmer=sin(t*1.8+uv.x*17.3+uv.y*11.7)*0.5+0.5;
    surface += vec3(0.05,0.03,0.01)*shimmer*gloss*(1.0-tarnishAmt)*(1.0-isText);

    vec3 color = mix(surface, glowTerm, isText);

    // Vignette
    color *= 1.0 - VIGNETTE*pow(length((uv-0.5)*vec2(1.1,0.85)), 2.0);

    // ── State output ───────────────────────────────────────────────────────────
    vec3 finalRGB = mix(color, vec3(newCu, newFe, newCrust), 0.18);
    finalRGB = mix(finalRGB, glowTerm, isText);
    fragColor = vec4(clamp(finalRGB,0.0,1.0), clamp(newFlow,0.0,1.0));
}
