# Palimpsest

A collection of custom shaders for [Ghostty](https://ghostty.org) terminal.

These shaders use Ghostty's `custom-shader` system to transform terminal rendering — adding volumetric smoke, wave simulations, rain, geological descent, and more. Several shaders include Metal compute kernels for GPU-accelerated particle/fluid simulation via a feedback-buffer texture pipeline.

## Requirements

**Ghostty with compute shader support.** The compute shaders (`.compute.msl`) require the `feature/feedback-buffer` branch from [unity-hallie/ghostty](https://github.com/unity-hallie/ghostty/tree/feature/feedback-buffer), which adds:

- Feedback buffer (`iChannel1`) — previous frame's output, readable as a texture
- Metal compute shader pipeline (`iChannel2`) — `rgba16f` state texture for simulations
- Compute shaders are auto-discovered by naming convention: `smoke.glsl` automatically loads `smoke.compute.msl`

Shaders that don't use compute or feedback (like `astrolabe.glsl`) work on stock Ghostty.

## Shaders

### smoke.glsl + smoke.compute.msl
Volumetric particle smoke driven by terminal text luminance. Text radiates heat as brownian curl noise agitation; energy diffuses, advects, and drives warm ember glow. Bisexual edge lighting (magenta/cyan) with per-terminal rotation. Focus dim on unfocused windows.

### palimpsest.glsl
Aged paper with physarum ink veins. Text strokes bleed into self-organizing vein networks via feedback. Glitter ink, lavender halo seep, per-terminal personality from content hash.

### ripple.glsl + ripple.compute.msl
Viscoelastic wave equation on terminal content. Non-Newtonian shear-thinning, plasticity (settled peaks hold shape), optional convection currents. Cyberpunk palette.

### downpour.glsl
Rain on dirty glass. Procedural rivulets with tributaries, chromatic aberration, subpixel RGB through water lensing, feedback-driven grime accumulation.

### typewriter.glsl
Bond paper + ribbon ink. Feedback-driven mycelium growth along fiber channels, water drops with pseudopod surface tension, compound UV distortion, downpour storms.

### glasshouse.glsl
Frosted glass at night overlooking a procedural garden in a storm. Rain rivulets with overlapping generation system, stationary drops, HUD-style terminal text with glow halo.

### kalpa.glsl
Descent through geological time. Impossibly slow elevator through five dead world layers (crystal, fungal, ruins, void, magma). Corroded iron viewport, barrel distortion, grime on glass.

### terraform.glsl
Planetary terraforming with day/night cycle, biomes, rivers, aurora, campfires. Double-warped fbm terrain.

### astrolabe.glsl
Mechanical astrolabe with hyperspace starfield background. No compute shader needed.

## Usage

```
# ~/.config/ghostty/config
custom-shader = /path/to/palimpsest/smoke.glsl
custom-shader-animation = always
```

Only list the `.glsl` file — Ghostty finds the `.compute.msl` automatically.

## Ghostty Shader API

Shaders receive standard Shadertoy-style uniforms (`iTime`, `iResolution`, `iMouse`) plus Ghostty extensions:

| Uniform | Description |
|---------|-------------|
| `iChannel0` | Terminal content texture |
| `iChannel1` | Feedback buffer (previous frame output) |
| `iChannel2` | Compute state texture (`rgba16f`) |
| `iCurrentCursor` | xy=pixel pos, zw=width/height |
| `iPreviousCursor` | Cursor position one change ago |
| `iTimeCursorChange` | Timestamp of last cursor move |
| `iTimeFocus` | Timestamp of last focus change |
| `iFocus` | 1=focused, 0=unfocused |
| `iPalette[256]` | Full 256-color palette |
| `iBackgroundColor` | Background color from config |
| `iForegroundColor` | Foreground color from config |
| `iCursorColor` | Cursor color from config |

Compute shaders are plain Metal (`.compute.msl`), not GLSL. Texture bindings: `t0`=terminal, `t2`=feedback, `t3`=state read, `t8`=state write.
