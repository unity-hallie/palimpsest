// ocean.glsl — rolling ocean swells with day/night cycle + boid fish school
//
// iChannel0 = terminal content
// iChannel2 = fish boid state (ocean.compute.msl)
//             row 0, pixel i: (posX, posY, velX, velY) for fish i

// ── Tuning ────────────────────────────────────────────────────────────────────
#define HORIZON      0.28     // where ocean meets sky (0=bottom, 1=top)
#define WAVE_HEIGHT  0.014    // swell amplitude
#define CHOP         0.52     // steepness / choppiness
#define FOAM_STR     0.55     // whitecap brightness
#define REFRACT_STR  0.028    // text distortion through surface
#define CYCLE_TIME   600.0    // seconds per full day (10 min)
#define NUM_FISH     32      // boid fish (matches ocean.compute.msl)
// ─────────────────────────────────────────────────────────────────────────────

float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

vec3 gerstner(vec2 pos, vec2 dir, float wavelength, float amplitude, float steepness, float speed) {
    float k = 6.28318 / wavelength;
    float c = sqrt(9.8 / k);
    float f = k * (dot(dir, pos) - c * speed * iTime);
    float Q = steepness / (k * amplitude);
    return vec3(Q * amplitude * dir.x * cos(f), Q * amplitude * dir.y * cos(f), amplitude * sin(f));
}

