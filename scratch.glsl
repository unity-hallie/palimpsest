// scratch.glsl — live editing scratchpad
// Ghostty hot-reloads this on save. No restart needed.
// iChannel0 = terminal
// iChannel2 = compute state (if scratch.compute.msl is active)

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;

    vec4 term = texture(iChannel0, uv);

    // ── your experiment here ─────────────────────────────────────────


    fragColor = term;
}
