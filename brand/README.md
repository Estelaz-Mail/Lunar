# Brand

The Lunar logo: a planet with Brazil on it, a moon in orbit around it, and the
wordmark under it.

## The icon is the planet, on its own

`icon.png` and `favicon.png` are the planet with no wordmark and **no
background** — transparent, so they sit on whatever the tab bar, the dock or
the editor happens to be. That is what the VS Code extension and the example
app use. The blue colourway is bright enough to read on a light background and
on a dark one, which is why the icon is the blue one.

## Which file

| File                        | What                        | Background  | Use it                        |
| --------------------------- | --------------------------- | ----------- | ----------------------------- |
| `icon.png`                  | the planet, 256×256         | transparent | **the application icon**      |
| `favicon.png`               | the planet, 32×32           | transparent | **the favicon**               |
| `planet-blue.svg`           | the planet                  | transparent | the icon, as vector           |
| `planet-violet.svg`         | the planet, violet          | transparent | the same, on a light page     |
| `planet-blue.png`           | the planet, 1024×1024       | transparent | where a PNG is wanted         |
| `planet-violet.png`         | the planet, violet          | transparent | the same, on a light page     |
| `lunar-blue.svg`            | the lockup                  | transparent | on a dark background          |
| `lunar-violet.svg`          | the lockup, violet          | transparent | on a light background         |
| `lunar-blue.png`            | the lockup                  | transparent | on a dark background          |
| `lunar-violet.png`          | the lockup, violet          | transparent | on a light background         |
| `lunar-blue-on-black.png`   | the lockup                  | black       | where transparency is not an option |
| `lunar-violet-on-black.png` | the lockup, violet          | black       | the same, violet              |
| `lunar-violet-on-white.png` | the lockup, violet          | white       | print, slides                 |

The wordmark is white in the blue colourway, so `lunar-blue.*` disappears on a
white page; that is what the violet colourway is for. The README picks between
them with `prefers-color-scheme`.

## Which files are the originals

Two, and only two:

- `lunar-blue.png` — the blue colourway, with real transparency.
- `lunar-violet-on-white.png` — the violet colourway, as it was exported.

Everything else is written by the two scripts:

```sh
python3 brand/make.py       # the PNGs; needs Pillow
python3 brand/svg.py        # the SVGs;  needs Pillow and vtracer
```

### `make.py`, and the violet one's transparency

The violet colourway had never been exported with transparency, so it is
recovered rather than redrawn: the silhouette of the violet art matches the
blue file's alpha channel exactly — the same drawing in two colourways — so
that alpha is the real one, and with it the white it was flattened onto can be
divided back out of every pixel.

The script checks itself. Flattening what it recovered has to give back the
designer's own black exports, and it does, to within a few units on an
antialiased edge — which is the rounding in that division.

### `svg.py`, and why it does not trace the logo

Tracing the whole logo produces nine hundred paths and a file larger than the
PNG, because every band of every gradient becomes a shape of its own. So the
drawing is taken apart first: the planet is a circle, the orbiting moon is a
circle, and only Brazil, the star, the orbit and the wordmark are really
drawings. Those four are traced; the two circles are circles; each is filled
with a gradient read off the original.

The parts are found by connected components rather than by guessing at
coordinates — Brazil is the largest blob inside the disc, the star is the one
above and to the right of it, the orbit is the ring that reaches past the disc,
the wordmark is everything below. The result is six shapes and about twenty
kilobytes, which is a file a person can open and edit.
