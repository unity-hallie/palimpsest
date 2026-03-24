# palimpsest

Ghostty terminal shader experiments. Each shader is a named world.

## Structure

Each shader is a named set of files:
- `<name>.glsl` -- fragment shader (Shadertoy-style, iChannel0=terminal, iChannel2=compute state)
- `<name>.compute.msl` -- Metal compute shader (auto-loaded by Ghostty when present)
- `<name>.conf` -- Ghostty config (colors, font, shader path)

`shade <name>` copies `<name>.conf` to `~/.config/ghostty/config`.

## Critical: no inline comments in .conf files

**Ghostty does not allow inline comments after values.** `background = f0ead8  # warm paper` will fail with a load error. Comments must be on their own lines starting with `#`.

Wrong: `background = f0ead8   # warm paper`
Right:
```
# warm paper
background = f0ead8
```

## Critical: ASCII only in shader files

**Em dashes, smart quotes, box-drawing characters, and any non-ASCII in .glsl or .msl files cause silent compile failures.** The shader loads as all-zeros with no error output. Use `--` instead of `--`, plain quotes, plain hyphens.

To check a file: `python3 -c "open('f.glsl').read().encode('ascii')"` -- raises if non-ASCII present.

## Shaders

Active (have .conf files, usable via `shade`):
- **abyss** -- bioluminescence in dark water, dinoflagellate emission; `abyss.conf`
- **aero** -- condensation on glass, Frutiger Aero; `aero.conf` (in progress)
- **astrolabe** -- mechanical astrolabe + starfield, no compute; `astrolabe.conf`
- **dodonpachi** -- Cave-style danmaku bullet curtain, Jamestown canyon background; `dodonpachi.conf`
- **embers** -- burned-down ash field, slow breathing coals; `embers.conf`
- **fog** -- drifting mist banks, lightweight no-compute; `fog.conf`
- **lichen** -- crustose lichen colonies on dark stone, domain-warped, 5-min colonization; `lichen.conf`
- **mycelium** -- physarum slime mold network; `mycelium.conf`
- **ocean** -- Gerstner waves, day/night cycle, boid fish school; `ocean.conf`
- **rain** -- compute-driven water flow on glass, solarpunk city; `rain-dark.conf`
- **scratch** -- scratch pad / testing; `scratch.conf`
- **strata** -- geological sediment layers with tectonic warping; `strata.conf`
- **tattoo** -- skin and ink; `tattoo-light.conf`, `tattoo-dark.conf`
- **tide** -- caustic light bands on cave ceiling, underwater refraction; `tide.conf`
- **typewriter** -- paper, ink bleed, mycelium memory, water drops; `typewriter-light.conf`

In `old/` or undocumented: daisyworld, downpour, glasshouse, kalpa, palimpsest, putty, ripple, smoke, terraform

`src/` contains precompiler source files -- run `./precompile` to build root .glsl/.msl files.

## render.py -- offline rendering

Renders shaders to PNG/GIF without Ghostty. Requires `pip3 install moderngl pillow`.

```bash
python3 render.py ocean.glsl -t 300         # ocean at noon
python3 render.py embers.glsl -t 30         # breathing ash
python3 render.py dodonpachi.glsl --light   # canyon (light bg shader)
python3 render.py abyss.glsl --compute abyss --compute-warmup 400
python3 render.py ocean.glsl -n 60 --gif    # 2s animation
```

Y-axis flip is handled -- shaders see fragCoord.y=0 at top, matching Ghostty.
`--compute abyss` runs `abyss_compute.py` (numpy port of `abyss.compute.msl`).

## abyss notes

Compute state (rgba16f): R=disturbance, G=emission, B=drift clock, A=prev luma

Refractory gate: hard threshold at 0.44 -- `readiness = localEmission < 0.44 ? 1.0 : 0.0`
Two-rate decay: fast (0.92) above 0.5, slow (0.99992) below -- flash fades in ~0.2s, refractory floor persists ~5 min.
Advection gated by readiness -- spent cells don't accept drifting light from neighbors.
Visual dimming: fragment applies `dimFactor = smoothstep(0.20, 0.55, emission)` -- only cells above 0.55 glow brightly.
The drama is in the flash event (emission > 0.7), not the steady floor.
