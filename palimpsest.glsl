// The Palimpsest v8 - temporal bleed
// Ink seeps further the longer the session lives.
// Your terminal ages like a notebook.

// ====== TUNE THESE ======
#define GRAIN_STRENGTH 0.014
#define WARP_AMOUNT 0.0012
#define INK_BLEED 0.3
// Bleed starts here and grows over time
#define BLEED_STRENGTH_MIN 0.08
#define BLEED_STRENGTH_MAX 0.35
#define BLEED_RADIUS_MIN 3.0
#define BLEED_RADIUS_MAX 14.0
// How many seconds until bleed reaches full maturity
#define BLEED_MATURITY_SECONDS 600.0
#define WARMTH_STRENGTH 0.025
#define VIGNETTE_STRENGTH 0.2
// =========================

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord.xy / iResolution.xy;
    float t = iTime * 0.08;
    
    // --- Temporal age: 0.0 at launch, 1.0 after BLEED_MATURITY_SECONDS ---
    float age = clamp(iTime / BLEED_MATURITY_SECONDS, 0.0, 1.0);
    // Ease in - seep starts slow, accelerates, then plateaus
    age = age * age * (3.0 - 2.0 * age); // smoothstep curve
    
    float bleed_strength = mix(BLEED_STRENGTH_MIN, BLEED_STRENGTH_MAX, age);
    float bleed_radius = mix(BLEED_RADIUS_MIN, BLEED_RADIUS_MAX, age);
    
    // --- Paper grain ---
    vec2 grain_uv = fragCoord.xy;
    float fiber = 0.0;
    fiber += sin(grain_uv.x * 0.3 + grain_uv.y * 0.7 + t * 0.4) * 0.5;
    fiber += sin(grain_uv.x * 0.7 - grain_uv.y * 0.4 + t * 0.3) * 0.3;
    fiber += sin((grain_uv.x + grain_uv.y) * 0.15 + t * 0.2) * 0.4;
    fiber = fiber * GRAIN_STRENGTH;
    float fine = fract(sin(dot(floor(grain_uv * 1.5), vec2(12.9898, 78.233))) * 43758.5453);
    fine = (fine - 0.5) * 0.015;
    float surface = fiber + fine;
    
    // --- Text warp ---
    vec2 warp = vec2(
        sin(uv.y * 4.0 + t * 1.5) * WARP_AMOUNT,
        cos(uv.x * 3.0 + t * 1.2) * WARP_AMOUNT * 0.67
    );
    
    vec4 terminal = texture(iChannel0, uv + warp);
    
    // --- Tight ink bleed (letterform softening) ---
    float px = 1.0 / iResolution.x;
    float py = 1.0 / iResolution.y;
    vec4 blur = terminal * 0.55;
    blur += texture(iChannel0, uv + warp + vec2(px, 0.0)) * 0.1125;
    blur += texture(iChannel0, uv + warp + vec2(-px, 0.0)) * 0.1125;
    blur += texture(iChannel0, uv + warp + vec2(0.0, py)) * 0.1125;
    blur += texture(iChannel0, uv + warp + vec2(0.0, -py)) * 0.1125;
    float ink_density = 1.0 - dot(terminal.rgb, vec3(0.299, 0.587, 0.114));
    vec4 inked = mix(terminal, blur, ink_density * INK_BLEED);
    
    // --- TEMPORAL AGAR BLEED ---
    // Inner ring - grows with age
    float bpx = bleed_radius / iResolution.x;
    float bpy = bleed_radius / iResolution.y;
    
    float halo = 0.0;
    halo += (1.0 - dot(texture(iChannel0, uv + vec2(bpx, 0.0)).rgb, vec3(0.299, 0.587, 0.114)));
    halo += (1.0 - dot(texture(iChannel0, uv + vec2(-bpx, 0.0)).rgb, vec3(0.299, 0.587, 0.114)));
    halo += (1.0 - dot(texture(iChannel0, uv + vec2(0.0, bpy)).rgb, vec3(0.299, 0.587, 0.114)));
    halo += (1.0 - dot(texture(iChannel0, uv + vec2(0.0, -bpy)).rgb, vec3(0.299, 0.587, 0.114)));
    halo += (1.0 - dot(texture(iChannel0, uv + vec2(bpx, bpy) * 0.707).rgb, vec3(0.299, 0.587, 0.114)));
    halo += (1.0 - dot(texture(iChannel0, uv + vec2(-bpx, bpy) * 0.707).rgb, vec3(0.299, 0.587, 0.114)));
    halo += (1.0 - dot(texture(iChannel0, uv + vec2(bpx, -bpy) * 0.707).rgb, vec3(0.299, 0.587, 0.114)));
    halo += (1.0 - dot(texture(iChannel0, uv + vec2(-bpx, -bpy) * 0.707).rgb, vec3(0.299, 0.587, 0.114)));
    halo /= 8.0;
    
    // Outer ring - only appears as session ages
    float outer_radius = bleed_radius * 2.0;
    float bpx2 = outer_radius / iResolution.x;
    float bpy2 = outer_radius / iResolution.y;
    float halo2 = 0.0;
    halo2 += (1.0 - dot(texture(iChannel0, uv + vec2(bpx2, 0.0)).rgb, vec3(0.299, 0.587, 0.114)));
    halo2 += (1.0 - dot(texture(iChannel0, uv + vec2(-bpx2, 0.0)).rgb, vec3(0.299, 0.587, 0.114)));
    halo2 += (1.0 - dot(texture(iChannel0, uv + vec2(0.0, bpy2)).rgb, vec3(0.299, 0.587, 0.114)));
    halo2 += (1.0 - dot(texture(iChannel0, uv + vec2(0.0, -bpy2)).rgb, vec3(0.299, 0.587, 0.114)));
    halo2 += (1.0 - dot(texture(iChannel0, uv + vec2(bpx2, bpy2) * 0.707).rgb, vec3(0.299, 0.587, 0.114)));
    halo2 += (1.0 - dot(texture(iChannel0, uv + vec2(-bpx2, bpy2) * 0.707).rgb, vec3(0.299, 0.587, 0.114)));
    halo2 += (1.0 - dot(texture(iChannel0, uv + vec2(bpx2, -bpy2) * 0.707).rgb, vec3(0.299, 0.587, 0.114)));
    halo2 += (1.0 - dot(texture(iChannel0, uv + vec2(-bpx2, -bpy2) * 0.707).rgb, vec3(0.299, 0.587, 0.114)));
    halo2 /= 8.0;
    
    // Combine: inner at full bleed_strength, outer fades in with age
    float seep = halo * bleed_strength + halo2 * bleed_strength * 0.4 * age;
    
    // Slight animation - the ink is still moving in the agar
    seep *= (0.92 + 0.08 * sin(t * 2.0 + uv.x * 5.0 + uv.y * 3.0));
    
    // --- Agar warmth ---
    // Warmth also deepens with age - the culture plate is warming up
    float warmth_age = mix(0.6, 1.0, age);
    float stain = sin(uv.x * 1.5 + uv.y * 1.0 + t * 0.8) * 0.5 + 0.5;
    stain *= stain;
    
    // --- Compose ---
    vec3 color = inked.rgb;
    color += vec3(surface);
    
    // Ink seep
    color.r -= seep * 0.5;
    color.g -= seep * 0.7;
    color.b -= seep * 0.9;
    
    // Agar warmth
    color.r += stain * WARMTH_STRENGTH * warmth_age;
    color.g += stain * WARMTH_STRENGTH * 0.5 * warmth_age;
    color.b -= stain * WARMTH_STRENGTH * 0.4 * warmth_age;
    
    // Vignette
    float vignette = 1.0 - VIGNETTE_STRENGTH * pow(length((uv - 0.5) * vec2(1.2, 0.8)), 2.0);
    color *= vignette;
    
    fragColor = vec4(color, inked.a);
}
