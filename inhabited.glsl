// Inhabited
// The text is the city. Characters are buildings. Dark space is streets and sky.
// You are looking down from above, at night.
// The simulation is not overlaid — it emerges from what is actually on screen.

// ====== TUNE THESE ======
#define DISTRICT_RADIUS   0.07    // How far to look when measuring neighborhood density
#define BLEED_STEPS       5.0     // Quality of upward light bleed (more = softer, more expensive)
#define BLEED_HEIGHT      0.022   // How far light climbs above buildings
#define HEAT_STRENGTH     0.14    // Warmth of busy districts
#define STREET_COOL       0.35    // Blue depth of dark/empty areas (streets, sky between towers)
#define PULSE_SPEED       0.6     // How fast districts breathe
#define FLOW_SPEED        0.12    // Speed of traffic/wind through streets
#define WINDOW_RATE       2.5     // How fast individual windows flicker on/off
// =========================

float luma(vec3 c) {
    return dot(c, vec3(0.299, 0.587, 0.114));
}

float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash21(i),                  hash21(i + vec2(1.0, 0.0)), f.x),
        mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x),
        f.y
    );
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    float t = iTime;

    // --- Read the city as-is ---
    vec4 terminal = texture(iChannel0, uv);
    float brightness = luma(terminal.rgb);

    // --- District: what neighborhood is this pixel in? ---
    // Sample radially to measure local building density.
    // This is the topology — it determines everything downstream.
    float district = 0.0;
    float r = DISTRICT_RADIUS;
    district += luma(texture(iChannel0, uv + vec2(-r,   0.0)).rgb);
    district += luma(texture(iChannel0, uv + vec2( r,   0.0)).rgb);
    district += luma(texture(iChannel0, uv + vec2( 0.0, -r )).rgb);
    district += luma(texture(iChannel0, uv + vec2( 0.0,  r )).rgb);
    district += luma(texture(iChannel0, uv + vec2(-r,  -r ) * 0.707).rgb);
    district += luma(texture(iChannel0, uv + vec2( r,  -r ) * 0.707).rgb);
    district += luma(texture(iChannel0, uv + vec2(-r,   r ) * 0.707).rgb);
    district += luma(texture(iChannel0, uv + vec2( r,   r ) * 0.707).rgb);
    district /= 8.0;

    // --- Upward light bleed ---
    // Buildings cast warm light upward into the space above them.
    // Sample below current position — light is climbing toward this pixel.
    float bleed = 0.0;
    for (float i = 1.0; i <= BLEED_STEPS; i++) {
        float offset = (i / BLEED_STEPS) * BLEED_HEIGHT;
        float falloff = 1.0 - (i / (BLEED_STEPS + 1.0));
        bleed += luma(texture(iChannel0, uv + vec2(0.0, -offset)).rgb) * falloff;
    }
    bleed /= BLEED_STEPS;

    // --- Traffic flow field ---
    // Directional noise simulating movement along streets.
    // Stronger in dense areas — the city channels its own activity.
    float flow_t = t * FLOW_SPEED;
    vec2 city_uv = uv * vec2(14.0, 7.0); // city-block scale
    float flow = noise(city_uv + vec2(flow_t * 0.8,  flow_t * 0.3));
    flow += noise(city_uv * 1.8 + vec2(-flow_t * 0.5, flow_t * 0.7)) * 0.5;
    flow /= 1.5;
    float traffic = flow * district * 0.06;

    // --- District pulse: neighborhoods breathe at different phases ---
    // Two overlapping rhythms so adjacent areas don't sync up.
    float phase = uv.x * 4.2 + uv.y * 2.8;
    float pulse_a = sin(t * PULSE_SPEED + phase) * 0.5 + 0.5;
    float pulse_b = sin(t * PULSE_SPEED * 1.6 - phase * 0.7 + 1.2) * 0.5 + 0.5;
    float pulse = sqrt(pulse_a * pulse_b); // geometric mean — softer, less uniform

    // --- Window flicker ---
    // Individual characters (windows) turn on and off.
    // Only characters that are already lit participate — dark space stays dark.
    float char_x = floor(fragCoord.x / 8.0);  // approx character cell width
    float char_y = floor(fragCoord.y / 16.0); // approx character cell height
    float window_phase = hash21(vec2(char_x, char_y));
    float flicker = step(0.5, fract(window_phase + t * WINDOW_RATE * (0.5 + window_phase)));
    flicker = mix(0.85, 1.0, flicker); // subtle — not binary on/off, just dimming

    // --- Compose ---
    vec3 color = terminal.rgb;

    // Apply window flicker to actual text (buildings are their windows)
    color *= mix(1.0, flicker, brightness * 0.3);

    // Street cool: dark space shifts toward night-sky blue
    float openness = 1.0 - brightness;
    color.b += openness * STREET_COOL * 0.08;
    color.r -= openness * STREET_COOL * 0.02;
    color.g -= openness * STREET_COOL * 0.01;

    // Upward bleed: warm orange-yellow light from buildings climbing upward
    float bleed_contribution = bleed * (1.0 - brightness * 0.5); // streets receive more
    color.r += bleed_contribution * 0.35;
    color.g += bleed_contribution * 0.18;
    color.b += bleed_contribution * 0.02;

    // District heat: busy neighborhoods breathe warm
    float heat = district * pulse * HEAT_STRENGTH;
    color.r += heat * 0.55;
    color.g += heat * 0.22;
    color.b -= heat * 0.15;

    // Traffic: subtle luminance shimmer along flow channels
    color += vec3(traffic);

    fragColor = vec4(color, terminal.a);
}
