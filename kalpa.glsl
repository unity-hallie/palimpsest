// Kalpa
// You are in an impossibly slow elevator descending through the basement of time.
// The terminal is the craft's viewport. Text is system readout on the glass.
// Outside: dead worlds scrolling past, each with its own character.
// The glass is between you and all of it.

// ====== TUNE THESE ======
#define DESCENT_SPEED     0.010   // How fast you descend (glacial)
#define LAYER_SCALE       0.55    // How many strata visible at once (~2 screens per layer)
#define BG_BRIGHTNESS     0.40    // Overall background brightness
#define MOTE_SPEED        6.0     // How fast motes drift downward
#define TEXT_TINT         0.25    // How much the current stratum tints the text
#define FRAME_WIDTH       0.018   // Thin bezel — glass sits inside it
#define BARREL_STRENGTH  -0.15    // Concave glass — edges flare into bezel
#define VIEWPORT_SOFT     0.02    // How soft the viewport edge is
#define GLASS_STRENGTH    0.025   // Faint reflections on the glass
#define FRAME_GLOW        0.15    // Instrument light spilling from the frame edge
// =========================

float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float hash11(float p) {
    return fract(sin(p * 127.1) * 43758.5453);
}

// Smooth noise
float vnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash21(i),                  hash21(i + vec2(1.0, 0.0)), f.x),
        mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x),
        f.y
    );
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 5; i++) {
        v += a * vnoise(p);
        p = p * 2.01 + vec2(1.7, 9.2);
        a *= 0.5;
    }
    return v;
}

// Voronoi — crystalline cells
float voronoi(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    float d = 1.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 nb = vec2(float(x), float(y));
            vec2 pt = vec2(hash21(i + nb), hash21(i + nb + 99.0));
            d = min(d, length(nb + pt - f));
        }
    }
    return d;
}

// Voronoi cell edges (for ruins/structure)
float voronoiEdge(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    float d1 = 1.0, d2 = 1.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 nb = vec2(float(x), float(y));
            vec2 pt = vec2(hash21(i + nb), hash21(i + nb + 99.0));
            float d = length(nb + pt - f);
            if (d < d1) { d2 = d1; d1 = d; }
            else if (d < d2) { d2 = d; }
        }
    }
    return d2 - d1;
}

// Each layer is a different dead world.
// layerType 0: crystalline/mineral — voronoi facets, cool
// layerType 1: fungal/organic — fbm, bioluminescent
// layerType 2: ruins — grid fragments, dead geometry
// layerType 3: void — near-empty, distant faint lights
// layerType 4: magma/deep — hot, slow-pulsing

vec3 layerPalette(float layerType, float layerSeed) {
    vec3 c;
    if (layerType < 1.0)      c = mix(vec3(0.08, 0.12, 0.28), vec3(0.15, 0.25, 0.40), layerSeed); // crystal: cold slate/blue
    else if (layerType < 2.0) c = mix(vec3(0.04, 0.22, 0.15), vec3(0.08, 0.35, 0.20), layerSeed); // fungal: deep green/teal
    else if (layerType < 3.0) c = mix(vec3(0.25, 0.18, 0.06), vec3(0.45, 0.30, 0.08), layerSeed); // ruins: amber/gold
    else if (layerType < 4.0) c = mix(vec3(0.02, 0.02, 0.04), vec3(0.04, 0.03, 0.08), layerSeed); // void: near-black
    else                      c = mix(vec3(0.30, 0.08, 0.03), vec3(0.50, 0.15, 0.04), layerSeed); // magma: deep red/orange
    return c;
}

