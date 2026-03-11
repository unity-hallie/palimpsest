// putty.glsl — silly putty over terminal
//
// iChannel0 = terminal
// iChannel2 = putty state (R=density, G=velX, B=velY, A=stress)

// ── Tuning ────────────────────────────────────────────────────────────────────
#define PUTTY_OPACITY   0.82
#define REFRACTION      0.018
#define IRID_STRENGTH   0.45
#define SPECULAR        0.60
#define DEPTH_DARK      0.35
// ─────────────────────────────────────────────────────────────────────────────

float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

// Thin-film iridescence: stress + gradient angle → hue
vec3 iridescence(float hue, float strength) {
    vec3 c = clamp(abs(fract(hue + vec3(0.0, 1.0/3.0, 2.0/3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
    return mix(vec3(1.0), c, strength);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec2 px = 1.0 / iResolution.xy;

    vec4  state   = texture(iChannel2, uv);
    float density = state.r;
    vec2  vel     = state.gb;
    float stress  = state.a;

    // ── Density gradient for surface normal ───────────────────────────────
    float dL = texture(iChannel2, uv + vec2(-px.x, 0)).r;
    float dR = texture(iChannel2, uv + vec2( px.x, 0)).r;
    float dU = texture(iChannel2, uv + vec2(0, -px.y)).r;
    float dD = texture(iChannel2, uv + vec2(0,  px.y)).r;
    vec2 densGrad = vec2(dR - dL, dD - dU);
    vec3 normal = normalize(vec3(-densGrad * 6.0, 1.0));

    // ── Refraction — text smears through putty ────────────────────────────
    vec2 refractUV = uv + densGrad * REFRACTION * density;
    vec3 term = texture(iChannel0, clamp(refractUV, 0.001, 0.999)).rgb;
    float textL = luma(term);

    // ── Flesh base color — warm pinkish beige ────────────────────────────
    vec3 fleshLo = vec3(0.88, 0.68, 0.58);  // shadowed flesh
    vec3 fleshHi = vec3(0.97, 0.84, 0.76);  // lit flesh
    vec3 fleshColor = mix(fleshLo, fleshHi, smoothstep(0.2, 0.8, density));

    // ── Depth darkening in thick areas ───────────────────────────────────
    fleshColor *= 1.0 - density * DEPTH_DARK;

    // ── Iridescence — thin film shimmer on surface ────────────────────────
    float iridHue = fract(atan(densGrad.y, densGrad.x) / 6.2832 + stress * 0.5 + 0.5);
    float iridMask = smoothstep(0.02, 0.15, length(densGrad)) * density;
    vec3 iridColor = iridescence(iridHue, IRID_STRENGTH);
    fleshColor = mix(fleshColor, fleshColor * iridColor, iridMask * 0.6);

    // ── Specular highlight ────────────────────────────────────────────────
    vec3 lightDir = normalize(vec3(0.4, 0.7, 1.0));
    float spec = pow(max(dot(normal, lightDir), 0.0), 24.0) * SPECULAR;
    fleshColor += vec3(1.0, 0.95, 0.90) * spec * density;

    // ── Composite — text shows through thin putty ─────────────────────────
    float alpha = smoothstep(0.05, 0.45, density) * PUTTY_OPACITY;
    vec3 color = mix(term, fleshColor, alpha);

    // ── Focus dim ─────────────────────────────────────────────────────────
    float focusT = clamp((iTime - iTimeFocus) * 1.5, 0.0, 1.0);
    float focusMix = iFocus == 1 ? focusT : 1.0 - focusT;
    float dimAmount = mix(0.55, 1.0, focusMix);
    float satAmount = mix(0.3,  1.0, focusMix);
    vec3 grey = vec3(luma(color));
    color = mix(grey, color, satAmount) * dimAmount;

    fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