vec3 oceanSurface(vec2 pos) {
    vec3 w = vec3(0.0);
    w += gerstner(pos, normalize(vec2(1.0,  0.4)), 0.38, WAVE_HEIGHT * 1.00, CHOP, 0.32);
    w += gerstner(pos, normalize(vec2(0.7,  1.0)), 0.21, WAVE_HEIGHT * 0.60, CHOP, 0.28);
    w += gerstner(pos, normalize(vec2(1.2, -0.3)), 0.15, WAVE_HEIGHT * 0.35, CHOP, 0.22);
    w += gerstner(pos, normalize(vec2(0.3,  0.8)), 0.09, WAVE_HEIGHT * 0.18, CHOP, 0.18);
    return w;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv    = fragCoord / iResolution.xy;
    vec2 px    = 1.0 / iResolution.xy;
    float aspect = iResolution.x / iResolution.y;

    // ── Day cycle ─────────────────────────────────────────────────────────
    // phase: 0=midnight, 0.25=sunrise, 0.5=noon, 0.75=sunset, 1=midnight
    float phase    = fract(iTime / CYCLE_TIME);
    float sunAngle = phase * 6.28318 - 1.5708;  // sun arcs full circle
    vec2  sunPos   = vec2(cos(sunAngle) * 0.7 + 0.5, HORIZON * (0.12 + 0.84 * (1.0 - max(sin(sunAngle), 0.0))));
    float sunAbove = smoothstep(-0.05, 0.10, sin(sunAngle));  // 0=night, 1=day
    float sunset   = smoothstep(0.0, 0.18, sin(sunAngle)) * (1.0 - smoothstep(0.18, 0.55, sin(sunAngle)));
    float sunrise  = smoothstep(-0.05, 0.18, sin(sunAngle)) * (1.0 - smoothstep(0.18, 0.4, sin(sunAngle)));
    float goldHour = max(sunset, sunrise);

    // ── Sky palette ───────────────────────────────────────────────────────
    vec3 skyNight   = vec3(0.01, 0.02, 0.08);
    vec3 skyDay     = vec3(0.28, 0.52, 0.88);
    vec3 skyHorizon = vec3(0.55, 0.72, 0.95);
    vec3 skySunset  = vec3(0.92, 0.38, 0.08);
    vec3 skyDusk    = vec3(0.35, 0.14, 0.32);

    // Vertical sky gradient
    float skyT = smoothstep(HORIZON, HORIZON - 0.5, uv.y);
    vec3 skyBase = mix(skyHorizon, skyDay, skyT);
    skyBase = mix(skyNight, skyBase, sunAbove);

    // Golden hour wash near horizon
    float horizonGlow = smoothstep(0.25, 0.0, abs(uv.y - HORIZON - 0.02));
    skyBase = mix(skyBase, mix(skySunset, skyDusk, smoothstep(0.0, 1.0, phase > 0.5 ? (phase - 0.75) * 4.0 + 0.5 : 0.0)), goldHour * horizonGlow * 1.8);
    skyBase += skySunset * goldHour * horizonGlow * 0.6;

    // ── Sun disc ──────────────────────────────────────────────────────────
    float sunDist = length((uv - sunPos) * vec2(aspect, 1.0));
    float sunDisc = smoothstep(0.032, 0.018, sunDist);
    float sunHalo = exp(-sunDist * sunDist * 80.0) * 0.35;
    vec3  sunCol  = mix(vec3(1.0, 0.85, 0.45), vec3(1.0, 0.98, 0.88), sunAbove);
    skyBase += sunCol * (sunDisc + sunHalo) * sunAbove;

    // ── Moon — rises opposite sun, phase cycles over 4 days ──────────────
    float moonAngle = sunAngle + 3.14159;               // opposite sun
    vec2  moonPos   = vec2(cos(moonAngle) * 0.7 + 0.5, HORIZON * (0.12 + 0.84 * (1.0 - max(sin(moonAngle), 0.0))));
    float moonPhase = fract(iTime / (CYCLE_TIME * 4.0) + 0.5); // offset so we start at full moon
    float moonVis   = 1.0 - sunAbove;                   // fades with daylight

    if (moonVis > 0.01 && moonPos.y > 0.0 && moonPos.y < HORIZON) {
        float moonDist = length((uv - moonPos) * vec2(aspect, 1.0));
        float moonR    = 0.022;
        float moonDisc = smoothstep(moonR, moonR * 0.82, moonDist);  // sharp edge

        // Real sphere phase — sun direction relative to moon viewer
        // phase 0=new(behind), 0.25=first quarter, 0.5=full(facing), 0.75=last quarter
        float sunPhaseAngle = moonPhase * 6.28318;
        vec3  sunDir        = vec3(sin(sunPhaseAngle), 0.0, cos(sunPhaseAngle));
        // For this pixel, reconstruct 3D point on moon sphere
        vec2  moonLocal = (uv - moonPos) * vec2(aspect, 1.0) / moonR;
        float r2        = dot(moonLocal, moonLocal);
        float mz        = sqrt(max(1.0 - r2, 0.0));         // z of sphere surface
        vec3  moonSurf  = vec3(moonLocal, mz);               // point on unit sphere
        float lit       = dot(moonSurf, sunDir);             // positive = sunlit
        float phaseMask = smoothstep(-0.08, 0.08, lit);      // soft terminator

        // Surface shading — limb darkening + terminator glow
        float limb    = sqrt(max(mz, 0.0));
        // Occlude sky behind entire disc — dark side blocks stars
        skyBase *= (1.0 - moonDisc);
        // Lit face
        vec3  moonCol = vec3(0.88, 0.90, 0.78) * moonVis * limb;
        skyBase += moonCol * moonDisc * phaseMask;
        // Earthshine — very faint, just enough to show the disc is there
        skyBase += vec3(0.012, 0.016, 0.022) * moonDisc * (1.0 - phaseMask) * moonVis;
        // Halo
        skyBase += vec3(0.88, 0.90, 0.78) * 0.06 * exp(-moonDist * moonDist * 600.0) * moonVis;
    }

    // ── Moonlight glitter — computed here, applied after waterCol ────────
    float moonGlitter = 0.0;
    if (moonVis > 0.01 && sin(moonAngle) > 0.0) {
        float mGlitterX = abs(uv.x - moonPos.x) * aspect;
        moonGlitter = exp(-mGlitterX * mGlitterX * 10.0)
                    * smoothstep(HORIZON - 0.01, HORIZON + 0.01, uv.y)
                    * moonVis;
    }

    // ── Stars at night ────────────────────────────────────────────────────
    float nightness = 1.0 - sunAbove;
    if (nightness > 0.01 && uv.y < HORIZON) {

        // ── Shared projection constants ───────────────────────────────────
        const float LAT    = 0.7767;   // 44.5°N (Maine) in radians
        const float sinLAT = 0.7009;
        const float cosLAT = 0.7133;
        float lst = fract(iTime / CYCLE_TIME) * 6.28318; // LST 0–2π

        // ── Procedural background field — inverse projection into RA/Dec ──
        // For this pixel, find its RA/Dec, then hash nearby cells for stars.
        // All stars rotate correctly because they live in celestial coords.
        {
            float altFrac = 1.0 - uv.y / HORIZON;
            float alt0    = altFrac * 1.5708;
            float cosAlt0 = max(cos(alt0), 0.01);
            float sinAlt0 = sin(alt0);
            float spreadW = max(cos(alt0) * 0.50, 0.001);
            float sinAz0  = -(uv.x - 0.5) / spreadW;

            if (abs(sinAz0) < 0.999) {
                // Force southern sky: az=π at center, az=π/2(E) left, az=3π/2(W) right
                float az0  = 3.14159265 - asin(sinAz0);
                // Alt/az → Dec, H (full atan2 so H ∈ [-π, π])
                float sinD = sinAlt0 * sinLAT + cosAlt0 * cosLAT * cos(az0);
                float dec0 = asin(clamp(sinD, -1.0, 1.0));
                float cosD = max(cos(dec0), 0.001);
                float Hnum = -cosAlt0 * sin(az0);
                float Hden = sinAlt0 * cosLAT - cosAlt0 * sinLAT * cos(az0);
                float H0   = atan(Hnum, Hden);
                float ra0  = lst - H0;

                // Cellular hash in RA/Dec space — 3×3 neighborhood
                const float CS = 0.048; // cell size ~2.75°
                for (int ci = -1; ci <= 1; ci++) {
                for (int cj = -1; cj <= 1; cj++) {
                    vec2  cv   = floor(vec2(ra0, dec0) / CS) + vec2(ci, cj);
                    float hv   = fract(sin(dot(cv, vec2(127.1, 311.7))) * 43758.5);
                    if (hv < 0.78) continue; // ~22% of cells have a star
                    float ra_s  = (cv.x + 0.1 + fract(hv * 5.13) * 0.8) * CS;
                    float dec_s = (cv.y + 0.1 + fract(hv * 9.37) * 0.8) * CS;
                    float dRA   = ra0 - ra_s;
                    float dDec  = dec0 - dec_s;
                    float ang2  = dRA * dRA * cosD * cosD + dDec * dDec;
                    float stB   = (0.16 + fract(hv * 23.1) * 0.12) * nightness;
                    float stT   = 0.82 + 0.18 * sin(iTime * (0.4 + hv * 1.8) + hv * 17.3);
                    skyBase    += vec3(0.82, 0.87, 1.00) * exp(-ang2 * 160000.0) * stB * stT;
                }}
            }
        }

        // ── Named catalog stars — Yale BSC, mag < 2.2 ────────────────────
        // [RA_h, Dec_deg, mag, color: 0=white 1=orange 2=blue 3=yellow]

        // 50 brightest named stars
        // [RA_h, Dec_deg, mag, color: 0=white 1=orange 2=blue 3=yellow]
        vec4 cat[35];
        cat[ 0] = vec4( 6.75, -16.72, -1.46, 2.); // Sirius      blue-white
        cat[ 1] = vec4( 6.40, -52.70, -0.72, 2.); // Canopus     white
        cat[ 2] = vec4(14.26,  19.18, -0.04, 3.); // Arcturus    orange
        cat[ 3] = vec4(18.62,  38.78,  0.03, 2.); // Vega        blue-white
        cat[ 4] = vec4( 5.28,  46.00,  0.08, 3.); // Capella     yellow
        cat[ 5] = vec4( 5.24,  -8.20,  0.12, 2.); // Rigel       blue-white
        cat[ 6] = vec4( 7.65,   5.22,  0.34, 0.); // Procyon     white
        cat[ 7] = vec4( 1.63, -57.24,  0.46, 2.); // Achernar    blue-white
        cat[ 8] = vec4( 5.92,   7.41,  0.42, 1.); // Betelgeuse  orange-red
        cat[ 9] = vec4(14.07, -60.37,  0.61, 2.); // Hadar       blue
        cat[10] = vec4(19.85,   8.87,  0.76, 0.); // Altair      white
        cat[11] = vec4(12.45, -63.10,  0.77, 2.); // Acrux       blue
        cat[12] = vec4( 4.60,  16.51,  0.85, 1.); // Aldebaran   orange
        cat[13] = vec4(16.49, -26.43,  0.96, 1.); // Antares     orange-red
        cat[14] = vec4(13.42, -11.16,  0.97, 2.); // Spica       blue
        cat[15] = vec4( 7.75,  28.03,  1.14, 3.); // Pollux      orange
        cat[16] = vec4(22.96, -29.62,  1.16, 0.); // Fomalhaut   white
        cat[17] = vec4(12.80, -59.69,  1.25, 2.); // Mimosa      blue
        cat[18] = vec4(20.69,  45.28,  1.25, 2.); // Deneb       blue-white
        cat[19] = vec4(10.14,  11.97,  1.35, 2.); // Regulus     blue-white
        cat[20] = vec4( 6.98, -28.97,  1.50, 2.); // Adhara      blue
        cat[21] = vec4( 7.58,  31.89,  1.57, 0.); // Castor      white
        cat[22] = vec4(12.52, -57.11,  1.63, 1.); // Gacrux      orange
        cat[23] = vec4(17.56, -37.10,  1.63, 2.); // Shaula      blue
        cat[24] = vec4( 5.42,   6.35,  1.64, 2.); // Bellatrix   blue
        cat[25] = vec4( 5.44,  28.61,  1.65, 0.); // Elnath      white
        cat[26] = vec4( 9.22, -69.72,  1.68, 0.); // Miaplacidus white
        cat[27] = vec4( 5.60,  -1.20,  1.70, 2.); // Alnilam     blue
        cat[28] = vec4(22.08, -46.88,  1.74, 2.); // Alnair      blue
        cat[29] = vec4(12.90,  55.96,  1.76, 0.); // Alioth      white
        cat[30] = vec4( 5.68,  -1.94,  1.77, 2.); // Alnitak     blue
        cat[31] = vec4(11.06,  61.75,  1.79, 3.); // Dubhe       orange
        cat[32] = vec4( 3.41,  49.86,  1.79, 0.); // Mirfak      white
        cat[33] = vec4( 7.14, -26.39,  1.84, 3.); // Wezen       yellow
        cat[34] = vec4(18.40, -34.38,  1.85, 2.); // Kaus Aust.  blue
        // Keep Polaris in the 35
        cat[34] = vec4( 2.53,  89.26,  1.97, 3.); // Polaris     yellow

        for (int i = 0; i < 35; i++) {
            float ra_rad  = cat[i].x * 0.26180;   // hours → radians (*π/12)
            float dec_rad = cat[i].y * 0.01745;   // degrees → radians (*π/180)
            float mag     = cat[i].z;
            float ctype   = cat[i].w;

            // Hour angle and altitude/azimuth
            float H      = lst - ra_rad;
            float sinDec = sin(dec_rad), cosDec = cos(dec_rad);
            float sinH   = sin(H),       cosH   = cos(H);

            float sinAlt = sinDec * sinLAT + cosDec * cosLAT * cosH;
            float alt    = asin(clamp(sinAlt, -1.0, 1.0));
            if (alt < 0.02) continue;  // below horizon

            float cosAlt = cos(alt);
            float sinAz  = -cosDec * sinH / cosAlt;
            float cosAz  = (sinDec - sinAlt * sinLAT) / (cosAlt * cosLAT);
            float az     = atan(sinAz, cosAz);  // 0=N, π=S

            if (cosAz > 0.0) continue;  // northern sky — behind us, skip

            // Dome projection: spread ∝ cos(alt) — horizon wide, zenith clusters
            float altFrac = alt / 1.5708;
            float sY = HORIZON * (1.0 - altFrac);
            float sX = 0.5 - sin(az) * cos(alt) * 0.50;

            // Brightness from magnitude (lower = brighter)
            float bright = clamp((2.5 - mag) / 4.0, 0.0, 1.0) * nightness;

            // Color by spectral type
            vec3 starCol = ctype < 0.5 ? vec3(0.88, 0.92, 1.00)  // white
                         : ctype < 1.5 ? vec3(1.00, 0.65, 0.35)  // orange
                         : ctype < 2.5 ? vec3(0.75, 0.85, 1.00)  // blue-white
                         :               vec3(1.00, 0.95, 0.60);  // yellow

            float dist  = length((uv - vec2(sX, sY)) * vec2(aspect, 1.0));
            // Twinkle — slow irregular scintillation
            float fi2     = float(i) * 2.399;
            float tfreq   = 0.3 + float(i) * 0.071;
            float twinkle = 0.78
                          + 0.12 * sin(iTime * tfreq        + fi2)
                          + 0.07 * sin(iTime * tfreq * 2.73 + fi2 * 1.4)
                          + 0.03 * sin(iTime * tfreq * 5.11 + fi2 * 0.7);

            // Aspect-corrected offset for spike calc
            vec2  dA = vec2((uv.x - sX) * aspect, uv.y - sY);

            // Sharp disc edge like the sun, size scales with brightness
            float pointBright = min(bright, 0.55) * twinkle;
            float starR  = 0.0018 + pointBright * 0.0012;  // radius varies with mag
            float dist2  = length(dA);
            float point  = smoothstep(starR, starR * 0.5, dist2) * pointBright;
            float halo   = exp(-dist2 * dist2 * 6000.0) * pointBright * 0.04;

            // Diffraction spikes — 4-point lens cross
            float spikeH = exp(-dA.y*dA.y * 80000.0) * exp(-abs(dA.x) * 380.0);
            float spikeV = exp(-dA.x*dA.x * 80000.0) * exp(-abs(dA.y) * 380.0);
            float spikes = (spikeH + spikeV) * bright * twinkle * 0.18;
            skyBase += starCol * (point + halo + spikes);
        }
    }

    vec3 sky = skyBase;

    // ── Dynamic light direction ───────────────────────────────────────────
    vec3 L = normalize(vec3(cos(sunAngle) * 0.8, 0.6, max(sin(sunAngle), 0.1)));
    vec3 lightCol = mix(vec3(0.3, 0.15, 0.4), mix(sunCol, vec3(1.0, 0.98, 0.88), sunAbove), sunAbove);

    // ── Waves ─────────────────────────────────────────────────────────────
    vec2 pos   = vec2(uv.x * aspect * 3.0, uv.y * 3.0);
    vec3 surf  = oceanSurface(pos);
    float waveH  = surf.z;
    float horizon = HORIZON + waveH * 0.04;

    vec3 surfR = oceanSurface(pos + vec2(px.x * aspect * 3.0, 0.0));
    vec3 surfU = oceanSurface(pos + vec2(0.0, px.y * 3.0));
    vec2 grad  = vec2(surfR.z - waveH, surfU.z - waveH) * 40.0;
    vec3 N     = normalize(vec3(-grad, 1.0));

    // ── Terminal text ─────────────────────────────────────────────────────
    vec2 refractOffset = grad * REFRACT_STR * smoothstep(horizon - 0.06, horizon + 0.06, uv.y);
    float ch = 0.012;
    vec3 term = vec3(
        texture(iChannel0, clamp(uv + refractOffset * (1.0 - ch), 0.001, 0.999)).r,
        texture(iChannel0, clamp(uv + refractOffset,               0.001, 0.999)).g,
        texture(iChannel0, clamp(uv + refractOffset * (1.0 + ch), 0.001, 0.999)).b
    );
    float textL = luma(term);

    // ── Water color — tinted by sky/light ────────────────────────────────
    vec3 deepCol    = mix(vec3(0.01, 0.04, 0.06), vec3(0.02, 0.09, 0.10), sunAbove);
    vec3 shallowCol = mix(vec3(0.02, 0.09, 0.10), vec3(0.05, 0.18, 0.14), sunAbove);
    deepCol    = mix(deepCol,    vec3(0.18, 0.06, 0.04), goldHour * 0.5);
    shallowCol = mix(shallowCol, vec3(0.28, 0.14, 0.06), goldHour * 0.4);

    float depthFade = smoothstep(horizon, horizon - 0.3, uv.y);
    vec3  waterCol  = mix(shallowCol, deepCol, depthFade);

    // ── Specular ──────────────────────────────────────────────────────────
    vec3  H    = normalize(L + vec3(0.0, 0.0, 1.0));
    float spec = pow(max(dot(N, H), 0.0), 120.0) * length(grad) * 8.0;
    waterCol  += lightCol * spec * mix(0.3, 0.9, sunAbove);

    // ── Sun glitter — perspective correct, narrows to point at horizon ────
    float glitterX    = abs(uv.x - sunPos.x) * aspect;
    float distFromHor = max(uv.y - horizon, 0.001);   // deeper = wider path
    float perspWidth  = 14.0 / (distFromHor * 18.0 + 0.8);
    float pathMask    = exp(-glitterX * glitterX * perspWidth) * smoothstep(horizon + 0.01, horizon - 0.01, uv.y);
    vec3  sunRefl     = normalize(vec3(sunPos - uv, 0.5));
    float facetCatch  = pow(max(dot(N, normalize(sunRefl + vec3(0.0, 0.0, 1.0))), 0.0), 60.0);
    waterCol += sunCol * pathMask * facetCatch * sunAbove * 2.5;

    // ── Moonlight on water ────────────────────────────────────────────────
    waterCol += vec3(0.55, 0.60, 0.50) * moonGlitter * 0.4 * (0.5 + 0.5 * dot(N, normalize(vec3(cos(moonAngle), 0.3, sin(moonAngle)))));

    // ── Foam ──────────────────────────────────────────────────────────────
    float foam = smoothstep(0.55, 0.85, waveH) * FOAM_STR;
    vec3 foamCol = mix(vec3(0.75, 0.65, 0.55), vec3(0.85, 0.92, 0.96), sunAbove);
    waterCol = mix(waterCol, foamCol, foam);

    // ── Fresnel reflection of sky ─────────────────────────────────────────
    float fresnel = pow(1.0 - max(dot(N, vec3(0.0, 0.0, 1.0)), 0.0), 3.0);
    waterCol = mix(waterCol, sky * 0.7, fresnel * 0.45);

    // ── Fish school — silhouettes in the water ────────────────────────────
    float fishShadow = 0.0;
    if (uv.y > horizon) for (int i = 0; i < NUM_FISH; i++) {
        vec2  fUV  = vec2((float(i) + 0.5) / iResolution.x, 0.5 / iResolution.y);
        vec4  fSt  = texture(iChannel2, fUV);
        vec2  fPos = fSt.rg;
        vec2  fVel = fSt.ba;

        if (fPos.y < HORIZON + 0.01) continue;  // uninitialized

        // Fish-local coordinate space
        // Aspect-correct both d and the heading so nose points where fish moves
        vec2  d    = vec2((uv.x - fPos.x) * aspect, uv.y - fPos.y);
        vec2  headScreen = length(fVel) > 0.00001
                         ? normalize(vec2(fVel.x * aspect, fVel.y))
                         : vec2(1.0, 0.0);
        float bodyL = 0.011;
        // Tail at fPos — body extends forward: shift lx so lx=0 is mid-body
        float lx   = ( d.x * headScreen.x + d.y * headScreen.y) - bodyL;
        float ly   = (-d.x * headScreen.y + d.y * headScreen.x);

        // Tapered body: wide at shoulder, pointed at nose and tail
        float taper = smoothstep(bodyL * 0.6, -bodyL * 0.8, lx);  // fatter toward front
        float bodyW = 0.0018 + taper * 0.0014;
        float fishD = length(vec2(lx / bodyL, ly / bodyW));
        fishShadow = max(fishShadow, smoothstep(1.0, 0.7, fishD));
    }

    // Shadow: subtle silhouette
    vec3 shadowCol = waterCol * 0.35 + vec3(0.01, 0.02, 0.04);
    waterCol = mix(waterCol, shadowCol, fishShadow * 0.45);

    // ── Composite ─────────────────────────────────────────────────────────
    float surfMask = smoothstep(horizon + 0.01, horizon - 0.01, uv.y);
    vec3  color    = mix(waterCol, sky, surfMask);
    float textAlpha = textL * mix(0.5, 1.0, surfMask);
    color = mix(color, term + color * 0.2, textAlpha * 0.9);

    // ── Depth haze — Beer-Lambert extinction + scatter, like ripple ──────────
    if (uv.y > horizon) {
        float depth = (uv.y - horizon) / (1.0 - horizon);  // 0=surface, 1=bottom

        // Per-channel extinction: R absorbed first, B last → warm→cool with depth
        vec3  sigma = vec3(2.4, 1.4, 0.7) * mix(0.6, 1.0, sunAbove);
        vec3  T     = exp(-sigma * depth * depth);  // transmittance

        // Scatter veil: grows with depth, tinted by water color
        float scatter  = 1.0 - exp(-4.0 * depth * depth);
        vec3  veilCol  = mix(shallowCol, deepCol, depth) * mix(0.3, 0.15, sunAbove);
        veilCol        = mix(veilCol, vec3(0.18, 0.06, 0.04) * 0.3, goldHour * 0.5);

        color = color * T + veilCol * scatter;

        // ── Fish shadow god rays — shadow cones descend from each fish ────
        // Light leans slightly toward sun; contrast with clear water = rays
        float fishOcclusion = 0.0;
        for (int i = 0; i < NUM_FISH; i++) {
            vec2  fUV  = vec2((float(i) + 0.5) / iResolution.x, 0.5 / iResolution.y);
            vec4  fSt  = texture(iChannel2, fUV);
            vec2  fPos = fSt.rg;
            vec2  fVel = fSt.ba;
            if (fPos.y < HORIZON + 0.01) continue;
            if (uv.y <= fPos.y + 0.005) continue;

            float d    = uv.y - fPos.y;
            float lean = (sunPos.x - 0.5) * d * 0.4 * sunAbove;

            // Project fragment back up to fish depth along sun direction
            vec2 proj = vec2(uv.x - lean, fPos.y);

            // Fish SDF at projected point — same as render
            vec2  dp   = vec2((proj.x - fPos.x) * aspect, proj.y - fPos.y);
            float bodyL = 0.011;
            vec2  headS = length(fVel) > 0.00001
                        ? normalize(vec2(fVel.x * aspect, fVel.y)) : vec2(1.0, 0.0);
            float lx    = ( dp.x * headS.x + dp.y * headS.y) - bodyL;
            float ly    = (-dp.x * headS.y + dp.y * headS.x);
            float taper = smoothstep(bodyL * 0.6, -bodyL * 0.8, lx);
            float bodyW = 0.0018 + taper * 0.0014;
            float fishD = length(vec2(lx / bodyL, ly / bodyW));

            // Core shadow (fish shape) + soft penumbra that spreads with depth
            float core     = smoothstep(1.3, 0.7, fishD);
            float penumbra = exp(-fishD * fishD / (0.8 + d * 4.0));  // widens with depth
            float shadow   = max(core, penumbra * 0.5) * exp(-d * 2.8);
            fishOcclusion = max(fishOcclusion, shadow);
        }
        color = mix(color, color * 0.55, fishOcclusion * 0.38 * sunAbove);
    }

    // ── Focus dim ─────────────────────────────────────────────────────────
    float focusT   = clamp((iTime - iTimeFocus) * 1.5, 0.0, 1.0);
    float focusMix = iFocus == 1 ? focusT : 1.0 - focusT;
    vec3  grey     = vec3(luma(color));
    color = mix(grey, color, mix(0.3, 1.0, focusMix)) * mix(0.55, 1.0, focusMix);

    fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
