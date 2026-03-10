// daisyworld.glsl — SimEarth climate sim behind your terminal
//
// iChannel0 = terminal content
// iChannel2 = climate state (R=temp, G=moisture, B=biomass, A=elevation)
//
// Biomes emerge from conditions. Text is sacred.

// ── Tuning ──────────────────────────────────────────────────────────────────
#define GROUND_OPACITY    0.9      // how much the world shows through
#define BIOME_SATURATION  0.85     // color vividness
#define TEXT_BLEND        0.10     // ground color bleeding into text
#define CLOUD_OPACITY     0.20     // moisture haze in atmosphere
#define WATER_DEPTH       0.3      // how dark deep water gets
#define SNOW_LINE         0.72     // elevation above which snow appears
#define ICE_TEMP          0.08     // temperature below which ice forms
// ────────────────────────────────────────────────────────────────────────────

float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

vec3 biomeColor(float temp, float moisture, float biomass, float elev) {
    // ── Water ───────────────────────────────────────────────────────────
    // Water is where moisture exceeds what the land can hold
    // High elevation = well-drained, needs lots of moisture to be "water"
    // Low elevation = basin, even moderate moisture pools
    float drainCapacity = elev * 2.0;  // high ground drains more aggressively
    float waterExcess = moisture - drainCapacity;
    float isWater = smoothstep(0.0, 0.2, waterExcess);
    vec3 shallowWater = vec3(0.08, 0.15, 0.32);
    vec3 deepWater    = vec3(0.02, 0.05, 0.22);
    vec3 waterColor   = mix(shallowWater, deepWater, smoothstep(0.15, 0.0, elev));
    // Warm water is slightly greener (algae)
    waterColor = mix(waterColor, vec3(0.08, 0.20, 0.22), smoothstep(0.4, 0.7, temp) * 0.3);

    // ── Land biomes ─────────────────────────────────────────────────────
    // Desert: hot + dry — ochre clay
    vec3 desert = vec3(0.45, 0.30, 0.10);
    // Savanna: warm + moderate moisture — yellow-green
    vec3 savanna = vec3(0.30, 0.38, 0.06);
    // Grassland: moderate temp + moisture — true green
    vec3 grassland = vec3(0.12, 0.42, 0.05);
    // Forest: warm + wet + high biomass — deep green
    vec3 forest = vec3(0.06, 0.35, 0.03);
    // Jungle: hot + very wet — saturated emerald
    vec3 jungle = vec3(0.03, 0.32, 0.05);
    // Tundra: cold + some moisture — sage
    vec3 tundra = vec3(0.20, 0.26, 0.16);
    // Rock: cold + dry + high elevation — warm grey
    vec3 rock = vec3(0.20, 0.17, 0.13);
    // Ice/snow
    vec3 ice = vec3(0.7, 0.75, 0.8);

    // Start with bare ground based on temp
    vec3 bare = mix(rock, desert, smoothstep(0.3, 0.6, temp));

    // Add moisture influence
    vec3 land = bare;
    float wetness = smoothstep(0.2, 0.6, moisture);

    // Cold biomes
    vec3 coldBiome = mix(rock, tundra, wetness);
    // Warm biomes
    vec3 warmBiome = mix(desert, mix(savanna, grassland, wetness), smoothstep(0.0, 0.2, wetness));
    // Hot biomes
    vec3 hotBiome = mix(desert, jungle, wetness);

    // Blend by temperature — wider bands for distinct biomes
    land = mix(coldBiome, warmBiome, smoothstep(0.20, 0.38, temp));
    land = mix(land, hotBiome, smoothstep(0.50, 0.65, temp));

    // Biomass pushes into green — even a little life shows
    vec3 lifeGreen = mix(grassland, forest, biomass);
    land = mix(land, lifeGreen, biomass * smoothstep(0.08, 0.25, moisture));

    // Snow at high elevation or very cold — but not on active volcanoes
    float snowAmount = smoothstep(SNOW_LINE, 0.95, elev)
                     + smoothstep(ICE_TEMP, 0.0, temp) * 0.5;
    snowAmount *= smoothstep(0.30, 0.15, temp);  // any warmth melts snow
    snowAmount = clamp(snowAmount, 0.0, 1.0);
    land = mix(land, ice, snowAmount * (1.0 - moisture * 0.3));

    // ── Composite water vs land ─────────────────────────────────────────
    vec3 color = mix(land, waterColor, isWater);

    return mix(vec3(luma(color)), color, BIOME_SATURATION);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    // ── State (spatially blurred to kill single-frame jitter) ──────────
    vec2 px = 1.0 / iResolution.xy;
    vec4 st  = texture(iChannel2, uv);
    vec4 stL = texture(iChannel2, uv + vec2(-px.x * 2.0, 0));
    vec4 stR = texture(iChannel2, uv + vec2( px.x * 2.0, 0));
    vec4 stU = texture(iChannel2, uv + vec2(0, -px.y * 2.0));
    vec4 stD = texture(iChannel2, uv + vec2(0,  px.y * 2.0));
    vec4 blurred = st * 0.4 + (stL + stR + stU + stD) * 0.15;
    float temp     = blurred.r;
    float moisture = blurred.g;
    float biomass  = blurred.b;
    float elev     = st.a;  // elevation is stable, no blur needed

    // ── Sun position (needed for hillshade + day/night) ─────────────────
    float dayT = iTime * 0.08;
    float sunX = fract(dayT * 0.133);

    // ── Ground ──────────────────────────────────────────────────────────
    vec3 ground = biomeColor(temp, moisture, biomass, elev);

    // Elevation normal map — light follows the sun
    float eL = texture(iChannel2, uv + vec2(-px.x, 0)).a;
    float eR = texture(iChannel2, uv + vec2( px.x, 0)).a;
    float eU = texture(iChannel2, uv + vec2(0, -px.y)).a;
    float eD = texture(iChannel2, uv + vec2(0,  px.y)).a;
    vec2 slope = vec2(eR - eL, eD - eU) * 12.0;
    float sunAngle = (uv.x - sunX) * 6.28;
    vec2 lightDir = normalize(vec2(cos(sunAngle), -0.6));
    float hillshade = 0.5 + dot(slope, lightDir) * 0.5;
    // Water is flat — no hillshade on ocean
    float isWaterShade = smoothstep(0.0, 0.2, moisture - elev * 2.0);
    hillshade = mix(hillshade, 0.5, isWaterShade);
    ground *= mix(0.75, 1.25, hillshade);

    // ── Day/night lighting ──────────────────────────────────────────────
    float sunDist = abs(uv.x - sunX);
    sunDist = min(sunDist, 1.0 - sunDist);
    float daylight = 1.0 - smoothstep(0.0, 0.45, sunDist);
    daylight = daylight * 0.7 + 0.3;

    vec3 dayTint   = vec3(1.05, 1.0, 0.88);
    vec3 nightTint = vec3(0.55, 0.6, 0.85);
    vec3 lightTint = mix(nightTint, dayTint, daylight);

    ground *= lightTint;

    // ── Volcanic glow (after lighting — lava makes its own light) ─────
    float isWater = smoothstep(0.0, 0.2, moisture - elev * 1.5);
    float lavaIntensity = smoothstep(0.55, 0.75, temp) * smoothstep(0.3, 0.6, elev) * (1.0 - isWater);
    vec3 lavaColor = mix(vec3(0.6, 0.15, 0.0), vec3(1.0, 0.4, 0.05), lavaIntensity);
    ground = mix(ground, lavaColor, lavaIntensity * 0.7);

    // Moisture haze (clouds/fog in wet areas)
    float haze = smoothstep(0.5, 0.85, moisture) * CLOUD_OPACITY;
    ground = mix(ground, vec3(0.6, 0.65, 0.7) * lightTint, haze);

    // ── Terminal text as sunlight ──────────────────────────────────────
    vec3 term = texture(iChannel0, uv).rgb;
    float textBright = luma(term);

    // Text tinted by time of day
    vec3 termGrey = vec3(luma(term));
    vec3 neutralized = mix(term, termGrey, 0.4);
    vec3 warmText = neutralized * lightTint;

    // Ground color subtly bleeds into text
    vec3 textColor = mix(warmText, warmText * mix(vec3(1.0), ground * 2.0, TEXT_BLEND), textBright);

    // ── Composite ───────────────────────────────────────────────────────
    float textMask = smoothstep(0.02, 0.12, textBright);
    vec3 color = mix(ground * GROUND_OPACITY, textColor, textMask);

    // ── Focus dim ───────────────────────────────────────────────────────
    float focusT = clamp((iTime - iTimeFocus) * 1.5, 0.0, 1.0);
    float focusMix = iFocus == 1 ? focusT : 1.0 - focusT;
    float dimAmount = mix(0.5, 1.0, focusMix);
    float satAmount = mix(0.2, 1.0, focusMix);
    vec3 grey = vec3(luma(color));
    color = mix(grey, color, satAmount) * dimAmount;

    fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