// Texture for each world type
float layerTexture(float layerType, vec2 uv, float depth, float seed, float t) {
    if (layerType < 1.0) {
        // CRYSTAL — geode interior, layered facets at multiple scales
        float v1 = voronoi(uv * 8.0 + seed * 50.0);
        float v2 = voronoi(uv * 20.0 + seed * 30.0); // smaller crystal inclusions
        float edge = smoothstep(0.05, 0.0, v1) * 0.5;
        float face = smoothstep(0.4, 0.1, v1) * 0.12;
        // Inner crystal detail — smaller gems embedded in faces
        float inner = smoothstep(0.06, 0.0, v2) * 0.2 * smoothstep(0.15, 0.3, v1);
        // Faint prismatic shimmer across faces
        float shimmer = vnoise(uv * 30.0 + seed * 20.0) * 0.08 * smoothstep(0.3, 0.1, v1);
        return edge + face + inner + shimmer;

    } else if (layerType < 2.0) {
        // FUNGAL — mycelium networks, glowing nodules, spore clouds
        float f = fbm(uv * 4.0 + seed * 30.0);
        float f2 = fbm(uv * 12.0 + seed * 50.0); // fine detail
        // Mycelium threads — thin bright lines
        float thread = smoothstep(0.48, 0.50, f) * 0.35;
        // Glowing nodules where threads converge
        float nodule = smoothstep(0.65, 0.75, f) * 0.5;
        nodule *= 0.7 + 0.3 * sin(t * 0.15 + f * 8.0);
        // Spore haze — fine texture overlay
        float spore = smoothstep(0.6, 0.75, f2) * 0.12;
        // Larger ambient glow in dense areas
        float ambient = smoothstep(0.45, 0.65, f) * 0.1;
        return thread + nodule + spore + ambient;

    } else if (layerType < 3.0) {
        // RUINS — dead city plan, aqueducts, walls, still-powered nodes
        vec2 ruinUV = uv * 15.0 + seed * 40.0;
        // Geological warp — the city is buckled and folded
        ruinUV += vec2(vnoise(ruinUV * 0.2) * 2.5, vnoise(ruinUV * 0.2 + 77.0) * 2.5);
        vec2 cell = fract(ruinUV);
        vec2 ci = floor(ruinUV);
        // Walls at varied thickness
        float wallW = 0.42 + hash21(ci) * 0.05;
        float gx = smoothstep(0.06, 0.0, abs(cell.x - 0.5) - wallW);
        float gy = smoothstep(0.06, 0.0, abs(cell.y - 0.5) - wallW);
        float grid = max(gx, gy);
        // Fragmentary — buried unevenly
        float mask = smoothstep(0.30, 0.65, vnoise(ruinUV * 0.12 + seed * 10.0));
        grid *= mask;
        // Room interiors — faint floor texture in some cells
        float roomH = hash21(ci + seed * 55.0);
        float floor_ = step(0.4, roomH) * vnoise(ruinUV * 3.0) * 0.06 * mask;
        // Still-powered nodes — faint flicker
        float nodeH = hash21(ci + seed * 99.0);
        float node = step(0.90, nodeH) * smoothstep(0.35, 0.0, length(cell - 0.5));
        node *= 0.4 + 0.6 * sin(t * 0.4 + nodeH * 20.0);
        // Connecting lines between nodes (aqueducts/conduits)
        float conduit = step(0.85, nodeH) * smoothstep(0.08, 0.0, abs(cell.y - 0.5)) * mask * 0.2;
        return grid * 0.35 + node * 0.3 + floor_ + conduit;

    } else if (layerType < 4.0) {
        // VOID — the space between kalpas. Faint stars, distant impossible geometry
        vec2 starUV = uv * 40.0 + seed * 100.0;
        vec2 ci = floor(starUV);
        float h = hash21(ci);
        float star = step(0.95, h) * smoothstep(0.4, 0.0, length(fract(starUV) - 0.5));
        star *= 0.3 + 0.7 * sin(t * 0.1 + h * 30.0);
        // Faint nebula-like wisps
        float wisp = fbm(uv * 6.0 + seed * 40.0);
        wisp = smoothstep(0.5, 0.7, wisp) * 0.08;
        // Distant structure — something geometric, impossibly far
        float ghostGrid = voronoiEdge(uv * 3.0 + seed * 20.0);
        float ghost = smoothstep(0.1, 0.0, ghostGrid) * 0.04;
        return star * 0.4 + wisp + ghost;

    } else {
        // MAGMA — deep earth heat, lava rivers in cracked stone
        float f = fbm(uv * 3.0 + seed * 20.0 + t * 0.005);
        float hot = smoothstep(0.4, 0.65, f) * 0.35;
        // Cracked stone — voronoi edges are the cracks
        float crack = voronoiEdge(uv * 5.0 + seed * 30.0);
        float lava = smoothstep(0.1, 0.0, crack) * 0.5;
        lava *= 0.7 + 0.3 * sin(t * 0.08 + f * 4.0);
        // Cooling crust on top of lava — darker patches
        float crust = vnoise(uv * 15.0 + seed * 60.0);
        crust = step(0.5, crust) * smoothstep(0.15, 0.0, crack) * 0.15;
        // Ember particles embedded in stone
        float ember = step(0.97, hash21(floor(uv * 50.0 + seed * 80.0)));
        ember *= 0.2 * (0.5 + 0.5 * sin(t * 0.3 + hash21(floor(uv * 50.0)) * 20.0));
        return hot + lava - crust + ember;
    }
}

