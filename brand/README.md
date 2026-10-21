# Brand

The Lunar logo: a planet with Brazil on it, a moon in orbit around it, and the
wordmark under it.

## The icon is the planet, on its own

`icon.png` and `favicon.png` are the planet with no wordmark and **no
background** — transparent, so they sit on whatever the tab bar, the dock or
the editor happens to be. That is what the VS Code extension and the example
app use. The blue colourway is bright enough to read on a light background and
on a dark one, which is why the icon is the blue one.

An icon has to be square and this drawing is not: it is a fifth wider than it
is tall, because the orbit reaches out either side. So the drawing touches the
left and right edges and what is left above and below — about seven per cent —
is the drawing's own proportion and nothing else. Cropping to fill would cut
the orbit off; a margin would float the planet in the middle of an empty
frame. Neither is better than the shape the logo already has.

`planet-blue.png` and `planet-violet.png` are not square: they are cropped to
the drawing, with no border at all.

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

The parts are found by connected components, and sorted by **where their
pixels are** rather than by how big their bounding boxes are: a blob more than
half of which lies outside the disc is orbit, and what is left on the disc is
Brazil and the star. The orbit arrives in three pieces — the ring, and the two
slivers the disc cuts off at the top and the left — and a rule about box sizes
puts those slivers somewhere else, which is how the left of the orbit ends up
filled with Brazil's colour.

The colours are measured off the artwork band by band, not guessed at. That is
how it came out that Brazil, the star and the wordmark are flat — what looks
like a fade on them is the antialiased edge against the body — and that the
globe is lit from the upper right, where the moon is, rather than from the top.

The result is six shapes and about thirty-five kilobytes. Rendered back at full
size and compared with the artwork, the average difference is 3.5 of 255 per
channel: the rest is the coastline, where a traced curve is smoother than the
original's pixels.
