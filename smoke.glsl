// smoke.glsl — volumetric smoke with energy glow + bisexual edge lighting
//
// iChannel0 = terminal content
// iChannel2 = smoke state (R=density, G=velX, B=velY, A=smoothed energy)

// ── Tuning ────────────────────────────────────────────────────────────────────
#define NEON_STRENGTH   1.1
#define RAY_STRENGTH    2.5
#define HEAT_GLOW       2.8
#define HEAT_COLOR_LO   vec3(0.04, 0.12, 0.55)
#define HEAT_COLOR_HI   vec3(0.30, 0.60, 1.00)
#define SMOKE_NEON      1.2
#define SMOKE_OPACITY   0.40
#define VIGNETTE        0.00
#define MOON_BRIGHTNESS 0.5
#define MOON_SIZE       0.10
// ─────────────────────────────────────────────────────────────────────────────

float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

float hash11(float p) {
    return fract(sin(p * 127.1) * 43758.5453);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    // ── Compute state ─────────────────────────────────────────────────────
    vec4 smokeState = texture(iChannel2, uv);
    float density = smokeState.r;
    float energy  = smokeState.a;  // smoothed in compute, flicker-free

    // ── Terminal text ─────────────────────────────────────────────────────
    vec3 term = texture(iChannel0, uv).rgb;
    float textBright = luma(term);

    // ── Bisexual edge neon ────────────────────────────────────────────────
    float launchSeed = iResolution.x * 7.13 + iResolution.y * 3.71;
    float baseAngle  = hash11(launchSeed) * 6.2832;
    float hueShift   = hash11(launchSeed * 2.37) * 0.3 - 0.15;

    vec3 neonA = vec3(0.85 + hueShift, 0.20, 0.55 - hueShift);
    vec3 neonB = vec3(0.15, 0.55 + hueShift, 0.75 - hueShift);

    vec2 center = uv - 0.5;
    float edgeDist = 1.0 - 2.0 * max(abs(center.x), abs(center.y));
    float edgeMask = smoothstep(0.5, 0.0, edgeDist);

    float fallA = max(dot(center, vec2(cos(baseAngle), sin(baseAngle))), 0.0) * edgeMask;
    float fallB = max(dot(center, vec2(cos(baseAngle + 3.14), sin(baseAngle + 3.14))), 0.0) * edgeMask;
    vec3 neonColor = neonA * fallA + neonB * fallB;

    // ── Moon with accurate phase ──────────────────────────────────────────
    // Position: slow drift, per-terminal placement
    float moonSeed = hash11(launchSeed * 3.91);
    vec2 moonPos = vec2(0.15 + moonSeed * 0.7, 0.75 + moonSeed * 0.15);
    moonPos += vec2(sin(iTime * 0.003), cos(iTime * 0.002)) * 0.02;

    // Soft glowing disc with radial falloff
    float aspect = iResolution.x / iResolution.y;
    float moonDist = length((uv - moonPos) * vec2(aspect, 1.0));
    float disc = smoothstep(MOON_SIZE, 0.0, moonDist); // soft radial glow
    float core = smoothstep(MOON_SIZE * 0.5, 0.0, moonDist); // bright center
    float moonMask = mix(disc * 0.5, 1.0, core); // halo + bright core

    // Warm moonlight, hazed by smoke
    vec3 moonColor = vec3(0.9, 0.85, 0.7) * MOON_BRIGHTNESS;
    float moonHaze = 1.0 - density * 0.6;

    // ── Text dimmed by scattering ─────────────────────────────────────────
    float scatter = density * textBright;
    vec3 color = term * (1.0 - scatter * 0.4);
    // Boost text contrast so it reads through smoke
    color += term * textBright * 0.6;

    // ── Gaussian neon haze — soft bloom beyond the smoke body ─────────────
    vec2 px = 1.0 / iResolution.xy;
    float r1 = 4.0, r2 = 9.0;
    float hazeDensity =
        density                                                            * 0.30 +
        texture(iChannel2, uv + vec2( r1,  0.0) * px).r                   * 0.12 +
        texture(iChannel2, uv + vec2(-r1,  0.0) * px).r                   * 0.12 +
        texture(iChannel2, uv + vec2( 0.0,  r1) * px).r                   * 0.12 +
        texture(iChannel2, uv + vec2( 0.0, -r1) * px).r                   * 0.12 +
        texture(iChannel2, uv + vec2( r2,  r2 ) * px).r                   * 0.04 +
        texture(iChannel2, uv + vec2(-r2,  r2 ) * px).r                   * 0.04 +
        texture(iChannel2, uv + vec2( r2, -r2 ) * px).r                   * 0.04 +
        texture(iChannel2, uv + vec2(-r2, -r2 ) * px).r                   * 0.04;

    // ── Smoke: neon haze + text scatter + energy heat ────────────────────
    vec3 smokeColor = neonColor * hazeDensity * SMOKE_NEON;
    // Text light scattered into smoke
    smokeColor += term * density * textBright * 0.2;
    // Energy heat glow — ember to warm white, smooth and stable
    float h = smoothstep(0.0, 0.6, energy);
    vec3 heatTint = mix(HEAT_COLOR_LO, HEAT_COLOR_HI, h);
    smokeColor += heatTint * density * energy * HEAT_GLOW;

    // ── God rays — text light shafting through smoke ──────────────────────
    vec3 godRays = vec3(0.0);
    float rayStep = 0.026;
    float rayDecay = 0.84;
    for (int i = 0; i < 12; i++) {
        float angle = float(i) * 0.5236; // 30° apart
        vec2 dir = vec2(cos(angle), sin(angle));
        float w = 1.0;
        for (int j = 1; j <= 6; j++) {
            vec2 sUV = clamp(uv + dir * float(j) * rayStep, 0.001, 0.999);
            float sBright = luma(texture(iChannel0, sUV).rgb);
            float sDens   = texture(iChannel2, sUV).r;
            godRays += neonColor * sBright * sDens * w;
            w *= rayDecay;
        }
    }
    godRays /= 72.0;

    // ── Background layers (behind smoke) ────────────────────────────────
    color += moonColor * moonMask * moonHaze;
    color += neonColor * NEON_STRENGTH * 0.12;

    // ── Smoke absorption — thick smoke darkens background ────────────────
    float absorption = smoothstep(0.2, 0.9, density);
    color *= 1.0 - absorption * 0.42;

    // ── Scatter neon back through the haze (backlit volumetric) ──────────
    float fog = smoothstep(0.05, 0.7, hazeDensity) * SMOKE_OPACITY;
    color = mix(color, smokeColor, fog);
    color += godRays * RAY_STRENGTH;

    // ── Focus dim ─────────────────────────────────────────────────────────
    float focusT = clamp((iTime - iTimeFocus) * 1.5, 0.0, 1.0);
    float focusMix = iFocus == 1 ? focusT : 1.0 - focusT;
    float dimAmount = mix(0.55, 1.0, focusMix);
    float satAmount = mix(0.3, 1.0, focusMix);
    vec3 grey = vec3(luma(color));
    color = mix(grey, color, satAmount) * dimAmount;

    // ── Vignette ──────────────────────────────────────────────────────────
    color *= 1.0 - VIGNETTE * dot(uv - 0.5, uv - 0.5);

    fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
