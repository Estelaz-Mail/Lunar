# Brand

The Lunar logo: a planet with Brazil on it, an orbit around it, and the
wordmark under it.

## Which file

| File                        | Colourway | Background  | Use it                          |
| --------------------------- | --------- | ----------- | ------------------------------- |
| `lunar-blue.png`            | blue      | transparent | on a dark background            |
| `lunar-violet.png`          | violet    | transparent | on a light background           |
| `lunar-blue-on-black.png`   | blue      | black       | where transparency is not an option |
| `lunar-violet-on-black.png` | violet    | black       | the same, violet                |
| `lunar-violet-on-white.png` | violet    | white       | print, slides, anything on white |
| `mark-blue.png`             | blue      | transparent | the planet alone, square        |
| `mark-violet.png`           | violet    | transparent | the planet alone, square        |
| `icon.png`                  | blue      | near-black  | 256×256 application icon        |
| `favicon.png`               | blue      | near-black  | 32×32                           |

The wordmark is white in the blue colourway, so `lunar-blue.png` disappears on
a white page; that is what `lunar-violet.png` is for. The README picks between
them with `prefers-color-scheme`.

## Which files are the originals

Two, and only two:

- `lunar-blue.png` — the blue colourway, with real transparency.
- `lunar-violet-on-white.png` — the violet colourway, as it was exported.

Everything else is written by `make.py`:

```sh
python3 brand/make.py       # needs Pillow
```

`lunar-violet.png` is the interesting one. The violet colourway was only ever
exported flattened onto a background, so its transparency is recovered: the
silhouette of the violet art matches the blue file's alpha channel exactly —
they are the same drawing twice — so that alpha is the real one, and with it
the white it was composited over can be divided back out.

The script checks itself at the end. Flattening what it recovered has to give
back the designer's own black exports, and it does: the largest difference is a
handful of units on an antialiased edge, which is the rounding in that
division.
