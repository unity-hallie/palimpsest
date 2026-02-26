// Terraform
// A planet terraforms as you write.
// Text density drives biome progression: glaciated ice → barren → living world.
// The planetary terminator sweeps day/night across the map.
// Mountains form on the left; the sea drains right; rivers carve downhill.

// ── Tuning ────────────────────────────────────────────────────────────────────
#define TERRAIN_SCALE  3.4     // spatial frequency of terrain
#define DAY_DURATION   240.0   // seconds per day
#define YEAR_DURATION  1920.0  // 8 day-cycles per year — seasons visible within the hour
#define AXIAL_TILT     0.42    // radians (~24°)
#define LIFE_DURATION  3600.0  // seconds for full terraforming (1 hour)
#define SEA_LEVEL      0.37
#define BEACH_LEVEL    0.50
#define GRASS_LEVEL    0.60
#define FOREST_LEVEL   0.70
#define ROCK_LEVEL     0.82
#define WIND_SPEED     0.038
#define CLOUD_SPEED    0.011
#define TWO_PI         6.28318530718
// Background luma of the terminal theme (#080C0D) — zeroes the life signal on blank screen
#define BG_LUMA        0.043

float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise(vec2 p) {
    vec2 i = floor(p); vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash21(i),               hash21(i + vec2(1.0, 0.0)), f.x),
        mix(hash21(i + vec2(0.0,1.0)), hash21(i + vec2(1.0,1.0)), f.x),
        f.y);
}
float fbm(vec2 p) {
    float v  = noise(p)                           * 0.5000;
    v       += noise(p * 2.01 + vec2(1.7,  9.2))  * 0.2500;
    v       += noise(p * 4.03 + vec2(8.3,  2.8))  * 0.1250;
    v       += noise(p * 8.07 + vec2(3.1,  7.4))  * 0.0625;
    v       += noise(p * 16.1 + vec2(5.4,  1.2))  * 0.0313;
    return v;
}

// Double-warped terrain — coastlines that look geological
float terrain(vec2 p) {
    vec2 w1 = vec2(fbm(p + vec2(1.3,0.4)), fbm(p + vec2(8.2,3.7)));
    vec2 w2 = vec2(fbm(p + w1*1.4 + vec2(2.8,6.1)), fbm(p + w1*1.4 + vec2(5.4,0.9)));
    return fbm(p + w2 * 0.8);
}

// Normals from single-pass fbm
vec3 fastNormal(vec2 p, float bump) {
    float eps = 0.004, sc = 9.5;
    float nL = fbm((p - vec2(eps,0.0)) * sc);
    float nR = fbm((p + vec2(eps,0.0)) * sc);
    float nD = fbm((p - vec2(0.0,eps)) * sc);
    float nU = fbm((p + vec2(0.0,eps)) * sc);
    float ar = iResolution.x / iResolution.y;
    return normalize(vec3((nL-nR)*bump*ar, (nD-nU)*bump, 1.0));
}

