// dodonpachi.glsl -- dense bullet curtain behind terminal text
//
// Cave-style danmaku: overlapping spiral fans, aimed streams,
// rolling walls. Pink rounds, blue laser traces, gold stars.
// The beautiful violence of bullet hell as ambient wallpaper.
//
// iChannel0 = terminal content
// iChannel2 = TickWorld bullet state (dodonpachi.compute.msl)

// -- Tuning ----------------------------------------------------------
#define BG_COLOR        vec3(0.02, 0.01, 0.04)    // deep purple-black (behind sky)
#define BULLET_GLOW     0.6                         // bloom intensity
#define TEXT_BRIGHTNESS  0.95
#define BULLET_PX       0.004                       // bullet pixel size
#define PI               3.14159265
#define TAU              6.28318530
// ====================================================================

// -- begin include common.glsl --
// common.glsl -- shared helpers for palimpsest shaders
// include with: //@ include "common.glsl"

// Perceptual luminance
float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

// 1D hash
float hash1(float n) { return fract(sin(n) * 43758.5453); }

// 2D hash -> [0,1]
float hash2(vec2 p) {
    p = fract(p * vec2(127.1, 311.7));
    p += dot(p, p.yx + 19.19);
    return fract(p.x * p.y);
}

// Value noise (smooth, based on hash2)
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

// 4-octave fBm
float fbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) { v += a * noise(p); p *= 2.1; a *= 0.5; }
    return v;
}
// -- end include common.glsl --

// -- Helpers ---------------------------------------------------------
// hash1(float n) from common.glsl used below via alias
float hash(float n) { return hash1(n); }

// Signed distance to a circle
float sdCircle(vec2 p, float r) { return length(p) - r; }

// Bullet: pixelated bright core + soft glow halo
vec3 bullet(vec2 uv, vec2 pos, float radius, vec3 color, float intensity) {
    // Snap both UV and position to pixel grid for chunky look
    vec2 puv = floor(uv / BULLET_PX) * BULLET_PX + BULLET_PX * 0.5;
    vec2 ppos = floor(pos / BULLET_PX) * BULLET_PX + BULLET_PX * 0.5;
    float d = length(puv - ppos);
    // Hard pixelated core
    float core = step(d, radius);
    // Soft glow halo (not pixelated -- bloom bleeds smooth)
    float dSmooth = length(uv - pos);
    float glow = exp(-dSmooth * dSmooth / (radius * radius * 10.0)) * BULLET_GLOW;
    return color * (core * intensity + glow * intensity * 0.3);
}

// -- Bullet colors by emitter index ----------------------------------
vec3 bulletColor(int emitter) {
    if (emitter == 0) return vec3(1.0, 0.3, 0.55);   // pink spirals
    if (emitter == 1) return vec3(0.3, 0.5, 1.0);     // blue streams
    if (emitter == 3) return vec3(0.9, 0.25, 0.45);   // pink wall
    if (emitter == 4) return vec3(0.7, 0.3, 0.9);     // purple fans
    if (emitter == 5) return vec3(1.0, 0.85, 0.25);   // gold medals
    if (emitter == 6) return vec3(1.0, 0.92, 0.4);    // bling (converted)
    return vec3(0.7, 0.3, 0.9);
}

float bulletRadius(int emitter) {
    if (emitter == 5) return 0.012;  // medals are bigger
    if (emitter == 6) return 0.009;  // bling slightly bigger than bullets
    return 0.007;
}

// Medal: shiny diamond shape instead of round
vec3 medal(vec2 uv, vec2 pos, float life, float time) {
    vec2 puv = floor(uv / BULLET_PX) * BULLET_PX + BULLET_PX * 0.5;
    vec2 ppos = floor(pos / BULLET_PX) * BULLET_PX + BULLET_PX * 0.5;
    vec2 d = abs(puv - ppos);
    // Diamond shape: |x| + |y| < radius
    float dist = d.x + d.y;
    float radius = 0.012;
    float core = step(dist, radius);
    // Shimmer: brightness oscillates
    float shimmer = 0.7 + 0.3 * sin(time * 8.0 + pos.y * 40.0);
    // Gold gradient: brighter center
    vec3 gold = mix(vec3(1.0, 0.75, 0.15), vec3(1.0, 0.95, 0.6), shimmer);
    // Soft glow
    float dSmooth = length(uv - pos);
    float glow = exp(-dSmooth * dSmooth / (radius * radius * 12.0)) * 0.5;
    return gold * (core * shimmer * life + glow * life * 0.4);
}

