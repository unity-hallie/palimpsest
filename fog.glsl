// fog.glsl -- layered mist drifting over terminal text
//
// No compute. No loops. Just stacked noise planes at different
// drift speeds. Text stays readable -- fog sits behind and between.
//
// iChannel0 = terminal content

// -- Tuning ----------------------------------------------------------
#define FOG_SPEED     0.02
#define BG_COLOR      vec3(0.04, 0.05, 0.07)
// --------------------------------------------------------------------

float hash2(vec2 p) {
    p = fract(p * vec2(127.1, 311.7));
    p += dot(p, p.yx + 19.19);
    return fract(p.x * p.y);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash2(i);
    float b = hash2(i + vec2(1.0, 0.0));
    float c = hash2(i + vec2(0.0, 1.0));
    float d = hash2(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// 3-octave fbm
float fbm3(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 3; i++) { v += a * noise(p); p *= 2.1; a *= 0.5; }
    return v;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    // -- Terminal -------------------------------------------------
    vec4 termRaw = texture(iChannel0, uv);
    vec3 term = termRaw.rgb;
    float textLuma = dot(term, vec3(0.299, 0.587, 0.114));
    float distFromBg = length(term - BG_COLOR);
    float textMask = smoothstep(0.03, 0.14, distFromBg);
    textMask = max(textMask, smoothstep(0.06, 0.20, textLuma));

    // -- Fog layers -----------------------------------------------
    float t = iTime * FOG_SPEED;

    // Three layers at different scales and speeds for parallax
    float f0 = fbm3(uv * vec2(3.0, 2.0) + vec2(t * 0.7, t * 0.05));
    float f1 = fbm3(uv * vec2(5.0, 3.0) + vec2(t * 1.4 + 3.7, -t * 0.15));
    float f2 = fbm3(uv * vec2(8.0, 4.0) + vec2(t * 2.2 + 7.2, t * 0.2));

    // Combine with contrast: subtract 0.3 center, scale up, clamp
    // This makes fog patchy -- clear holes and dense banks
    float fog = f0 * 0.5 + f1 * 0.3 + f2 * 0.2;
    fog = clamp((fog - 0.25) * 3.0, 0.0, 1.0);

    // Fog is additive light -- mist scatters ambient
    vec3 fogTint = vec3(0.35, 0.40, 0.50);
    vec3 color = BG_COLOR + fogTint * fog * 0.35;

    // Vignette
    vec2 vc = uv - 0.5;
    color *= 1.0 - dot(vc, vc) * 0.5;

    // -- Text on top ----------------------------------------------
    color = mix(color, term, textMask);

    // -- Focus dim ------------------------------------------------
    float focusT   = clamp((iTime - iTimeFocus) * 1.5, 0.0, 1.0);
    float focusMix = iFocus == 1 ? focusT : 1.0 - focusT;
    float grey     = dot(color, vec3(0.299, 0.587, 0.114));
    color = mix(vec3(grey), color, mix(0.3, 1.0, focusMix)) * mix(0.55, 1.0, focusMix);

    fragColor = vec4(clamp(color, 0.0, 1.0), termRaw.a);
}
