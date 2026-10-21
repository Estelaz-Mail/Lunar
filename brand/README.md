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

## Where these came from

Two of them are the designer's: `lunar-blue.png`, which has real
transparency, and `lunar-violet-on-white.png`, which does not. The rest were
derived from those two, and three things are worth knowing about how.

**The violet colourway had never been exported with transparency.** It was
recovered rather than redrawn: the silhouette of the violet art matches the
blue file's alpha channel exactly — the same drawing in two colourways — so
that alpha is the real one, and with it the white it was flattened onto can be
divided back out of every pixel. Flattening the result back onto black gives
the designer's own black export again, to within a few units on an antialiased
edge, which is the rounding in that division.

**The SVGs are not traced from the PNG.** Tracing the whole logo gives nine
hundred paths and a file larger than the PNG, because every band of every
gradient becomes a shape of its own. So the drawing was taken apart first: the
planet is a circle, the orbiting moon is a circle, and only Brazil, the star,
the orbit and the wordmark are really drawings. Those four are traced; the two
circles are circles. Ten paths, no transforms, thirty kilobytes.

**The ribbon of the orbit is flat, and so is everything else except the
globe.** The artwork paints the ribbon with a gradient along its length, which
is why it had to be cut out of the PNG with a threshold measured against the
local brightness rather than a fixed one: a fixed threshold takes a wide band
where the ribbon is bright and a narrow one where it is dim, which is a ring
that alternates fat and thin and ends bluntly where it should taper to a
point. In the SVG the ribbon is simply white.

The globe is the one thing that is shaded, with a radial gradient centred on
the highlight in its upper right — which is where the moon is.
