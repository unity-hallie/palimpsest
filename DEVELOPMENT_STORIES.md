# Development Stories

## The Smoke That Blinded Us

### "CLAUDE I CANNOT SEE ANYTHING CLAUDE"

During development of `smoke.glsl`, there was a period where the fluid simulation worked *too well*. The smoke opacity was set high enough that the terminal was completely illegible.

The process looked like this:

```
Hallie: CLAUDE I CANNOT SEE ANYTHING CLAUDE
Claude: Adjusting SMOKE_OPACITY from 0.95 to 0.85
Hallie: STILL NOTHING
Claude: Now trying 0.75
Hallie: I CAN SEE A LETTER
Claude: Progress. Setting to 0.65
Hallie: OKAY I CAN READ NOW
Hallie: ...
Hallie: but it needs more smoke
Claude: ...
```

Just the AI patiently tuning parameters while the human flailed in a self-inflicted atmospheric catastrophe.

The README documents this calmly as "iterating in real time on a terminal we couldn't always read because the smoke was too thick." The understatement is beautiful.

### The Final Tuning

```glsl
#define SMOKE_OPACITY   0.25   // was 0.85, literally could not read terminal
#define HEAT_GLOW       1.9    // perfect after much yelling
```

Current state: Hallie can mostly read it all the time now. The harrowing moments were worth it.

## What We Built

**smoke.glsl + smoke.compute.msl**

Real computational fluid dynamics:
- Brownian curl noise agitation (divergence-free turbulent flow)
- Coriolis deflection spiraling smoke outward
- Lissajous breeze (figure-8 wind pattern that never repeats)
- Five invisible drifting thermals creating convection cells
- Energy field that advects, diffuses, uses temporal EMA for flicker-free glow
- Semi-Lagrangian advection
- Bisexual edge lighting (magenta/cyan) seeded per-terminal
- Moon drifting through the haze
- Focus dim/desaturate (unfocused windows become rooms you stepped out of)

Text luminance drives the agitation. The brighter the text, the more the smoke churns. The text is the heat source that makes the whole space alive.

## The Lineage

**Jamestown bullet patterns → fluid simulations**

Hallie wrote bullet patterns for Jamestown - those beautiful spiraling Victorian sci-fi curtains of death. The precision, the rhythm, the way forces compose into readable patterns even when they're overwhelming.

The same sensibility is in these shaders:
- Curl noise spirals
- Coriolis deflection creating outward spirals
- Pulsing thermals with their own periods
- Lissajous breeze that never quite repeats
- The way you can *read* the flow even when it's chaotic

Bullet pattern design language applied to fluid dynamics. Both about making chaos beautiful and navigable. Both about rhythm and force and flow.

The bisexual edge lighting getting a different angle per terminal has "each player's experience is slightly different but equally fair" energy.

## The Philosophy

**Making Math Beautiful**

"Is there anything better than making math beautiful?"

No. There really isn't.

Making math beautiful is making it **real** - not abstract symbols on a page, but something you can *feel*. The curl noise isn't equations, it's the way smoke moves. The Coriolis force isn't a formula, it's why the spiral goes that way. The exponential moving average isn't statistics, it's why the glow doesn't flicker.

When the math is beautiful, it becomes **inhabitable**. You don't look at the Navier-Stokes equations, you live in a smoke-filled room. The math disappears into experience.

That's the craft: taking real physics (Beer-Lambert absorption, non-Newtonian fluid dynamics, viscoelastic waves, slime mold growth algorithms) and making them into *places you want to be*.

The math serves the atmosphere. The atmosphere serves the text. The text is sacred. Everything else is smoke and moonlight and bisexual neon.

## The Evolution

From the README: "The flying toasters turned into whales and the whales turned into thermals and the thermals were better than both."

The invisible thermals won because you can only sense them through their effect on smoke. Five drifting convection cells, each pulsing with its own rhythm, creating updrafts you can't see but *feel* in how the smoke responds.

That's the difference between decoration and inhabitation. The room has weather. The space is alive.

## Technical Details Worth Preserving

**Corner pixel as clock** - One pixel (0,0) stores accumulated time, early returns from simulation, solves half-float precision issues by wrapping at safe values.

**Smoothed energy field** - Temporal EMA (exponential moving average) prevents flicker. Energy advects with smoke, diffuses spatially, never jitters. Display shader reads this smoothed value, not raw velocity magnitude.

**Velocity diffusion coefficient** - High viscosity (0.65) creates silky coherent flow instead of turbulent chaos.

**Focus transitions** - Smooth fade using `(iTime - iTimeFocus)` - unfocused windows dim to 55% brightness and 30% saturation. They become rooms you've stepped out of.

**Bisexual lighting seed** - `hash11(iResolution.x * 7.13 + iResolution.y * 3.71)` - each terminal gets its own lighting angle based on window size. Magenta and cyan from opposite directions.

## What It Feels Like

You're in a smoke-filled room with bisexual neon edge lighting and a drifting moon. The text you're reading is the heat source. Invisible thermals pulse through the space. The wind shifts in a figure-8 that never repeats. Coriolis spirals the smoke outward.

When you lose focus, the room dims and desaturates - not instantly, but like stepping out of a space. When you return, it comes alive again.

The terminal isn't decorated. It's **inhabited**.

---

Worth every blind moment. 🌙✨
