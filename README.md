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
  Medium = recommended default (shadow map 2048, 128 blocks).
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
