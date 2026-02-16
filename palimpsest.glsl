// The Palimpsest v5 - livable
// You should feel it more than see it.
// Paper that breathes. Ink that remembers it was wet.

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord.xy / iResolution.xy;
    float t = iTime * 0.08;
    
    // --- Paper grain - the version you liked ---
    vec2 grain_uv = fragCoord.xy;
    float fiber = 0.0;
    fiber += sin(grain_uv.x * 0.3 + grain_uv.y * 0.7 + t * 0.4) * 0.5;
    fiber += sin(grain_uv.x * 0.7 - grain_uv.y * 0.4 + t * 0.3) * 0.3;
    fiber += sin((grain_uv.x + grain_uv.y) * 0.15 + t * 0.2) * 0.4;
    fiber = fiber * 0.018;
    float fine = fract(sin(dot(floor(grain_uv * 1.5), vec2(12.9898, 78.233))) * 43758.5453);
    fine = (fine - 0.5) * 0.02;
    float surface = fiber + fine;
    
    // --- Text warp - just barely perceptible ---
    // Slow, long-wavelength. Like the paper itself is settling.
    vec2 warp = vec2(
        sin(uv.y * 4.0 + t * 1.5) * 0.0012,
        cos(uv.x * 3.0 + t * 1.2) * 0.0008
    );
    
    vec4 terminal = texture(iChannel0, uv + warp);
    
    // --- Ink bleed ---
    float px = 1.0 / iResolution.x;
    float py = 1.0 / iResolution.y;
    vec4 blur = terminal * 0.55;
    blur += texture(iChannel0, uv + warp + vec2(px, 0.0)) * 0.1125;
    blur += texture(iChannel0, uv + warp + vec2(-px, 0.0)) * 0.1125;
    blur += texture(iChannel0, uv + warp + vec2(0.0, py)) * 0.1125;
    blur += texture(iChannel0, uv + warp + vec2(0.0, -py)) * 0.1125;
    float ink_density = 1.0 - dot(terminal.rgb, vec3(0.299, 0.587, 0.114));
    vec4 inked = mix(terminal, blur, ink_density * 0.3);
    
    // --- Agar warmth - slow drift ---
    // One big warm zone that migrates like moisture in a culture plate
    float stain = sin(uv.x * 1.5 + uv.y * 1.0 + t * 0.8) * 0.5 + 0.5;
    stain *= stain; // Soften the gradient
    
    vec3 color = inked.rgb;
    color += vec3(surface);
    
    // Warmth that you notice after 30 seconds, not immediately
    color.r += stain * 0.025;
    color.g += stain * 0.012;
    color.b -= stain * 0.01;
    
    // Vignette
    float vignette = 1.0 - 0.2 * pow(length((uv - 0.5) * vec2(1.2, 0.8)), 2.0);
    color *= vignette;
    
    fragColor = vec4(color, inked.a);
}
