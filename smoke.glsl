// smoke.glsl — volumetric smoke with smoothed energy glow + bisexual edge lighting
//
// iChannel0 = terminal content
// iChannel2 = smoke state (R=density, G=velX, B=velY, A=smoothed energy)

// ── Tuning ────────────────────────────────────────────────────────────────────
#define NEON_STRENGTH   1.25
#define HEAT_GLOW       1.9
#define SMOKE_NEON      0.8
#define SMOKE_OPACITY   0.25
#define VIGNETTE        0.00
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

    // ── Text dimmed by scattering ─────────────────────────────────────────
    float scatter = density * textBright;
    vec3 color = term * (1.0 - scatter * 0.4);

    // ── Smoke: neon + text scatter + energy heat ──────────────────────────
    vec3 smokeColor = neonColor * density * SMOKE_NEON;
    // Text light scattered into smoke
    smokeColor += term * density * textBright * 0.2;
    // Energy heat glow — ember to warm white, smooth and stable
    float h = smoothstep(0.0, 0.6, energy);
    vec3 heatTint = mix(vec3(0.6, 0.2, 0.05), vec3(1.0, 0.75, 0.45), h);
    smokeColor += heatTint * density * energy * HEAT_GLOW;

    // ── Edge neon wash (base layer, under smoke) ────────────────────────
    color += neonColor * NEON_STRENGTH * 0.10;

    // ── Composite smoke over everything ───────────────────────────────────
    float fog = smoothstep(0.0, 0.4, density) * SMOKE_OPACITY;
    color = mix(color, smokeColor, fog);

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
