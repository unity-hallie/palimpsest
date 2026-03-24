// tide.glsl -- caustic light bands on a cave ceiling
//
// No compute. Horizontal bands of refracted light that breathe
// up and down, like sunlight through shallow water hitting stone.
// Cheap: two noise calls for the wave surface, one for texture.
//
// iChannel0 = terminal content

// -- Tuning ----------------------------------------------------------
#define WAVE_SPEED    0.04
#define BAND_SCALE    3.0
#define CAUSTIC_STR   0.45
#define BG_COLOR      vec3(0.04, 0.04, 0.06)
#define LIGHT_COLOR   vec3(0.25, 0.38, 0.42)
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

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    // -- Terminal -------------------------------------------------
    vec4 termRaw = texture(iChannel0, uv);
    vec3 term = termRaw.rgb;
    float textLuma = dot(term, vec3(0.299, 0.587, 0.114));
    float distFromBg = length(term - BG_COLOR);
    float textMask = smoothstep(0.03, 0.14, distFromBg);
    textMask = max(textMask, smoothstep(0.06, 0.20, textLuma));

    // -- Caustic bands --------------------------------------------
    // Simulate refracted light: two wave layers create interference
    float t = iTime * WAVE_SPEED;
    vec2 waveUV = uv * BAND_SCALE;

    // Two wave surfaces at different angles and speeds
    float w1 = noise(vec2(waveUV.x * 2.0 + t * 0.7, waveUV.y * 0.8 + t * 0.3));
    float w2 = noise(vec2(waveUV.x * 1.5 - t * 0.5, waveUV.y * 1.2 + t * 0.6 + 5.0));

    // Caustic = where waves focus light (peaks of interference)
    float surface = w1 * 0.6 + w2 * 0.4;
    // Sharp bright bands where waves constructively interfere
    float caustic = pow(surface, 2.0) * 3.0;
    caustic = clamp(caustic, 0.0, 1.0);

    // Subtle horizontal bias -- bands tend to run across the screen
    // like real underwater caustics on a ceiling
    float hBias = noise(vec2(uv.x * 1.5 + t * 0.2, uv.y * 6.0 - t * 0.4));
    caustic *= 0.6 + 0.4 * hBias;

    // -- Color ----------------------------------------------------
    vec3 color = BG_COLOR + LIGHT_COLOR * caustic * CAUSTIC_STR;

    // Slight warmth in the bright bands
    color += vec3(0.08, 0.03, 0.0) * caustic * CAUSTIC_STR;

    // -- Text on top ----------------------------------------------
    color = mix(color, term, textMask);

    // -- Focus dim ------------------------------------------------
    float focusT   = clamp((iTime - iTimeFocus) * 1.5, 0.0, 1.0);
    float focusMix = iFocus == 1 ? focusT : 1.0 - focusT;
    float grey     = dot(color, vec3(0.299, 0.587, 0.114));
    color = mix(vec3(grey), color, mix(0.3, 1.0, focusMix)) * mix(0.55, 1.0, focusMix);

    fragColor = vec4(clamp(color, 0.0, 1.0), termRaw.a);
}