// Wide-radius Gaussian blur of terminal texture → life signal
// r=0.09 ≈ 173px on 1920-wide, fully dissolves characters into density regions
float getLifeH(vec2 uv) {
    float r = 0.09, h = 0.0;
    h += luma(texture(iChannel0, uv+vec2(-r,-r)).rgb)*0.0625;
    h += luma(texture(iChannel0, uv+vec2( 0.,-r)).rgb)*0.125;
    h += luma(texture(iChannel0, uv+vec2( r,-r)).rgb)*0.0625;
    h += luma(texture(iChannel0, uv+vec2(-r, 0.)).rgb)*0.125;
    h += luma(texture(iChannel0, uv            ).rgb)*0.25;
    h += luma(texture(iChannel0, uv+vec2( r, 0.)).rgb)*0.125;
    h += luma(texture(iChannel0, uv+vec2(-r, r)).rgb)*0.0625;
    h += luma(texture(iChannel0, uv+vec2( 0., r)).rgb)*0.125;
    h += luma(texture(iChannel0, uv+vec2( r, r)).rgb)*0.0625;
    return h;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2  uv  = fragCoord / iResolution.xy;
    float ar  = iResolution.x / iResolution.y;
    vec2  p   = vec2(uv.x * ar, uv.y);
    float t   = iTime;

    // Read terminal texture once — used for life signal and final composite
    vec4 terminal = texture(iChannel0, uv);

    // ── Terrain height + normals ───────────────────────────────────────────────
    float h = terrain(p * TERRAIN_SCALE);
    h = h * 0.84 + 0.10;
    h = clamp(h + (0.58 - uv.x) * 0.36, 0.0, 1.0);
    h += smoothstep(FOREST_LEVEL, 1.0, h) * 0.24;
    h  = clamp(h, 0.0, 1.0);
    float bump   = mix(1.0, 9.0, smoothstep(GRASS_LEVEL, ROCK_LEVEL, h));
    vec3  normal = fastNormal(p, bump);

    // ── Terraforming progress ─────────────────────────────────────────────────
    // Subtract terminal background luma so blank screens read as zero density
    float rawDensity   = getLifeH(uv);
    float textDensity  = max(0.0, rawDensity - BG_LUMA) / (1.0 - BG_LUMA);
    float lifeProgress = smoothstep(0.0, LIFE_DURATION, t);
    float elevBonus    = smoothstep(1.0, 0.3, h);
    float lifeAmount   = smoothstep(0.0, 1.0, textDensity * lifeProgress * elevBonus * 4.5);

    float iceAmount = smoothstep(0.30, 0.02, lifeProgress);
    float riverMelt = smoothstep(0.05, 0.45, lifeProgress);
    float isLowland = (1.0 - smoothstep(BEACH_LEVEL, FOREST_LEVEL, h)) * step(SEA_LEVEL, h);

    float snowProgress = smoothstep(0.28, 0.56, lifeProgress);
    float snowMelt     = smoothstep(0.80, 1.00, lifeProgress);
    float snowLine     = mix(ROCK_LEVEL + 0.03, 0.84, snowMelt);
    float snowCover    = snowProgress * (1.0 - snowMelt * 0.88);

    // ── Day/night: axial tilt + seasons + planetary terminator ────────────────
    float dayPhase    = t * TWO_PI / DAY_DURATION;
    float yearPhase   = t * TWO_PI / YEAR_DURATION;
    float declination = sin(yearPhase) * AXIAL_TILT;
    float latitude    = (uv.y - 0.5) * 1.85;
    float hourAngle   = dayPhase + (uv.x - 0.5) * 2.6;
    float sunElev     = sin(latitude)*sin(declination)
                      + cos(latitude)*cos(declination)*sin(hourAngle);
    float sunAz       = cos(dayPhase);
    float isDay       = smoothstep(-0.12, 0.20, sunElev);
    float isDawnDusk  = smoothstep(0.45, 0.0, abs(sunElev)) * isDay;
    vec3  sunDir      = normalize(vec3(sunAz * 0.6, 0.5, max(sunElev, 0.0) * 1.3 + 0.05));

    float solarInsolation = max(0.0, cos(latitude - declination));
    float solarHeat       = clamp(sunElev, 0.0, 1.0) * solarInsolation;
    float sunIceMelt      = solarHeat * lifeProgress * 2.2;
    float localIce        = clamp(iceAmount - sunIceMelt * 0.70, 0.0, 1.0);

    // Sun disc
    vec3 sunIce    = vec3(0.84, 0.91, 1.00);
    vec3 sunBarren = mix(vec3(0.94,0.84,0.58), vec3(1.00,0.93,0.78), lifeAmount);
    vec3 sunMidday = mix(sunIce, sunBarren, smoothstep(0.0, 0.3, lifeProgress));
    vec3 sunCol    = sunMidday * isDay;

    // Horizon glow: fires near the terminator, NOT gated by isDay
    float horizGlow = smoothstep(0.38, 0.0, abs(sunElev));
    vec3  horizCol  = mix(vec3(0.55,0.72,1.00), vec3(1.00,0.48,0.12), lifeProgress);
    sunCol = mix(sunCol, horizCol * 0.85, horizGlow * isDay * 0.70);

    // Sky ambient
    vec3 nightAmb  = mix(vec3(0.05, 0.07, 0.16), vec3(0.03, 0.04, 0.10), lifeProgress);
    vec3 iceAmbDay = vec3(0.68, 0.76, 0.92);
    vec3 horizAmb  = mix(vec3(0.45,0.55,0.80), vec3(0.55,0.28,0.10), lifeProgress);
    vec3 dayAmb    = mix(iceAmbDay, mix(vec3(0.42,0.34,0.24), vec3(0.46,0.66,0.92), lifeAmount), smoothstep(0.0,0.35,lifeProgress));
    vec3 skyAmb    = mix(nightAmb, mix(horizAmb, dayAmb, smoothstep(-0.1, 0.5, sunElev)), isDay);
    skyAmb = mix(skyAmb, horizCol * 0.55, horizGlow * 0.45);

    // ── Breeze on vegetation ──────────────────────────────────────────────────
    float grassFac  = step(BEACH_LEVEL,h) * (1.0 - step(GRASS_LEVEL,h));
    float forestFac = step(GRASS_LEVEL,h) * (1.0 - step(FOREST_LEVEL,h));
    float bAmt = (grassFac*0.11 + forestFac*0.045) * lifeAmount;
    vec2  bUV  = p*10.0 + vec2(t*WIND_SPEED, t*WIND_SPEED*0.43);
    float bx   = (noise(bUV)               - 0.5) * 2.0 * bAmt;
    float by   = (noise(bUV+vec2(4.1,7.3)) - 0.5) * 2.0 * bAmt;
    normal = normalize(normal + vec3(bx, by, 0.0));

    // ── Wave normals on water ─────────────────────────────────────────────────
    float inSea   = 1.0 - step(SEA_LEVEL, h);
    float waveAmp = mix(0.08, 0.22, lifeAmount);
    vec2  wv1 = p*16.0 + vec2( t*0.20,  t*0.10);
    vec2  wv2 = p*10.0 + vec2(-t*0.13,  t*0.18);
    vec3  waterBase = mix(normal, vec3(0.0, 0.0, 1.0), inSea);
    vec3  surfN = normalize(waterBase + vec3((noise(wv1)-0.5)*waveAmp*inSea, (noise(wv2)-0.5)*waveAmp*inSea, 0.0));

    // ── Lighting ──────────────────────────────────────────────────────────────
    float diff      = max(dot(surfN, sunDir), 0.0) * isDay;
    float northFace = 1.0 - max(dot(normal, normalize(vec3(0.5,-0.6,0.8))), 0.0);
    float ao        = mix(1.0, mix(0.45, 0.58, smoothstep(0.0,0.4,lifeProgress)), northFace*northFace*0.70);
    vec3  ltotal    = (skyAmb * 0.22 + sunCol * diff * 0.95) * ao;
    vec3  ltotalIce = ltotal + iceAmbDay * 0.18 * localIce * isDay;

    // ── River channels ────────────────────────────────────────────────────────
    float riverH   = fbm(p * TERRAIN_SCALE * 1.8 + vec2(3.3, 7.1));
    float riverCh  = smoothstep(0.51, 0.55, riverH) * (1.0 - smoothstep(0.55, 0.59, riverH));
    float riverVis = riverCh * isLowland * riverMelt * (1.0 - lifeAmount * 0.8);

    // ── Biome colors: ice / barren-grey / living ──────────────────────────────
    vec3 iColor = vec3(0.0);
    vec3 bColor = vec3(0.0);
    vec3 lColor = vec3(0.0);

    if (h < SEA_LEVEL) {
        float depth = h / SEA_LEVEL;
        iColor = mix(vec3(0.68,0.74,0.84), vec3(0.78,0.84,0.92), depth*depth);
        bColor = mix(vec3(0.10,0.11,0.14), vec3(0.20,0.22,0.26), depth*depth);
        lColor = mix(vec3(0.03,0.08,0.30), vec3(0.08,0.28,0.58), depth*depth);
        vec3  halfV = normalize(sunDir + vec3(0.0,0.0,1.0));
        float spec  = pow(max(dot(surfN,halfV),0.0), 85.0) * 0.75 * isDay;
        iColor = iColor * ltotalIce + sunCol * spec * 1.3;
        bColor = bColor * ltotal    + sunCol * spec * 0.3;
        lColor = lColor * ltotal    + sunCol * spec;

    } else if (h < BEACH_LEVEL) {
        float s = (h-SEA_LEVEL)/(BEACH_LEVEL-SEA_LEVEL);
        iColor = mix(vec3(0.80,0.87,0.97), vec3(0.89,0.94,1.00), s) * ltotalIce;
        bColor = mix(vec3(0.30,0.29,0.27), vec3(0.40,0.38,0.34), s) * ltotal;
        lColor = mix(vec3(0.42,0.39,0.32), vec3(0.72,0.66,0.48), s) * ltotal;

    } else if (h < GRASS_LEVEL) {
        float s = (h-BEACH_LEVEL)/(GRASS_LEVEL-BEACH_LEVEL);
        iColor = mix(vec3(0.84,0.91,0.98), vec3(0.78,0.87,0.96), s) * ltotalIce;
        bColor = mix(vec3(0.32,0.30,0.27), vec3(0.40,0.38,0.34), s) * ltotal;
        vec3 carbonSoil = mix(vec3(0.09,0.08,0.06), vec3(0.07,0.07,0.05), s);
        vec3 grassGreen = mix(vec3(0.52,0.72,0.26), vec3(0.37,0.60,0.17), s);
        lColor = mix(carbonSoil, grassGreen, smoothstep(0.30, 0.75, lifeAmount)) * ltotal;

    } else if (h < FOREST_LEVEL) {
        float s = (h-GRASS_LEVEL)/(FOREST_LEVEL-GRASS_LEVEL);
        iColor = mix(vec3(0.89,0.94,0.99), vec3(0.93,0.97,1.00), s) * ltotalIce;
        bColor = mix(vec3(0.26,0.25,0.22), vec3(0.22,0.21,0.20), s) * ltotal;
        vec3 carbonDeep  = mix(vec3(0.07,0.06,0.04), vec3(0.05,0.05,0.04), s);
        vec3 forestGreen = mix(vec3(0.19,0.44,0.12), vec3(0.09,0.28,0.07), s);
        vec3 halfV2 = normalize(sunDir+vec3(0.0,0.0,1.0));
        float lSpc = pow(max(dot(surfN,halfV2),0.0),22.0)*0.09*isDay;
        lColor = mix(carbonDeep, forestGreen, smoothstep(0.40, 0.82, lifeAmount)) * ltotal + sunCol * lSpc;

    } else if (h < ROCK_LEVEL) {
        float s = (h-FOREST_LEVEL)/(ROCK_LEVEL-FOREST_LEVEL);
        iColor = mix(vec3(0.89,0.93,0.99), vec3(0.94,0.97,1.00), s) * ltotalIce;
        bColor = mix(vec3(0.28,0.27,0.26), vec3(0.22,0.22,0.21), s) * ltotal;
        lColor = mix(vec3(0.48,0.43,0.36), vec3(0.62,0.56,0.47), s) * ltotal;

    } else {
        float s = clamp((h-ROCK_LEVEL)/(1.0-ROCK_LEVEL), 0.0, 1.0);
        iColor = mix(vec3(0.92,0.96,1.00), vec3(0.99,1.00,1.00), s) * ltotalIce;
        bColor = mix(vec3(0.20,0.20,0.20), vec3(0.38,0.37,0.36), s) * ltotal;
        lColor = mix(vec3(0.74,0.78,0.84), vec3(0.93,0.96,1.00), s);
        float sSpc = pow(max(dot(surfN,sunDir),0.0),14.0)*0.40*isDay;
        lColor = lColor * ltotal + sunCol * sSpc * 0.35;
    }

    // Three-way blend: ice → barren → living
    float iceThaw   = smoothstep(0.0, 0.35, lifeProgress);
    float localThaw = clamp(iceThaw + sunIceMelt * 0.55, 0.0, 1.0);
    vec3  color     = mix(mix(iColor, bColor, localThaw), lColor, lifeAmount);

    // ── Mountain snow caps ────────────────────────────────────────────────────
    float snowEdgeNoise = (noise(p * 5.5 + vec2(3.1, 7.4)) - 0.5) * 0.045;
    float snowAmt = smoothstep(snowLine + snowEdgeNoise,
                               snowLine + snowEdgeNoise + 0.13, h)
                  * snowCover * (1.0 - solarHeat * lifeProgress * 0.9);
    if (snowAmt > 0.01) {
        float sSpcSn = pow(max(dot(surfN, sunDir), 0.0), 20.0) * 0.55 * isDay;
        vec3  snowPx = vec3(0.87, 0.92, 0.98) * ltotal + sunCol * sSpcSn;
        color = mix(color, snowPx, snowAmt);
    }

    // ── Ice fractures ─────────────────────────────────────────────────────────
    float aboveSea = step(SEA_LEVEL, h) * step(h, FOREST_LEVEL);
    if (aboveSea > 0.5 && localIce > 0.02) {
        float iceLine = smoothstep(0.59, 0.65, fbm(p * 22.0 + vec2(4.4,2.1)));
        color += vec3(-0.09, -0.05, 0.10) * iceLine * localIce * aboveSea;
    }

    // ── Dry earth cracks ──────────────────────────────────────────────────────
    if (aboveSea > 0.5 && lifeAmount < 0.92 && iceAmount < 0.3) {
        float crackLine = smoothstep(0.60, 0.67, fbm(p * 19.0 + vec2(2.2,7.1)));
        color -= vec3(0.05, 0.04, 0.03) * crackLine * (1.0 - lifeAmount) * (1.0 - iceAmount) * aboveSea;
    }

    // ── Rivers ────────────────────────────────────────────────────────────────
    if (riverVis > 0.01) {
        vec3  riverWater = mix(vec3(0.55,0.72,0.92), vec3(0.10,0.34,0.62), smoothstep(0.1,0.5,lifeProgress));
        vec3  halfVr = normalize(sunDir + vec3(0.0,0.0,1.0));
        float rSpec  = pow(max(dot(normal,halfVr),0.0),60.0) * 0.5 * isDay;
        color = mix(color, riverWater * ltotal + sunCol * rSpec, riverVis * 0.88);
    }

    // ── Shoreline foam ────────────────────────────────────────────────────────
    float sInner = smoothstep(SEA_LEVEL - 0.010, SEA_LEVEL, h);
    float sOuter = smoothstep(SEA_LEVEL + 0.010, SEA_LEVEL, h);
    float foam   = smoothstep(0.43, 0.57, fbm(p * 14.0 + vec2(t * 0.36, -t * 0.19)));
    vec3  foamCol = mix(vec3(0.88,0.92,0.98), mix(vec3(0.58,0.50,0.40), vec3(0.92,0.95,1.00), lifeAmount), smoothstep(0.0,0.25,lifeProgress));
    color = mix(color, foamCol, foam * sInner * sOuter * 0.80);

    // ── Aurora: curved oval ring around poles ─────────────────────────────────
    float auroraVis  = iceAmount * (1.0 - isDay);
    vec3  auroraAccum = vec3(0.0);
    if (auroraVis > 0.01) {
        vec2  dN = vec2(uv.x - 0.5, uv.y - 1.0);
        vec2  dS = vec2(uv.x - 0.5, uv.y - 0.0);
        float distN = length(dN);
        float distS = length(dS);
        float R = 0.32, W = 0.075;
        float northBand = smoothstep(R - W, R, distN) * (1.0 - smoothstep(R, R + W, distN));
        float southBand = smoothstep(R - W, R, distS) * (1.0 - smoothstep(R, R + W, distS));
        float auroraMask = max(northBand, southBand);
        if (auroraMask > 0.005) {
            float angN  = atan(dN.x, -dN.y);
            float angS  = atan(dS.x,  dS.y);
            float arcX  = (distN < distS) ? angN : angS;
            float rx    = arcX * 22.0 + t * 0.22;
            float rays  = pow(abs(sin(rx)) * abs(sin(rx * 1.618 + 1.1)), 0.55);
            vec2  cUV    = vec2(arcX * 1.6 + t * 0.013, t * 0.005);
            float curtain = sin(cUV.x * 5.4 + noise(cUV * 1.2) * 2.8) * 0.5 + 0.5;
            curtain *= 0.50 + 0.50 * noise(vec2(cUV.x * 2.4, t * 0.07));
            float intensity = rays * curtain * auroraMask * auroraVis;
            float cVar = noise(vec2(arcX * 3.8 + t * 0.010, t * 0.004));
            vec3  aCol = mix(vec3(0.04, 0.90, 0.34), vec3(0.05, 0.44, 0.88), cVar * 0.55);
            color += aCol * intensity * 0.22;
            auroraAccum = aCol * intensity;
        }
    }
    color += auroraAccum * (1.0 - inSea) * 0.06;
    color += auroraAccum * inSea * 0.18;

    // ── Campfires near rivers at night ────────────────────────────────────────
    float campVis = isLowland * (1.0 - isDay) * smoothstep(0.06, 0.24, lifeProgress)
                  * (1.0 - localIce) * clamp(textDensity * 2.5, 0.0, 1.0);
    if (campVis > 0.01) {
        vec2  fireGrid  = floor(p * 14.0);
        vec3  fireAccum = vec3(0.0);
        for (int di = -1; di <= 1; di++) {
            for (int dj = -1; dj <= 1; dj++) {
                vec2  ng   = fireGrid + vec2(float(di), float(dj));
                float seed = hash21(ng + vec2(91.7, 47.3));
                if (seed > 0.95 && textDensity > 0.38) {
                    vec2  fPos    = (ng + 0.5) / 14.0;
                    float dist    = length(p - fPos) * 14.0;
                    float flicker = 0.60 + 0.40 * noise(vec2(seed*53.1, t*4.8 + seed*18.2));
                    float glow    = exp(-dist*dist*0.9) * flicker;
                    float edgeT   = smoothstep(0.0, 1.8, dist);
                    fireAccum += mix(vec3(1.00,0.72,0.18), vec3(0.85,0.22,0.03), edgeT) * glow;
                }
            }
        }
        color += fireAccum * campVis * 0.45;
    }

    // ── Cloud shadows ─────────────────────────────────────────────────────────
    float cloudAmt = lifeAmount * isDay;
    if (cloudAmt > 0.01) {
        vec2  cUV   = uv * 2.2 + vec2(t*CLOUD_SPEED, t*CLOUD_SPEED*0.38);
        float cloud = fbm(cUV) * fbm(cUV * 2.1 + vec2(4.3,1.2));
        color *= 1.0 - smoothstep(0.15, 0.28, cloud) * 0.28 * cloudAmt;
    }

    // ── Ice overcast ──────────────────────────────────────────────────────────
    if (localIce > 0.02 && isDay > 0.05) {
        vec2  cUV2  = uv * 1.6 + vec2(t*CLOUD_SPEED*0.55, -t*CLOUD_SPEED*0.27);
        float iceCld = fbm(cUV2) * 0.45 + 0.20;
        color = mix(color, skyAmb * 0.88, iceCld * localIce * isDay * 0.28);
    }

    // ── Valley mist / sea haze ────────────────────────────────────────────────
    float mist = smoothstep(BEACH_LEVEL, SEA_LEVEL, h);
    color = mix(color, skyAmb * 0.60, mist * 0.18);

    // Night ocean: faint deep-blue so the sea isn't a pure void
    color += vec3(0.012, 0.018, 0.038) * inSea * (1.0 - isDay);

    // ── Eye-comfort pass ─────────────────────────────────────────────────────
    color *= 0.46;
    float colorLuma = luma(color);
    color = mix(color, vec3(colorLuma), 0.28);

    // ── Text compositing ──────────────────────────────────────────────────────
    // Shadow is always dark (bright shadow = doubled-text visual artefact).
    // Legibility on dark backgrounds handled by the omnidirectional glow halo.
    float px = 1.0 / iResolution.x;
    float py = 1.0 / iResolution.y;

    float textVal = luma(terminal.rgb);

    // Three-layer dark drop shadow
    float shd1 = luma(texture(iChannel0, uv + vec2( 3.0*px, -3.0*py)).rgb);
    float shd2 = luma(texture(iChannel0, uv + vec2( 5.0*px, -5.0*py)).rgb);
    float shd3 = luma(texture(iChannel0, uv + vec2(-2.0*px,  2.5*py)).rgb);
    vec3  darkShadow = vec3(0.00, 0.004, 0.012);
    color = mix(color, darkShadow, shd1 * 0.92);
    color = mix(color, darkShadow, shd2 * 0.60);
    color = mix(color, darkShadow, shd3 * 0.38);

    // Omnidirectional glow halo — brightens area behind text on dark terrain
    float gR = 6.0 * px, gRy = 6.0 * py;
    float glow = 0.0;
    glow += luma(texture(iChannel0, uv+vec2(-gR,  0.0)).rgb) * 1.00;
    glow += luma(texture(iChannel0, uv+vec2( gR,  0.0)).rgb) * 1.00;
    glow += luma(texture(iChannel0, uv+vec2( 0.0,-gRy)).rgb) * 1.00;
    glow += luma(texture(iChannel0, uv+vec2( 0.0, gRy)).rgb) * 1.00;
    glow += luma(texture(iChannel0, uv+vec2(-gR, -gRy)).rgb) * 0.65;
    glow += luma(texture(iChannel0, uv+vec2( gR, -gRy)).rgb) * 0.65;
    glow += luma(texture(iChannel0, uv+vec2(-gR,  gRy)).rgb) * 0.65;
    glow += luma(texture(iChannel0, uv+vec2( gR,  gRy)).rgb) * 0.65;
    glow /= 5.6;

    float bgLuma  = luma(color);
    vec3  glowCol = mix(vec3(0.48,0.64,0.96), vec3(0.65,0.80,1.00), lifeProgress);
    color += glowCol * glow * smoothstep(0.50, 0.04, bgLuma) * 0.38;

    // Dark underlay: dims terrain behind text for daytime legibility
    float underlayMask = clamp(max(glow * 1.6, textVal), 0.0, 1.0);
    color = mix(color, color * 0.12, underlayMask * 0.72);

    // Composite terminal text on top of terrain — terminal pixels replace background
    color = mix(color, terminal.rgb, textVal * 0.95);

    fragColor = vec4(color, terminal.a);
}
