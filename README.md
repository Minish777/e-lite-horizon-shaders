# E-LITE (Horizon port)

Unofficial port of [E-LITE shaders v5.1.3](https://github.com/EntokitoDezonze/E-LITE-shaders)
(a MakeUp - Ultra Fast edit by EntokitoDezonze, original MakeUp by Javier Garduño)
to Horizon's WGSL shader API (`.hshader` packs).

**This is not affiliated with the original authors.** Original code is LGPL-3.0
(see `LICENSE`); Horizon WGSL implementation structure follows the existing
Horizon packs (Radiant, MIT — see `LICENSE-Radiant-MIT.txt`).

## Install
Copy `e-lite-horizon-1.0.0.hshader` into `~/.local/share/horizon/shaderpacks/`,
then in game: Video Settings -> Shaders -> pick "E-LITE (Horizon port)".

## What is ported (E-LITE v5.1.3 -> Horizon)
- Profiles (ACERCADE): No effects / Very low / Low / Medium / High / Max.
  Medium = recommended default (shadow map 2048, 128 blocks; size/distance adjustable in Lighting).
- Color schemes (STYLE / COLOR_SCHEME): Vanilla, Realistic+, LITE Legacy,
  Warm film, Vivid. Colors calibrated to `config.glsl` defaults
  (day light 0.90/0.84/0.79, sunset 1.0/0.59/0.35, zenith/horizon day+night).
- Colored shadows, soft shadow filter, sun/moon strength, night brightness,
  avoid-dark floor, blocklight temperature, torch flicker.
- God rays (VOL_LIGHT), bloom, AO, atmosphere/fog (FOG_ADJUST), morning mist,
  rain puddles + wet ground, heat shimmer over lava.
- Water: waves, clarity, absorption, caustics, refraction, planar reflections,
  sun path/glitter, underwater fog rework.
- Sky: round sun with limb darkening, 2D clouds (V_CLOUDS), stars
  (brightness/coverage), Milky Way, aurora, sunset warmth.
- Waving (leaves + plants) with wind force; LabPBR normal/specular maps
  (from resource packs); emissive strength; weather rain/snow.
- Camera: ACES/Reinhard/Lottes tonemapping, exposure, brightness, contrast,
  gamma, saturation, vibrance, sharpening, depth of field, chromatic
  aberration, film grain, vignette, eye adaptation (auto-exposure), TAA.

## Not ported (no Horizon equivalent)
- Voxy / Distant Horizons integration (Horizon renders its own terrain).
- Per-dimension shader programs (world0/1/-1) — one material stage with
  `frame.dimension` checks instead.
- Iris/OptiFine-only bits: `block.properties` ENTITY ids (replaced by
  `[[materials]]`/`[[lights]]` lists), text-render splash, seasons,
  custom End portal, selection line, color-blindness modes,
  screen-space raymarched reflections (planar reflection is used instead),
  motion blur (no motion vectors exposed).

## Source layout
`horizon-shaders.toml` (manifest + settings), `common.wgsl`, `material.wgsl`,
`sky.wgsl`, `vertex.wgsl`, `weather.wgsl`, `post/*.wgsl`.
Build: `zip -r e-lite-horizon-1.0.0.hshader horizon-shaders.toml *.wgsl post README.md LICENSE* Credits*`

## Credits & licenses

- E-LITE shaders v5.1.3 by EntokitoDezonze, based on MakeUp - Ultra Fast by
  Javier Garduño (https://github.com/javiergcim/MakeUpUltraFast).
  Original shader code: LGPL-3.0 (see `LICENSE` in this pack / repo).
- This Horizon WGSL port reimplements the look using Horizon's shader API;
  its pipeline structure (shadows, water, god rays, post chain) follows the
  Horizon pack "Radiant" (MIT). Radiant MIT license text:

MIT License

Copyright (c) 2026 Daniel

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.


Original E-LITE Credits file (upstream attribution list):

Some of the code is inspired by the ideas presented below:

------

- Enhanced ambient occlusion is based on Capt Tatsu's ambient occlusion used in
  BSL Shaders:
  https://bitslablab.com/bslshaders/

- Shadow bias technique from Emin implementation, based on a concept
  reimagined by gri573:
  https://www.complementary.dev/

- Interleaved noise from:
  "NEXT GENERATION POST PROCESSING IN CALL OF DUTY: ADVANCED WARFARE"
  http://advances.realtimerendering.com/s2014/index.html

- TAA is based on Erkaman's TAA simple implementation:
  https://gist.github.com/Erkaman

- Phi noise by delu:
  https://www.shadertoy.com/view/Nst3R7
  Based on TinyTexel:
  https://www.shadertoy.com/view/wltSDn
  Based on:
  http://extremelearning.com.au/unreasonable-effectiveness-of-quasirandom-sequences/

- R dither based on:
  http://extremelearning.com.au/unreasonable-effectiveness-of-quasirandom-sequences/

- Dither 13 and Dther 17 by atyuwen:
  https://www.shadertoy.com/view/wl3cWX
  Based on:
  https://developer.oculus.com/blog/tech-note-shader-snippets-for-efficient-2d-dithering/

- Blocky clouds were inspired by rre36's Nostalgia Shader, however, no code was used from said shader.

- Text render by sixthsurge:
  https://discord.com/channels/237199950235041794/525510804494221312/1034533866951684187
  Based on Monocraft by IdreesInc:
  https://github.com/IdreesInc/Monocraft

------

If any functions were listed here, and are no longer listed,
they have been removed or replaced by own functions.

------

I am not a graphics developer, I made this shader out of curiosity and
my personal use, but I think it is good enough to be shared.

I have not copied, but have tried to learn, adapt and modify
other people's ideas in favor of the shader.

If you think I have violated your copyright, please notify me.
javierg.cim at gmail.com

