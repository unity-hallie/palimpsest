# palimpsest

Ghostty terminal shader experiments. Each shader is a named world.

## Structure

Each shader is a named set of files:
- `<name>.glsl` -- fragment shader (Shadertoy-style, iChannel0=terminal, iChannel2=compute state)
- `<name>.compute.msl` -- Metal compute shader (auto-loaded by Ghostty when present)
- `<name>.conf` -- Ghostty config (colors, font, shader path)

`shade <name>` copies `<name>.conf` to `~/.config/ghostty/config`.

## Critical: ASCII only in shader files

**Em dashes, smart quotes, box-drawing characters, and any non-ASCII in .glsl or .msl files cause silent compile failures.** The shader loads as all-zeros with no error output. Use `--` instead of `--`, plain quotes, plain hyphens.

To check a file: `python3 -c "open('f.glsl').read().encode('ascii')"` -- raises if non-ASCII present.

## Shaders

- **embers** -- burned-down ash field, slow breathing coals, fbm threshold background
- **abyss** -- bioluminescence in dark water, dinoflagellate emission with refractory period and drift
- **rain** -- current daily driver
- **ocean** -- Gerstner waves, boid fish school
- **mycelium**, **daisyworld**, and others in old/

## abyss notes

Compute state (rgba16f): R=disturbance, G=emission, B=drift clock, A=prev luma

Refractory period: emission self-gates via `readiness = 1 - smoothstep(0.15, 0.45, localEmission)`.
Two-rate decay: fast (0.92) above 0.5, slow (0.99992) below -- flash fades visually fast, refractory floor persists ~5 min.
Advection gated by readiness -- spent cells don't accept drifting light from neighbors.
