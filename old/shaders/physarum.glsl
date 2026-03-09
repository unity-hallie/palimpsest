// PHYSARUM TERMINAL — mycelial strand visualization
//
// iChannel0 = current terminal frame
// iChannel2 = compute state: R=trail density, A=heading (G,B unused)
//
// Everything derived from trail (R) alone:
//   - edge detection → strand walls opaque, blob interiors transparent
//   - trail magnitude → maturity / color warmth
//   - heading (A) → iridescent shimmer

const vec3 COL_SPORE  = vec3(0.96, 0.93, 0.58);  // germinating tip: pale sulfur
const vec3 COL_YOUNG  = vec3(0.80, 0.64, 0.18);  // young hypha: warm gold
const vec3 COL_MATURE = vec3(0.52, 0.34, 0.06);  // mature network: dark amber
const vec3 COL_DEAD   = vec3(0.42, 0.37, 0.28);  // starved/dying: grey ash

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec2 px = 1.0 / iResolution.xy;

    vec3  term    = texture(iChannel0, uv).rgb;
    vec4  state   = texture(iChannel2, uv);
    float trail   = state.r;
    float heading = state.a * 6.2832;

    // ── Sobel edge detection on trail ─────────────────────────────────────
    float tN  = texture(iChannel2, uv + vec2( 0,      px.y)).r;
    float tS  = texture(iChannel2, uv + vec2( 0,     -px.y)).r;
    float tE  = texture(iChannel2, uv + vec2( px.x,   0   )).r;
    float tW  = texture(iChannel2, uv + vec2(-px.x,   0   )).r;
    float tNE = texture(iChannel2, uv + vec2( px.x,  px.y)).r;
    float tSW = texture(iChannel2, uv + vec2(-px.x, -px.y)).r;
    float tNW = texture(iChannel2, uv + vec2(-px.x,  px.y)).r;
    float tSE = texture(iChannel2, uv + vec2( px.x, -px.y)).r;

    float gx   = (tE - tW) + 0.5 * ((tNE - tNW) + (tSE - tSW));
    float gy   = (tN - tS) + 0.5 * ((tNE - tSE) + (tNW - tSW));
    float grad  = length(vec2(gx, gy));
    float edge  = smoothstep(0.04, 0.30, grad);

    // Interior suppression: blob centres have high neighbor avg → kill alpha
    float nbAvg   = (tN + tS + tE + tW + tNE + tNW + tSE + tSW) / 8.0;
    float interior = smoothstep(0.15, 0.55, nbAvg * trail);

    // ── Color — derived from trail magnitude ──────────────────────────────
    // Low trail  = young spore (bright sulfur)
    // Mid trail  = growing hypha (gold)
    // High trail = mature network (amber-brown)
    float maturity = smoothstep(0.0, 0.6, trail);
    float oldness  = smoothstep(0.3, 1.0, trail);

    vec3 moldColor = mix(COL_SPORE, COL_YOUNG,  maturity);
    moldColor      = mix(moldColor,  COL_MATURE, oldness);

    // Strand edges catch the light
    moldColor = mix(moldColor, moldColor * 1.4 + vec3(0.07, 0.05, 0.01),
                    edge * 0.75);

    // Iridescent shimmer from heading (thin-film interference on hyphal wall)
    float shimmer = sin(heading * 3.0 + trail * 12.0) * 0.5 + 0.5;
    moldColor += vec3(0.03, 0.05, 0.01) * shimmer * trail;

    // ── Opacity ───────────────────────────────────────────────────────────
    // Strand walls: edge × trail — opaque and crisp
    // Body fill:   trail × (1 - interior) — transparent inside blobs
    float edgeAlpha = edge  * trail * 0.90;
    float bodyAlpha = trail * 0.30  * (1.0 - interior);
    float alpha     = max(edgeAlpha, bodyAlpha);
    alpha *= mix(0.25, 1.0, maturity); // young spores are faint

    // ── Composite ─────────────────────────────────────────────────────────
    vec3 color = term;
    color = mix(color, moldColor, clamp(alpha, 0.0, 1.0) * 0.87);
    // Wet specular glint along vein edges
    color += moldColor * edge * trail * 0.05;

    // Gentle vignette
    float vig = 1.0 - 0.12 * pow(length((uv - 0.5) * vec2(1.1, 0.85)), 2.0);
    color *= vig;

    fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
