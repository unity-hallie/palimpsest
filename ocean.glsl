// ocean.glsl — rolling ocean swells with day/night cycle
//
// iChannel0 = terminal content
// No compute needed — Gerstner waves are analytic.

// ── Tuning ────────────────────────────────────────────────────────────────────
#define HORIZON      0.28     // where ocean meets sky (0=bottom, 1=top)
#define WAVE_HEIGHT  0.018    // swell amplitude
#define CHOP         0.55     // steepness / choppiness
#define FOAM_STR     0.55     // whitecap brightness
#define REFRACT_STR  0.022    // text distortion through surface
#define CYCLE_TIME   600.0    // seconds per full day (10 min)
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
    vec2  sunPos   = vec2(cos(sunAngle) * 0.7 + 0.5, HORIZON - sin(sunAngle) * 0.5);
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

    // ── Stars at night — rotate around pole star (top-center) ────────────
    float nightness = 1.0 - sunAbove;
    if (nightness > 0.01 && uv.y < HORIZON) {
        float starAngle = iTime / CYCLE_TIME * 6.28318; // one full rotation per day
        vec2  pole      = vec2(0.5, 0.0);               // pole star at top-center
        vec2  d         = uv - pole;
        float c = cos(starAngle), s = sin(starAngle);
        vec2  rotUV     = pole + vec2(d.x*c - d.y*s, d.x*s + d.y*c);
        vec2  starUV    = rotUV * vec2(aspect * 60.0, 60.0);
        vec2  starCell  = floor(starUV);
        vec2  starFrac  = fract(starUV);
        float h = fract(sin(dot(starCell, vec2(127.1, 311.7))) * 43758.5);
        if (h > 0.88) {
            float star = exp(-length(starFrac - 0.5) * length(starFrac - 0.5) * 120.0);
            skyBase += vec3(0.8, 0.85, 1.0) * star * nightness * fract(h * 17.3);
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
    vec3 deepCol    = mix(vec3(0.01, 0.03, 0.10), vec3(0.02, 0.08, 0.18), sunAbove);
    vec3 shallowCol = mix(vec3(0.02, 0.06, 0.18), vec3(0.04, 0.22, 0.32), sunAbove);
    deepCol    = mix(deepCol,    vec3(0.18, 0.06, 0.04), goldHour * 0.5);
    shallowCol = mix(shallowCol, vec3(0.28, 0.14, 0.06), goldHour * 0.4);

    float depthFade = smoothstep(horizon, horizon - 0.3, uv.y);
    vec3  waterCol  = mix(shallowCol, deepCol, depthFade);

    // ── Specular ──────────────────────────────────────────────────────────
    vec3  H    = normalize(L + vec3(0.0, 0.0, 1.0));
    float spec = pow(max(dot(N, H), 0.0), 120.0) * length(grad) * 8.0;
    waterCol  += lightCol * spec * mix(0.3, 0.9, sunAbove);

    // ── Sun glitter — wave facets reflecting sun toward viewer ───────────
    float glitterX  = abs(uv.x - sunPos.x) * aspect;
    float pathMask  = exp(-glitterX * glitterX * 10.0) * smoothstep(horizon + 0.01, horizon - 0.01, uv.y);
    vec3  sunRefl   = normalize(vec3(sunPos - uv, 0.5));
    float facetCatch = pow(max(dot(N, normalize(sunRefl + vec3(0.0, 0.0, 1.0))), 0.0), 60.0);
    waterCol += sunCol * pathMask * facetCatch * sunAbove * 2.5;

    // ── Foam ──────────────────────────────────────────────────────────────
    float foam = smoothstep(0.55, 0.85, waveH) * FOAM_STR;
    vec3 foamCol = mix(vec3(0.75, 0.65, 0.55), vec3(0.85, 0.92, 0.96), sunAbove);
    waterCol = mix(waterCol, foamCol, foam);

    // ── Fresnel reflection of sky ─────────────────────────────────────────
    float fresnel = pow(1.0 - max(dot(N, vec3(0.0, 0.0, 1.0)), 0.0), 3.0);
    waterCol = mix(waterCol, sky * 0.7, fresnel * 0.45);

    // ── Composite ─────────────────────────────────────────────────────────
    float surfMask = smoothstep(horizon + 0.01, horizon - 0.01, uv.y);
    vec3  color    = mix(waterCol, sky, surfMask);
    float textAlpha = textL * mix(0.5, 1.0, surfMask);
    color = mix(color, term + color * 0.2, textAlpha * 0.9);

    // ── Focus dim ─────────────────────────────────────────────────────────
    float focusT   = clamp((iTime - iTimeFocus) * 1.5, 0.0, 1.0);
    float focusMix = iFocus == 1 ? focusT : 1.0 - focusT;
    vec3  grey     = vec3(luma(color));
    color = mix(grey, color, mix(0.3, 1.0, focusMix)) * mix(0.55, 1.0, focusMix);

    fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
