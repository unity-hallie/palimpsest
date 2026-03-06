// smoke.glsl — volumetric neon smoke with fluid sim
//
// iChannel0 = terminal content
// iChannel1 = feedback buffer (previous frame)
// iChannel2 = smoke state (R=density, G=velX, B=velY, from smoke.compute.msl)
//
// Smoke composites as a translucent fog OVER sharp text.
// Text is never blurred — legibility is sacred.
// Smoke catches and scatters nearby neon light that drifts with the fluid.

// ── Tuning ────────────────────────────────────────────────────────────────────
#define SMOKE_OPACITY   0.85     // max fog opacity over text (wisps, not blanket)
#define SMOKE_GLOW      1.0      // smoke self-illumination from neon
#define NEON_STRENGTH   1.25     // offscreen neon sign brightness
#define REFRACT_STR     0.001    // velocity-based text distortion
#define VIGNETTE        0.15     // edge darkening
// ─────────────────────────────────────────────────────────────────────────────

float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

float hash11(float p) {
    return fract(sin(p * 127.1) * 43758.5453);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec2 px = 1.0 / iResolution.xy;

    // ── Smoke state from compute shader ─────────────────────────────────────
    vec4 smokeState = texture(iChannel2, uv);
    float density = smokeState.r;
    vec2  vel     = smokeState.gb;


    // ── Terminal text (sharp, no refraction — keeps edges clean) ─────────────
    vec3 term = texture(iChannel0, uv).rgb;

    // ── Neon sign lighting — drifts with smoke velocity field ───────────────
    // Seed per-terminal, but animate the angle with accumulated velocity
    float launchSeed = iResolution.x * 7.13 + iResolution.y * 3.71;
    float baseAngle  = hash11(launchSeed) * 6.2832;
    float neonHue    = hash11(launchSeed * 3.71 + 1.0);

    // Bisexual lighting: warm vs cool, hue-shifted per terminal
    float hueShift = hash11(launchSeed * 2.37) * 0.3 - 0.15;  // ±0.15 hue drift
    vec3 neonA = vec3(0.85 + hueShift, 0.20, 0.55 - hueShift);  // warm side
    vec3 neonB = vec3(0.15, 0.55 + hueShift, 0.75 - hueShift);  // cool side

    // Edge glow — rotated per terminal so each window gets a unique angle
    // Project UV onto the neon axis (seeded from resolution)
    vec2 center = uv - 0.5;
    vec2 axisA = vec2(cos(baseAngle), sin(baseAngle));
    vec2 axisB = vec2(cos(baseAngle + 3.14), sin(baseAngle + 3.14));

    // Edge proximity: how close to the border along each axis direction
    float edgeDist = 1.0 - 2.0 * max(abs(center.x), abs(center.y));  // 0 at edge, 1 at center
    float edgeMask = smoothstep(0.5, 0.0, edgeDist);  // glow near edges

    float fallA = max(dot(center, axisA), 0.0) * edgeMask;
    float fallB = max(dot(center, axisB), 0.0) * edgeMask;

    vec3 neonColor = neonA * fallA + neonB * fallB;
    float neonTotal = fallA + fallB;

    // ── Fog color: smoke lit by neon + self-luminous haze ────────────────────
    vec3 fogBase = vec3(0.06, 0.06, 0.09);
    // Smoke always faintly visible — cool gray-violet self-glow
    vec3 smokeGlow = vec3(0.12, 0.11, 0.16) * density;
    vec3 fogLit  = fogBase + smokeGlow
                           + neonColor * NEON_STRENGTH
                           + neonColor * density * SMOKE_GLOW;

    // ── Composite: sharp text behind translucent smoke fog ──────────────────
    float fog = smoothstep(0.0, 0.5, density) * SMOKE_OPACITY;

    // Text brightened slightly so it reads through fog
    vec3 tintedText = term * (1.0 + fog * 0.3) + neonColor * fog * 0.05;

    // Layer fog over text
    vec3 color = mix(tintedText, fogLit, fog);

    // Edge neon always visible — not gated by smoke
    color += neonColor * NEON_STRENGTH * 0.15;

    // ── Smoke catches text light ────────────────────────────────────────────
    // Use overall screen text density as a proxy — no spatial sampling needed
    // The feedback buffer center pixel is a good average of the whole screen
    float screenBright = luma(texture(iChannel1, vec2(0.5)).rgb);
    color += vec3(0.55, 0.75, 0.70) * density * screenBright * 4.0;

    // ── Vignette ────────────────────────────────────────────────────────────
    color *= 1.0 - VIGNETTE * dot(uv - 0.5, uv - 0.5);

    fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
