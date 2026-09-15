# Scroll capture corpus

Real-world fixtures for `ImageStitcherCorpusTests`. Empty by default (just `.gitkeep`); the corpus test
iterates whatever subfolders are present and passes trivially when there are none.

## Layout

Each subfolder is one scrolling capture from one app:

```
Fixtures/scroll/
  <app>/
    frame-00.png
    frame-01.png
    frame-02.png
    ...
    expected.png
```

- `frame-NN.png`: the raw captured frames, in scroll order, sorted by filename (`frame-00.png` first).
- `expected.png`: the reviewed, correct stitched result for those frames -- the ground truth the test compares
  `ImageStitcher.stitch(frames)` against (same width/height, mean absolute difference <= 3/255 over a 64x64 grid).

`<app>` is a short slug for the source application/window (e.g. `notes`, `safari-long-article`), just a label;
the test does not interpret it.

## Collecting frames

Frames come from `ScrollCaptureService` (Task 7) via the `MIRACLE_SHOT_SCROLL_DUMP` environment variable: launch
the app from Terminal with it set to a directory, e.g.

```
MIRACLE_SHOT_SCROLL_DUMP=/tmp/scroll-dump /Applications/MiracleShot.app/Contents/MacOS/MiracleShot
```

then run a scrolling capture; each frame of the capture is written to that directory as it is taken. Copy the
frames for 4-5 windows into `Fixtures/scroll/<app>/`, rename them to the `frame-NN.png` sequence in capture
order, review the result and save it as `expected.png`.

If the corpus test fails, tune `ImageStitcher.stitch`'s `matchTolerance`/`minOverlap` rather than editing
`expected.png` -- the fixture is the ground truth.

## Running

Real frames take about half a minute each unoptimized, so a plain debug `swift test` skips the corpus. Run it
optimized with `scripts/test-corpus.sh`, or force it in a debug run with `MIRACLE_SHOT_CORPUS=1 swift test`.
