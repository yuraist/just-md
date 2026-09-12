# JustMD promotional video

This standalone Remotion project composes recorded JustMD clips into a
promotional video. It is used only for marketing; neither this project nor
Remotion is compiled into or distributed inside the macOS app.

## Commands

Run from this directory:

```bash
npm ci
npm run dev
npx remotion render JustMDPromo out/justmd-promo.mp4
```

The composition lives in `src/Promo.tsx`, with source clips in `public/clips/`.
See [the capture instructions](../README.md) for recording new clips.
Generated output in `out/` is ignored by Git.

## License

The original JustMD composition code is covered by the repository's
[MIT License](../../LICENSE). The `private` package flag prevents accidental
publication to npm; it does not restrict access to the source code.

Remotion is a separate development dependency with its own
[license terms](https://github.com/remotion-dev/remotion/blob/v4.0.522/LICENSE.md).
Those terms apply when using Remotion to create videos, not when building
or using the JustMD macOS application. Other npm dependencies retain their
respective licenses.
