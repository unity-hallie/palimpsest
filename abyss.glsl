// bio.glsl - bioluminescence in dark water
//
// Pitch black deep ocean. Text disturbs the water.
// Disturbed pixels trigger dinoflagellate emission - blue-green light
// that blooms and slowly fades back to dark.
//
// iChannel0 = terminal content
// iChannel2 = compute state (emission field from bio.compute.msl)

// -- Tuning ----------------------------------------------------------
#define BIO_COLOR    vec3(0.02, 0.78, 0.58)    // dinoflagellate cyan-green
#define BIO_FLASH    vec3(0.18, 1.00, 0.82)    // bright flash at epicenter
#define OCEAN_BG     vec3(0.004, 0.012, 0.020) // deep water - matches conf background
#define BLOOM_TAPS   24
#define BLOOM_SCALE  0.55                       // tight - dense enough to be continuous
// --------------------------------------------------------------------

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    // -- Terminal -----------------------------------------------------
    vec4 termRaw = texture(iChannel0, uv);
    vec3 term = termRaw.rgb;
    float textLuma = dot(term, vec3(0.299, 0.587, 0.114));
    float distFromBg = length(term - OCEAN_BG);
    float textMask = smoothstep(0.03, 0.12, distFromBg);
    textMask = max(textMask, smoothstep(0.06, 0.18, textLuma));

    // -- Emission field -----------------------------------------------
    float emission = texture(iChannel2, uv).g;

    // Soft bloom - golden-angle spiral at increasing radii
    float bloom = 0.0;
    float goldenAngle = 2.39996323;
    for (int i = 0; i < BLOOM_TAPS; i++) {
        float a = float(i) * goldenAngle;
        float r = 2.0 + float(i) * BLOOM_SCALE;
        vec2 off = vec2(cos(a), sin(a)) * r / iResolution.xy;
        bloom += texture(iChannel2, uv + off).g;
    }
    bloom /= float(BLOOM_TAPS);

    // Perceptual curve: flash looks bright, then falls to near-dark fast
    // pow > 1 crushes midtones - only the peak of the flash reads as bright
    float core = pow(emission, 1.8);
    float halo = pow(bloom, 1.4);

    // -- Color --------------------------------------------------------
    vec3 color = OCEAN_BG;
    color += BIO_COLOR * halo * 1.8;
    color += BIO_FLASH * core * 1.6;

    // -- Text ---------------------------------------------------------
    // max() blend -- text always shows at its full terminal color
    // dark colors aren't swallowed by the glow, bright colors add on top
    vec3 textTinted = mix(term, term * vec3(0.72, 1.0, 0.90), 0.18);
    color = 1.0 - (1.0 - color) * (1.0 - textTinted);

    fragColor = vec4(clamp(color, 0.0, 1.0), termRaw.a);
}
