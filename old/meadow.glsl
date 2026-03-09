// Meadow
// Wild grass grows in tufts. Text wears paths through it.
// Individual blade shapes, ground cover moss, wildflowers.
// Blades lean away from text at the mow edge.
//
// iChannel0 = terminal

// ====== TUNE THESE ======
#define MOW_RADIUS      22.0
#define CELL_SIZE       8.0      // Pixels per blade cell
#define BLADE_MIN_H     18.0     // Shortest blade (pixels)
#define BLADE_MAX_H     50.0     // Tallest blade (pixels)
#define BLADE_WIDTH     3.0      // Blade thickness (pixels)
#define WIND_SPEED      0.8
#define WIND_STRENGTH   10.0     // Pixels of tip sway
#define TUFT_SCALE      4.0      // Clump size
#define TUFT_THRESHOLD  0.50     // Sparseness
#define SUN_DIR         vec3(0.5, -0.7, 0.6)

// Flowers
#define FLOWER_CELL     40.0     // Flower grid size (pixels) — bigger = rarer
#define FLOWER_CHANCE   0.25     // Probability a cell gets a flower
// =========================

float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
        mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x),
        f.y
    );
}

float fbm(vec2 p) {
    return vnoise(p) * 0.5 + vnoise(p * 2.1 + 1.7) * 0.25
         + vnoise(p * 4.3 + 3.1) * 0.125;
}

float luma(vec3 c) {
    return dot(c, vec3(0.299, 0.587, 0.114));
}

// Returns (distance 0-1, direction to nearest text x, direction y)
vec3 textInfo(vec2 uv, vec2 px) {
    float radius = MOW_RADIUS * px.x;
    if (luma(texture(iChannel0, uv).rgb) > 0.08) return vec3(0.0);
    float minD = 1.0;
    vec2 dir = vec2(0.0);
    for (int r = 1; r <= 3; r++) {
        float d = radius * float(r) / 3.0;
        for (int i = 0; i < 8; i++) {
            float a = float(i) * 0.7854;
            vec2 offset = vec2(cos(a), sin(a)) * d;
            if (luma(texture(iChannel0, uv + offset).rgb) > 0.08) {
                float nd = float(r) / 3.0;
                if (nd < minD) {
                    minD = nd;
                    dir = -normalize(offset); // direction AWAY from text
                }
            }
        }
    }
    return vec3(minD, dir);
}

// Blade shape — returns (coverage, progress 0-1, normal x offset)
vec3 blade(vec2 fragCoord, vec2 root, float height, float lean, float wind, float width) {
    float prog = (root.y - fragCoord.y) / height;
    if (prog < 0.0 || prog > 1.0) return vec3(0.0);
    float curve = (lean + wind) * prog * prog;
    float bladeX = root.x + curve;
    float dx = fragCoord.x - bladeX;
    float w = width * (1.0 - prog * 0.6);
    float coverage = smoothstep(w, w * 0.3, abs(dx));
    return vec3(coverage, prog, dx / max(w, 0.1));
}