// Bling: opaque gold nugget, shining, falls with gravity
vec3 bling(vec2 uv, vec2 pos, float life, float time) {
    vec2 puv = floor(uv / BULLET_PX) * BULLET_PX + BULLET_PX * 0.5;
    vec2 ppos = floor(pos / BULLET_PX) * BULLET_PX + BULLET_PX * 0.5;
    float d = length(puv - ppos);
    float radius = 0.009;
    float core = step(d, radius);
    // Shimmer -- bright and solid, not fading
    float shimmer = 0.75 + 0.25 * sin(time * 12.0 + pos.x * 50.0 + pos.y * 70.0);
    vec3 gold = mix(vec3(1.0, 0.82, 0.2), vec3(1.0, 0.95, 0.6), shimmer);
    // Hard bright glow -- opaque, no alpha
    float dSmooth = length(uv - pos);
    float glow = exp(-dSmooth * dSmooth / (radius * radius * 10.0)) * 0.6;
    return gold * (core * shimmer + glow * 0.5);  // no life multiply -- always full bright
}

// Read all live bullets from state texture and draw them
// Layout: linear buffer starting at index 1. Pairs: posIdx = 1+i*2, velIdx = 1+i*2+1
vec3 drawBullets(vec2 uv, vec2 auv, float aspect) {
    vec3 col = vec3(0.0);
    vec2 texSize = iResolution.xy;
    int W = int(texSize.x);

    for (int i = 0; i < 200; i++) {
        // Position pixel is at linear index 1 + i*2
        int linIdx = 1 + i * 2;
        int px = linIdx % W;
        int py = linIdx / W;
        vec2 coord = (vec2(float(px), float(py)) + 0.5) / texSize;
        vec4 bdata = texture(iChannel2, coord);

        float life = bdata.b;
        if (life <= 0.0) continue;

        vec2 bpos = bdata.rg;
        float emitterID = bdata.a;
        vec2 abpos = vec2(bpos.x * aspect, bpos.y);

        int eid = int(emitterID + 0.5);
        if (eid == 5) {
            col += medal(auv, abpos, life, iTime);
        } else if (eid == 6) {
            col += bling(auv, abpos, life, iTime);
        } else {
            vec3 bc = bulletColor(eid);
            float radius = bulletRadius(eid);
            col += bullet(auv, abpos, radius, bc, life);
        }
    }
    return col;
}

