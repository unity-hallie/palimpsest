# Palimpsest

You spend hours a day staring at a terminal. Might as well nest.

Palimpsest is a collection of shaders for [Ghostty](https://ghostty.org) that turn your terminal into a place you want to be. Not a distraction — a room. Some of these are loud and some are quiet, but they all share the conviction that the text you're reading is sacred and everything else is atmosphere.

Several shaders run GPU-accelerated fluid and particle simulations via Metal compute kernels. Your terminal becomes a physics sandbox where the text itself is the heat source, the impulse, the thing that makes the smoke move and the waves ripple.

## The shaders

**smoke** — A room full of smoke. Text luminance radiates heat as brownian curl noise; energy diffuses and advects through a viscous fluid sim. Coriolis deflection spirals the smoke outward. A Lissajous breeze shifts the wind. Invisible thermals drift through, stirring convection cells you can't see but can feel. Bisexual edge lighting catches in the haze — magenta from one side, cyan from the other, different angle every terminal. Unfocused windows dim and desaturate like a room you've stepped out of.

**palimpsest** — Aged paper that remembers. Physarum-inspired ink veins self-organize through a feedback loop — text strokes bleed outward along paths of least resistance, building networks that look biological because they are (the algorithm is slime mold). Glitter ink catches iridescent light on the strokes. Each terminal develops a personality from a hash of its content, frozen in a corner pixel.

**ripple** — A viscoelastic wave equation running on your text. Type and the surface deforms. Non-Newtonian shear-thinning means fast motion flows easy, slow motion resists — and plasticity means peaks that settle hold their shape, like pressing a thumb into clay. Cyberpunk palette. The math is real continuum mechanics.

**downpour** — Rain on your monitor. Procedural rivulets run down the glass surface, refracting the terminal text beneath them with chromatic aberration and subpixel RGB patterns (you can see the LCD stripes through the water droplets, like looking through a magnifying glass at your screen). Water clears a slowly accumulating layer of grime. Some tributaries die partway down. The ones that survive widen as they go.

**typewriter** — Bond paper and ribbon ink. A feedback-driven mycelium network grows along the paper's fiber channels. Water drops land with pseudopod fingers that reach outward along surface tension gradients. Periodic downpour storms — 50 drops over 30 seconds, triangular onset, every few minutes. The paper remembers where the water was.

**glasshouse** — Frosted glass at night. Behind it, a procedural garden with warm lantern lights. Rain rivulets clear paths through the frost, and the garden distorts and sharpens where the water runs. Stationary drops sit between the rivulets. Your terminal text floats as a HUD with an 8-tap glow halo. It's 2am and you're working in a greenhouse and it's raining.

**kalpa** — You are in an elevator descending through geological time. Five dead world layers pass outside a corroded iron viewport: crystal, fungal, ruins, void, magma. Barrel distortion. Grime on the glass. It descends impossibly slowly. Dark Souls aesthetic. Named for the Hindu unit of time — 4.32 billion years, one day in the life of Brahma.

**terraform** — Watching a planet come alive. Day/night cycle, biomes emerging, rivers finding their paths, aurora overhead, campfires in the dark. The terrain is double-warped fractal brownian motion. The heaviest shader in the collection.

**astrolabe** — A mechanical astrolabe turning against a hyperspace starfield. The simplest shader here — no compute, no feedback. Just geometry and stars.

## Requirements

Most shaders with `.compute.msl` files need the [`feature/feedback-buffer`](https://github.com/unity-hallie/ghostty/tree/feature/feedback-buffer) branch of [a Ghostty fork](https://github.com/unity-hallie/ghostty) that adds:

- **Feedback buffer** (`iChannel1`) — previous frame's output, readable as texture
- **Compute shader pipeline** (`iChannel2`) — `rgba16f` state texture for simulations
- **Auto-discovery** — name your compute shader `foo.compute.msl` next to `foo.glsl`

Shaders that don't need compute or feedback (like `astrolabe.glsl`) work on stock Ghostty.

## Usage

```bash
# ~/.config/ghostty/config
custom-shader = /path/to/palimpsest/smoke.glsl
custom-shader-animation = always
```

Only point at the `.glsl` — Ghostty finds the `.compute.msl` automatically. If you point at the `.msl` directly, Ghostty tries to compile it as GLSL and fails.

## Notes for shader writers

The Ghostty shader API is Shadertoy-compatible (`iTime`, `iResolution`, `iMouse`, `mainImage`) with extensions:

| | |
|---|---|
| `iChannel0` | Terminal content |
| `iChannel1` | Feedback buffer (your previous frame) |
| `iChannel2` | Compute state (`rgba16f`) |
| `iFocus` / `iTimeFocus` | Window focus state and transition timestamp |
| `iCurrentCursor` / `iPreviousCursor` | Cursor position (xy=pixel, zw=size) |
| `iTimeCursorChange` | When the cursor last moved (absolute time) |
| `iPalette[256]` | The full terminal color palette |
| `iBackgroundColor` / `iForegroundColor` / `iCursorColor` | From your config |

Compute shaders are plain Metal, not GLSL. `#include <metal_stdlib>`, `kernel void computeMain(...)`. Texture bindings: 0=terminal, 2=feedback, 3=state read, 8=state write.

Things we learned the hard way:

- `terminal.a` is always 1.0. Use luminance to detect text.
- `iDate` is never updated. Always zero. Don't use it for seeding.
- Y is flipped — y=0 is the top of the screen.
- Feedback alpha is unreliable (used for window compositing). Store state in RGB.
- `rgba16f` is half-float. If you accumulate time, it loses precision past ~32. Wrap it.
- Velocity in a fluid sim jitters frame-to-frame. Never read it in the display shader. Smooth it in compute with a temporal EMA and read that.
- One pixel can be a clock. Reserve pixel (0,0), early-return from the sim, store your frame counter there.

## Credit

Built by a human and a language model, iterating in real time on a terminal we couldn't always read because the smoke was too thick. The flying toasters turned into whales and the whales turned into thermals and the thermals were better than both.