// Flower petal shape — SDF for a 5-petal flower
float flowerSDF(vec2 p, float size) {
    float r = length(p);
    float a = atan(p.y, p.x);
    // 5 petals
    float petals = cos(a * 5.0) * 0.3 + 0.7;
    float petal = r / (size * petals);
    return petal;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec2 px = 1.0 / iResolution.xy;
    vec4 term = texture(iChannel0, uv);
    float t = iTime;

    // === MOW ZONE ===
    vec3 textInf = textInfo(uv, px);
    float dist = textInf.x;
    vec2 awayDir = textInf.yz;
    float growth = smoothstep(0.0, 0.8, dist);

    // === TUFT MAP ===
    float tuftMap = fbm(uv * TUFT_SCALE);
    float tuftPresence = smoothstep(TUFT_THRESHOLD, TUFT_THRESHOLD + 0.2, tuftMap) * growth;

    // === GROUND ===
    float soil = fbm(uv * 35.0);
    vec3 ground = mix(vec3(0.07, 0.05, 0.03), vec3(0.11, 0.08, 0.04), soil);
    ground += vnoise(uv * 180.0) * 0.012;
    // Worn path near text
    ground = mix(ground, vec3(0.08, 0.06, 0.035), (1.0 - growth) * 0.3);

    // === GROUND COVER — patchy, visible ===
    float patchN = vnoise(uv * 18.0 + 5.5);
    float breakup = vnoise(uv * 45.0 + 22.0);
    float patch = step(0.38, patchN) * step(0.28, breakup) * growth;
    // Color varies smoothly, no branching
    float patchHue = vnoise(uv * 12.0 + 7.0);
    vec3 patchCol = mix(vec3(0.10, 0.22, 0.05), vec3(0.16, 0.18, 0.06), patchHue);
    patchCol += vnoise(uv * 80.0) * 0.06;
    ground = mix(ground, patchCol, patch * 0.8);

    // === RENDER BLADES ===
    vec3 bladeCol = ground;
    float topProg = 0.0;

    vec3 lushGreen = vec3(0.15, 0.40, 0.06);
    vec3 paleGreen = vec3(0.28, 0.42, 0.10);
    vec3 dryYellow = vec3(0.38, 0.34, 0.10);
    vec3 deadBrown = vec3(0.20, 0.15, 0.06);
    vec3 darkBase  = vec3(0.04, 0.15, 0.02);

    vec2 cellCoord = fragCoord / CELL_SIZE;
    vec2 cellID = floor(cellCoord);

    for (int cy = -7; cy <= 1; cy++) {
        for (int cx = -4; cx <= 4; cx++) {
            vec2 cid = cellID + vec2(float(cx), float(cy));
            float h = hash21(cid);
            if (h > 0.55) continue;

            vec2 cellUV = (cid + 0.5) * CELL_SIZE / iResolution.xy;
            float cellTuft = fbm(cellUV * TUFT_SCALE);
            // Use the pixel's own growth/direction — avoids per-cell texture spam
            float cellGrowth = growth;
            vec2 cellAway = awayDir;
            float cellPresence = smoothstep(TUFT_THRESHOLD, TUFT_THRESHOLD + 0.2, cellTuft) * cellGrowth;
            if (cellPresence < 0.1) continue;

            float bh = hash21(cid + 73.0);
            float bladeH = mix(BLADE_MIN_H, BLADE_MAX_H, bh) * cellPresence;

            // Lean: natural lean + push away from text at mow edge
            float naturalLean = (hash21(cid + 137.0) - 0.5) * 20.0;
            float pushStrength = (1.0 - cellGrowth) * 25.0; // stronger push near text
            float pushLean = cellAway.x * pushStrength;
            float bladeLean = naturalLean + pushLean;

            float bladeW = BLADE_WIDTH * (0.7 + hash21(cid + 211.0) * 0.6);

            vec2 root = vec2(
                (cid.x + 0.2 + h * 0.6) * CELL_SIZE,
                (cid.y + 1.0) * CELL_SIZE
            );

            float wind = sin(t * WIND_SPEED + cid.x * 0.7 + cid.y * 0.3) * WIND_STRENGTH * cellPresence;

            vec3 b = blade(fragCoord, root, bladeH, bladeLean, wind, bladeW);
            float coverage = b.x;
            float prog = b.y;
            float nx = b.z;
            if (coverage < 0.01) continue;

            float hue = hash21(cid + 317.0);
            vec3 tipCol;
            if      (hue < 0.35) tipCol = lushGreen;
            else if (hue < 0.55) tipCol = paleGreen;
            else if (hue < 0.75) tipCol = dryYellow;
            else                 tipCol = deadBrown;

            vec3 col = mix(darkBase, tipCol, prog);
            vec3 normal = normalize(vec3(nx * 0.6, -0.2 + prog * 0.4, 1.0));
            vec3 sun = normalize(SUN_DIR);
            float diff = max(dot(normal, sun), 0.0);
            float sss = pow(max(dot(vec3(-normal.xy, normal.z), sun), 0.0), 4.0) * 0.2;
            col *= 0.35 + diff * 0.5 + sss;
            col += tipCol * 0.15 * smoothstep(0.7, 1.0, prog);

            if (coverage > 0.1) {
                bladeCol = mix(bladeCol, col, coverage * smoothstep(topProg - 0.1, topProg + 0.1, prog));
                topProg = max(topProg, prog * coverage);
            }
        }
    }

    // === WILDFLOWERS ===
    // Sparse grid of potential flower positions
    vec2 flowerGrid = fragCoord / FLOWER_CELL;
    vec2 flowerID = floor(flowerGrid);

    // Check this cell and neighbors (flowers can be at cell edges)
    for (int fy = -1; fy <= 1; fy++) {
        for (int fx = -1; fx <= 1; fx++) {
            vec2 fid = flowerID + vec2(float(fx), float(fy));
            float fh = hash21(fid + 500.0);

            // Only some cells get flowers
            if (fh > FLOWER_CHANCE) continue;

            // Flower position within cell
            vec2 flowerPos = (fid + vec2(
                0.2 + hash21(fid + 600.0) * 0.6,
                0.2 + hash21(fid + 700.0) * 0.6
            )) * FLOWER_CELL;

            // Check if this flower is in grass (not on path)
            vec2 flowerUV = flowerPos / iResolution.xy;
            float flowerGrowth = growth; // reuse pixel's growth
            float flowerTuft = fbm(flowerUV * TUFT_SCALE);
            if (flowerGrowth < 0.5) continue; // no flowers on paths
            if (flowerTuft < TUFT_THRESHOLD - 0.1) continue; // only in grassy areas

            // Flower type from hash
            float flowerType = hash21(fid + 800.0);

            // Distance from pixel to flower center
            vec2 fp = fragCoord - flowerPos;

            // Gentle sway with wind
            float fWind = sin(t * WIND_SPEED * 0.7 + fid.x * 1.3 + fid.y * 0.8) * 3.0;
            fp.x -= fWind * 0.3;

            float fr = length(fp);
            float flowerSize = 3.5 + hash21(fid + 900.0) * 2.5; // 3.5 to 6 pixels

            if (fr > flowerSize * 2.0) continue;

            // Flower shape
            float fa = atan(fp.y, fp.x);
            vec3 flowerCol;

            if (flowerType < 0.3) {
                // DAISY — white petals, yellow center
                float petals = cos(fa * 5.0 + hash21(fid + 1000.0) * 3.0) * 0.25 + 0.75;
                float petal = smoothstep(flowerSize * petals, flowerSize * petals - 1.5, fr);
                float center = smoothstep(flowerSize * 0.35, flowerSize * 0.25, fr);
                vec3 petalCol = vec3(0.85, 0.82, 0.75); // cream white
                vec3 centerCol = vec3(0.75, 0.65, 0.15); // warm yellow
                flowerCol = mix(petalCol, centerCol, center);
                float mask = petal;
                // Normal — dome shape
                vec3 fn = normalize(vec3(fp / flowerSize * 0.5, 1.0));
                float fLight = max(dot(fn, normalize(SUN_DIR)), 0.0) * 0.4 + 0.6;
                flowerCol *= fLight;
                // Shadow underneath petals
                flowerCol *= 0.85 + 0.15 * center;
                bladeCol = mix(bladeCol, flowerCol, mask * flowerGrowth);

            } else if (flowerType < 0.55) {
                // BUTTERCUP — glossy yellow, small
                float sz = flowerSize * 0.7;
                float petals = cos(fa * 5.0 + hash21(fid + 1100.0) * 2.0) * 0.2 + 0.8;
                float petal = smoothstep(sz * petals, sz * petals - 1.2, fr);
                float center = smoothstep(sz * 0.3, sz * 0.2, fr);
                vec3 petalCol = vec3(0.85, 0.75, 0.05); // bright yellow
                vec3 centerCol = vec3(0.6, 0.45, 0.02); // darker yellow
                flowerCol = mix(petalCol, centerCol, center);
                // Glossy highlight
                vec3 fn = normalize(vec3(fp / sz * 0.4, 1.0));
                float spec = pow(max(dot(reflect(-normalize(SUN_DIR), fn), vec3(0,0,1)), 0.0), 8.0);
                float fLight = max(dot(fn, normalize(SUN_DIR)), 0.0) * 0.4 + 0.6;
                flowerCol = flowerCol * fLight + vec3(0.9, 0.85, 0.4) * spec * 0.3;
                bladeCol = mix(bladeCol, flowerCol, petal * flowerGrowth);

            } else if (flowerType < 0.75) {
                // VIOLET — small purple, 5 petals
                float sz = flowerSize * 0.65;
                float petals = cos(fa * 5.0 + 0.6) * 0.3 + 0.7;
                float petal = smoothstep(sz * petals, sz * petals - 1.0, fr);
                float center = smoothstep(sz * 0.25, sz * 0.15, fr);
                vec3 petalCol = vec3(0.35, 0.15, 0.55); // purple
                // Lighter toward center
                petalCol = mix(petalCol, vec3(0.55, 0.35, 0.70), smoothstep(sz * 0.6, sz * 0.2, fr));
                vec3 centerCol = vec3(0.80, 0.70, 0.20); // yellow eye
                flowerCol = mix(petalCol, centerCol, center);
                vec3 fn = normalize(vec3(fp / sz * 0.3, 1.0));
                float fLight = max(dot(fn, normalize(SUN_DIR)), 0.0) * 0.3 + 0.7;
                flowerCol *= fLight;
                bladeCol = mix(bladeCol, flowerCol, petal * flowerGrowth);

            } else {
                // CLOVER FLOWER — tiny pink/white puff
                float sz = flowerSize * 0.5;
                float puff = smoothstep(sz, sz - 1.5, fr);
                // Fuzzy edge — irregular
                float fuzz = vnoise(fp * 2.0 + fid * 10.0);
                puff *= smoothstep(0.3, 0.5, fuzz);
                vec3 puffCol = mix(vec3(0.70, 0.45, 0.55), vec3(0.85, 0.75, 0.80), fuzz);
                // Tiny darker base
                puffCol = mix(puffCol, vec3(0.3, 0.15, 0.2), smoothstep(sz * 0.7, sz, fr) * 0.3);
                vec3 fn = normalize(vec3(fp / sz * 0.3, 1.0));
                float fLight = max(dot(fn, normalize(SUN_DIR)), 0.0) * 0.3 + 0.7;
                puffCol *= fLight;
                bladeCol = mix(bladeCol, puffCol, puff * flowerGrowth);
            }
        }
    }

    // === TEXT ===
    float textLuma = luma(term.rgb);
    vec3 finalCol = mix(bladeCol, term.rgb, textLuma * 0.94);

    fragColor = vec4(finalCol, 1.0);
}