// ====================================================================

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    float aspect = iResolution.x / iResolution.y;
    vec2 auv = vec2(uv.x * aspect, uv.y);  // aspect-corrected for round bullets

    float t = iTime;

    // -- Blue sky gradient ---------------------------------------------
    vec3 skyTop = vec3(0.15, 0.35, 0.85);
    vec3 skyBot = vec3(0.45, 0.65, 0.95);
    vec3 scene = mix(skyTop, skyBot, uv.y);

    // -- Cloud layers -- parallax scrolling ---------------------------
    // Far clouds: slow, large, faint
    {
        float cs = t * -0.015;
        float cpx = 1.0 / 60.0;  // coarse pixels
        vec2 cuv = floor(uv / cpx) * cpx;
        float sy = cuv.y + cs;
        // Layered noise for cloud shapes
        float c = 0.0;
        c += hash(floor(sy * 2.0) * 5.1 + floor(cuv.x * 4.0) * 3.3) * 0.5;
        c += hash(floor(sy * 4.0) * 7.3 + floor(cuv.x * 8.0) * 5.7) * 0.3;
        c += hash(floor(sy * 8.0) * 11.1 + floor(cuv.x * 16.0) * 9.3) * 0.2;
        float cloud = smoothstep(0.45, 0.65, c);
        scene = mix(scene, vec3(0.85, 0.90, 0.98), cloud * 0.4);
    }

    // Mid clouds: medium speed, medium detail
    {
        float cs = t * -0.03;
        float cpx = 1.0 / 90.0;
        vec2 cuv = floor(uv / cpx) * cpx;
        float sy = cuv.y + cs;
        float c = 0.0;
        c += hash(floor(sy * 3.0) * 13.7 + floor(cuv.x * 6.0) * 17.1 + 200.0) * 0.5;
        c += hash(floor(sy * 6.0) * 19.3 + floor(cuv.x * 12.0) * 23.7 + 200.0) * 0.3;
        c += hash(floor(sy * 12.0) * 29.1 + floor(cuv.x * 24.0) * 31.3 + 200.0) * 0.2;
        float cloud = smoothstep(0.50, 0.70, c);
        scene = mix(scene, vec3(0.90, 0.93, 1.0), cloud * 0.35);
    }

    // Near clouds: fastest, wispier, slight shadow
    {
        float cs = t * -0.055;
        float cpx = 1.0 / 130.0;
        vec2 cuv = floor(uv / cpx) * cpx;
        float sy = cuv.y + cs;
        float c = 0.0;
        c += hash(floor(sy * 4.0) * 37.3 + floor(cuv.x * 8.0) * 41.1 + 500.0) * 0.5;
        c += hash(floor(sy * 8.0) * 43.7 + floor(cuv.x * 16.0) * 47.3 + 500.0) * 0.3;
        c += hash(floor(sy * 16.0) * 53.1 + floor(cuv.x * 32.0) * 59.7 + 500.0) * 0.2;
        float cloud = smoothstep(0.55, 0.75, c);
        scene = mix(scene, vec3(0.95, 0.96, 1.0), cloud * 0.3);
    }

    // -- Parallax background layers -- scrolling vertically like a shmup --

    // Pixelation helper: snap UV to a grid
    // All terrain layers use pixelated coordinates

    // Layer 1 (far terrain): distant mountains, slow scroll, coarse pixels
    {
        float scroll1 = t * -0.025;
        float pxSize1 = 1.0 / 80.0;  // chunky pixels
        vec2 puv1 = floor(uv / pxSize1) * pxSize1;
        float sy = puv1.y + scroll1;

        // Fractal heightmap: left and right edges are terrain walls
        float h1 = 0.0;
        float freq = 3.0;
        float amp = 0.15;
        for (int o = 0; o < 4; o++) {
            h1 += hash(floor(sy * freq) * 7.1) * amp;
            freq *= 2.0;
            amp *= 0.5;
        }
        // Terrain on both sides -- cave/canyon walls
        float wallL = step(puv1.x, h1);
        float wallR = step(1.0 - puv1.x, h1);
        float terrain1 = max(wallL, wallR);

        // Jamestown far mountains: hazy blue-green, sunlit tops
        float shade1 = 0.5 + 0.5 * hash(floor(puv1 / pxSize1).x * 3.1 + floor(sy * 6.0) * 7.7);
        vec3 rock1 = mix(vec3(0.18, 0.25, 0.30), vec3(0.30, 0.40, 0.35), shade1);
        // Green moss band near top of terrain
        float topDist1 = abs(puv1.x - h1) + abs((1.0 - puv1.x) - h1);
        float mossy1 = smoothstep(0.06, 0.0, min(abs(puv1.x - h1), abs((1.0 - puv1.x) - h1)));
        rock1 = mix(rock1, vec3(0.25, 0.45, 0.20), mossy1 * 0.6);
        scene = mix(scene, rock1, terrain1 * 0.85);
    }

    // Layer 2 (mid terrain): closer canyon walls, medium scroll, medium pixels
    {
        float scroll2 = t * -0.05;
        float pxSize2 = 1.0 / 120.0;
        vec2 puv2 = floor(uv / pxSize2) * pxSize2;
        float sy = puv2.y + scroll2;

        float h2 = 0.0;
        float freq = 2.5;
        float amp = 0.12;
        for (int o = 0; o < 4; o++) {
            h2 += hash(floor(sy * freq) * 13.3 + 50.0) * amp;
            freq *= 2.0;
            amp *= 0.5;
        }
        float wallL = step(puv2.x, h2 * 0.7);
        float wallR = step(1.0 - puv2.x, h2 * 0.7);
        float terrain2 = max(wallL, wallR);

        // Jamestown mid cliffs: warm brown earth, gold edge light
        float shade2 = 0.5 + 0.5 * hash(floor(puv2 / pxSize2).x * 5.3 + floor(sy * 8.0) * 11.1);
        vec3 rock2 = mix(vec3(0.25, 0.16, 0.10), vec3(0.40, 0.28, 0.18), shade2);
        // Mossy green patches
        float moss2 = hash(floor(puv2 / pxSize2).x * 9.1 + floor(sy * 5.0) * 3.3);
        rock2 = mix(rock2, vec3(0.20, 0.38, 0.15), step(0.65, moss2) * 0.5);
        float edgeDist = min(abs(puv2.x - h2 * 0.7), abs((1.0 - puv2.x) - h2 * 0.7));
        float edgeGlow = smoothstep(0.02, 0.0, edgeDist) * terrain2;
        scene = mix(scene, rock2, terrain2 * 0.9);
        scene += vec3(0.50, 0.38, 0.12) * edgeGlow * 0.6;  // golden edge
    }

    // Layer 3 (near terrain): foreground rocks, fastest scroll, finer pixels
    {
        float scroll3 = t * -0.08;
        float pxSize3 = 1.0 / 160.0;
        vec2 puv3 = floor(uv / pxSize3) * pxSize3;
        float sy = puv3.y + scroll3;

        float h3 = 0.0;
        float freq = 2.0;
        float amp = 0.08;
        for (int o = 0; o < 5; o++) {
            h3 += hash(floor(sy * freq) * 19.7 + 100.0) * amp;
            freq *= 2.0;
            amp *= 0.5;
        }
        float wallL = step(puv3.x, h3 * 0.45);
        float wallR = step(1.0 - puv3.x, h3 * 0.45);
        float terrain3 = max(wallL, wallR);

        // Jamestown near rock: dark rich earth, red-brown, bright gold/green edge
        float shade3 = 0.5 + 0.5 * hash(floor(puv3 / pxSize3).x * 7.7 + floor(sy * 10.0) * 13.3);
        vec3 rock3 = mix(vec3(0.18, 0.10, 0.06), vec3(0.35, 0.20, 0.12), shade3);
        // Deep green moss patches
        float moss3 = hash(floor(puv3 / pxSize3).x * 11.3 + floor(sy * 7.0) * 5.7);
        rock3 = mix(rock3, vec3(0.12, 0.30, 0.10), step(0.6, moss3) * 0.6);
        // Bright gold-green edge
        float edgeDist = min(abs(puv3.x - h3 * 0.45), abs((1.0 - puv3.x) - h3 * 0.45));
        float edgeGlow = smoothstep(0.015, 0.0, edgeDist) * terrain3;
        scene = mix(scene, rock3, terrain3 * 0.95);
        scene += vec3(0.55, 0.45, 0.15) * edgeGlow * 0.5;  // gold highlight
        scene += vec3(0.10, 0.25, 0.05) * edgeGlow * 0.3;  // green fringe
    }

    // -- FAR HAZE -- soften the world before bullets --------------------
    scene = mix(scene, vec3(0.85, 0.90, 0.95), 0.3);

    // -- BULLET LAYER -- read from TickWorld compute state ------------
    vec3 bullets = drawBullets(uv, auv, aspect);
    scene += bullets;

    // -- Bomb smoke puff -----------------------------------------------
    {
        int bombCycle = 600;
        float tickF = iTime * 60.0;  // approximate tick from time
        int tickInCycle = int(mod(tickF, float(bombCycle)));
        // Bomb just went off -- show expanding smoke ring
        if (tickInCycle < 90) {  // smoke visible for ~1.5 seconds
            float bombAge = float(tickInCycle) / 90.0;
            int bombIdx = int(tickF) / bombCycle;
            // Reconstruct bomb position (must match compute)
            vec2 bombPos = vec2(
                0.3 + 0.4 * hash(float(bombIdx) * 7.3 + 311.7 * 1.0),
                0.3 + 0.4 * hash(float(bombIdx) * 13.1 + 311.7 * 2.0)
            );
            // Note: hash functions differ between GLSL and Metal, positions won't match exactly
            // but the visual effect still works as ambient decoration

            vec2 abomb = vec2(bombPos.x * aspect, bombPos.y);
            float dist = length(auv - abomb);
            float ringRadius = bombAge * 0.3;
            float ringWidth = 0.04 * (1.0 - bombAge);
            float ring = smoothstep(ringWidth, 0.0, abs(dist - ringRadius));
            float fade = (1.0 - bombAge) * (1.0 - bombAge);

            // White-gold smoke
            vec3 smoke = mix(vec3(1.0, 0.95, 0.7), vec3(0.9, 0.85, 0.6), bombAge);
            scene += smoke * ring * fade * 0.4;

            // Central flash at detonation
            if (bombAge < 0.15) {
                float flash = exp(-dist * dist / 0.01) * (1.0 - bombAge / 0.15);
                scene += vec3(1.0, 0.95, 0.8) * flash * 0.6;
            }
        }
    }

    // -- NEAR HAZE -- bright frosted glass before text (HUD layer) ----
    scene = mix(scene, vec3(0.82, 0.88, 0.92), 0.35);

    // CRT scan lines
    float scan = sin(uv.y * iResolution.y * PI) * 0.5 + 0.5;
    scene *= 0.96 + 0.04 * scan;

    // -- TEXT -- dark on light: key out bright background ------------
    vec3 raw = texture(iChannel0, uv).rgb;
    float luma = dot(raw, vec3(0.299, 0.587, 0.114));
    // Dark text = low luma; bright bg = high luma. Invert the mask.
    float textMask = smoothstep(0.75, 0.55, luma);

    vec3 color = mix(scene, raw * TEXT_BRIGHTNESS, textMask);

    fragColor = vec4(clamp(color, 0.0, 1.0), texture(iChannel0, uv).a);
}