// Barrel distortion — thick curved glass
vec2 barrel(vec2 uv, float k) {
    vec2 c = uv - 0.5;
    float r2 = dot(c, c);
    return uv + c * r2 * k;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 rawUV = fragCoord / iResolution.xy;

    // Barrel distortion for strata only — text stays crisp and bounded
    vec2 uv = barrel(rawUV, BARREL_STRENGTH);
    // Terminal text sampled undistorted so it never escapes the frame
    vec4 term = texture(iChannel0, rawUV);
    float t = iTime;

    // === DESCENT ===
    float descent = t * DESCENT_SPEED;

    // Warp the layer boundaries with noise — geological folding
    // The warp is baked into the rock: use scrolling Y so it moves with the stone
    float scrollY = uv.y * LAYER_SCALE + descent;
    float warp = fbm(vec2(uv.x * 2.0, scrollY * 2.0)) * 0.25;
    float depth = scrollY + warp;

    // === WHICH WORLD ARE WE IN ===
    float layerID = floor(depth);
    float layerFrac = fract(depth);
    float layerSeed = hash11(layerID);
    float nextSeed = hash11(layerID + 1.0);

    // 5 world types, deterministic per layer
    float layerType = floor(mod(layerID * 3.0 + layerSeed * 2.0, 5.0));
    float nextType = floor(mod((layerID + 1.0) * 3.0 + nextSeed * 2.0, 5.0));

    // === LAYER BOUNDARY — organic, geological ===
    float edgeDist = min(layerFrac, 1.0 - layerFrac);
    // Soft wide transition between worlds
    float blend = smoothstep(0.0, 0.2, layerFrac); // 0 at top of layer, 1 deeper in
    float seam = smoothstep(0.03, 0.0, edgeDist) * 0.3;

    // === TEXTURE EACH WORLD ===
    // Offset UV so textures are baked into the rock, scrolling with descent
    vec2 rockUV = vec2(uv.x, uv.y + descent / LAYER_SCALE);
    float tex = layerTexture(layerType, rockUV, depth, layerSeed, t);
    float nextTex = layerTexture(nextType, rockUV, depth, nextSeed, t);

    // Blend textures near boundary
    float boundaryBlend = smoothstep(0.0, 0.15, layerFrac) * smoothstep(1.0, 0.85, layerFrac);
    tex = mix(nextTex, tex, boundaryBlend);

    // === COLOR ===
    vec3 baseColor = layerPalette(layerType, layerSeed);
    vec3 nextColor = layerPalette(nextType, nextSeed);
    vec3 color = mix(nextColor, baseColor, boundaryBlend);

    // Seam glow — faintly brighter at world boundaries
    vec3 seamColor = mix(baseColor, nextColor, 0.5) * 3.0 + 0.1;

    // === FALLING MOTES ===
    float motes = 0.0;
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float speed = MOTE_SPEED * (0.7 + fi * 0.3);
        float scale = 3.0 + fi * 1.5;
        vec2 mp = fragCoord.xy / scale;
        mp.y -= t * speed;
        mp.x += sin(mp.y * 0.02 + fi * 2.0) * 8.0;
        vec2 cell = floor(mp);
        float h = hash21(cell + fi * 77.0);
        if (h > 0.993) {
            vec2 center = cell + 0.5;
            float d = length(mp - center);
            motes += smoothstep(0.5, 0.0, d) * (0.2 + 0.15 * fi);
        }
    }

    // === COMPOSE ===
    vec3 bg = color * BG_BRIGHTNESS;
    bg += color * tex;
    bg += seam * seamColor;
    bg += motes * (color * 2.0 + 0.1);

    // === VIEWPORT ===
    // The terminal is a viewport in a descending craft.
    // Viewport opening follows the barrel curve — the glass IS curved
    float aspect = iResolution.x / iResolution.y;
    vec2 centered = (uv - 0.5) * vec2(aspect, 1.0);     // distorted — shapes the opening
    vec2 rawCentered = (rawUV - 0.5) * vec2(aspect, 1.0); // undistorted — for frame texture
    // Rounded rectangle SDF — box fits the screen minus the frame width
    vec2 boxSize = vec2(aspect * 0.5, 0.5) - FRAME_WIDTH;
    float cornerR = 0.02;
    vec2 q = abs(centered) - boxSize + cornerR;
    float boxDist = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - cornerR;
    // Viewport mask: 1.0 inside the window, fading to 0 at frame
    float viewport = 1.0 - smoothstep(-VIEWPORT_SOFT, 0.01, boxDist);

    // === FRAME — corroded wrought iron ===
    float inFrame = smoothstep(-0.01, 0.005, boxDist);
    vec2 frameUV = rawCentered;

    // Forged iron base — pitted, uneven surface
    float ironBase = fbm(frameUV * 6.0 + 17.0);
    // Pitting — small dark holes in the metal
    float pits = vnoise(frameUV * 50.0);
    pits = smoothstep(0.65, 0.70, pits) * 0.3;
    // Hammered texture — broad dents
    float hammered = vnoise(frameUV * 12.0 + 5.0) * 0.2;
    // Rust patches — warm brown breaking through the dark iron
    float rust = fbm(frameUV * 8.0 + 33.0);
    rust = smoothstep(0.45, 0.65, rust);
    // Scale/flaking at edges
    float flake = vnoise(frameUV * 30.0);
    flake = smoothstep(0.6, 0.7, flake) * rust * 0.2;

    // Iron color — very dark, cold, nearly black
    vec3 ironDark = vec3(0.015, 0.015, 0.02);   // blackened iron
    vec3 ironMid = vec3(0.04, 0.035, 0.035);    // worn iron
    vec3 rustColor = vec3(0.06, 0.025, 0.01);   // dark rust, barely warm
    vec3 frameIron = mix(ironDark, ironMid, ironBase * 0.4 + hammered);
    frameIron -= pits * 0.5;
    // Rust — just hints, not patches
    frameIron = mix(frameIron, rustColor, rust * 0.2);
    frameIron += flake;

    // Faint cold highlight — barely there
    float highlight = smoothstep(0.2, -0.3, rawCentered.x + rawCentered.y) * 0.02;
    frameIron += vec3(0.02, 0.02, 0.03) * highlight;

    // === HARD LIP — sharp iron edge biting into glass ===
    float lip = smoothstep(0.004, 0.001, abs(boxDist));              // thin bright line right at the boundary
    float lipShadow = smoothstep(0.0, -0.012, boxDist) * (1.0 - smoothstep(-0.012, -0.025, boxDist));
    vec3 lipColor = vec3(0.12, 0.11, 0.09) * lip;                    // cold bright edge
    vec3 shadowColor = -vec3(0.06) * lipShadow;                      // hard shadow inside

    // === GLASS ===
    // Grime and soot on old glass — not bright frost, dark residue
    float grime = fbm(uv * 10.0 + 7.7);
    grime = grime * 0.4 + fbm(uv * 25.0 + 3.3) * 0.3;
    // More grime near edges, clearer in center
    float grimeMask = smoothstep(0.12, 0.0, -boxDist) * 0.6 + 0.08;
    grime *= grimeMask;
    float grimeAmount = grime * 0.2;
    // Faint cold sheen on the glass
    float sheen = centered.x * 0.6 + centered.y * 0.4;
    float glassSheen = smoothstep(-0.3, 0.1, sheen) * smoothstep(0.5, 0.1, sheen);
    glassSheen *= 0.015 * viewport;

    // === TEXT AS HUD ON GLASS ===
    float textLuma = dot(term.rgb, vec3(0.299, 0.587, 0.114));
    vec3 textColor = term.rgb;
    // Text is projected on the glass — tinted by what's outside
    textColor = mix(textColor, textColor * (color * 3.0 + 0.7), TEXT_TINT);
    // Text glows faintly — it's a display, emitting light
    float textGlow = textLuma * 0.06;

    // === COMPOSE ===
    // Grime darkens the view through the glass — soot, not frost
    vec3 grimeColor = vec3(0.02, 0.02, 0.01);
    vec3 grimedBg = mix(bg, grimeColor, grimeAmount * viewport);

    // Strata through viewport, iron frame outside
    vec3 col = mix(frameIron, grimedBg, viewport);
    // Hard metal lip at frame/glass boundary
    col += lipColor;
    col += shadowColor;
    // Glass sheen
    col += glassSheen;
    // Text renders freely — frame is thin enough to stay out of the way
    col = mix(col, textColor, textLuma * 0.94);
    // Text emits a tiny amount of light onto the glass
    col += textGlow * color * viewport;

    fragColor = vec4(col, term.a);
}
