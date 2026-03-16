# tattoo.glsl — notes

Skin as terminal substrate. Text as ink aging in the dermis.

## Concept

- Background = skin. Color and tone derived continuously from `iBackgroundColor` via a 2D chromophore model: melanin concentration (dark bg → more melanin) on one axis, warmth/coolness (bg r-b chroma) on the other.
- Text = ink embedded in dermis, not sitting on top. Core always reads as actual terminal color. Surrounding halo sinks into skin and thins out.
- Age = two compounding axes: scroll position (top = older) + realtime drift (`iTime`). Posterized into discrete bands.
- Older ink: edges spread outward (radial gaussian bleed), blue-shift (red pigment fades faster in real tattoos).

## What works
- Chromophore model: light bg → Nordic/fair skin, dark bg → deep skin, warmth shifts undertone. Continuous, no presets needed.
- `iBackgroundColor` for bg detection (much more reliable than corner sampling)
- Ink detection by color distance from bg — catches colored text, not just dark/luma
- Radial gaussian bleed (not square grid — no geometric artifacts)
- Crisp core always reads, halo darkens skin around glyphs and fades out
- Tiny AA pass on ink edge
- Fine grain only (high-frequency FBM), no large patches

## What's parked
- **Veins**: FBM can't make branching structures. Needs a different algorithm (Worley ridges, reaction-diffusion, or explicit curve generation). Removed for now.
- **Per-row timestamps**: not possible in shaderspace without Ghostty fork changes. Using Y-position as age proxy instead.
- **Scroll continuity**: text jumps age bands when scrolling — considered a feature (skin alive/moving).

## Key tuning params
- `BASE_AGE` — how aged the top of screen is (currently 1.5)
- `BLEED_MAX` — max bleed radius in pixels at oldest age (currently 2.5)
- `DRIFT_RATE` — realtime aging speed (currently 0.012/sec)
- `BLUE_SHIFT_MAX` — how blue aged ink gets (currently 0.5)
- `AGE_BANDS` — discrete posterization steps (currently 5)

## Config
`tattoo-light.conf` — warm parchment bg, black ink (Scandinavian skin)
`tattoo-dark.conf` — deep warm bg, faded ink (high melanin skin)
Both are standalone Ghostty configs (not importable — Ghostty has no config-file directive).
To switch: change background/foreground in main Ghostty config per comments in Shader section.
