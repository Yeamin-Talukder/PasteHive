# PasteHive website

The marketing site for [PasteHive](https://github.com/Yeamin-Talukder/PasteHive),
a free, open-source clipboard manager and clipboard sync app for Windows, macOS
and Android.

It is a static site: Next.js (static export), Tailwind CSS and Motion. The build
produces plain HTML, CSS and JS in `out/`, which any static host can serve.

## Run it

From this folder (`website/` in the PasteHive repository):

```powershell
npm install
npm run dev
```

Then open http://localhost:3000.

## Check and build

```powershell
npm run typecheck
npm run lint
npm run build
```

`npm run build` writes the finished site to `out/`. To look at exactly what
will be hosted:

```powershell
npx serve out
```

## Hosting

Two settings are read at build time:

| Variable | What it is for | Example |
| --- | --- | --- |
| `NEXT_PUBLIC_SITE_URL` | The address the site is served from. Used for the canonical link and the social preview image. | `https://pastehive.example` |
| `NEXT_PUBLIC_BASE_PATH` | Only when the site lives in a sub-folder, as on a GitHub Pages project site. Leave unset otherwise. | `/PasteHive` |

A local build without `NEXT_PUBLIC_SITE_URL` points its social preview tags
at `http://localhost:3000`; that is fine for looking at it, not for hosting.

The site is served by GitHub Pages at
https://yeamin-talukder.github.io/PasteHive/ and nothing is set by hand:
[`.github/workflows/website.yml`](../.github/workflows/website.yml) reads both
settings from the repository's Pages configuration.

- A pull request that changes anything in `website/` is type-checked, linted
  and built.
- A push to `main` that changes anything in `website/` does the same and then
  publishes the result. It is live a minute or two later.
- To publish without a change: Actions > Website > Run workflow.

To host it somewhere else (Vercel, Netlify), point the host at the `website`
folder, with build command `npm run build` and output folder `out`, and set
`NEXT_PUBLIC_SITE_URL` there.

## Where things are

| Path | What is there |
| --- | --- |
| `src/app/` | The page, its metadata, the icons and the social preview image |
| `src/components/Hero.tsx` | The one-screen hero |
| `src/components/hero/model.ts` | The hero animation as data: what is copied, in what order, and how long each phase lasts |
| `src/components/hero/Scene.tsx` | The devices, the glass panel, and the two layouts (three devices on wide screens, two on small ones) |
| `src/components/hero/parts.tsx` | History rows, the copied content, the pointer |
| `src/components/*.tsx` | One file per section below the hero |
| `src/lib/site.ts` | Name, description and every outbound link |
| `src/assets/` | The logo (concept 3) and the two real app screenshots |

## Content rule

Every product claim on the page comes from the app's
[README](https://github.com/Yeamin-Talukder/PasteHive#readme). When the app
changes (a first release, iOS, sync over the internet), change the README
first and then this site. No testimonials, user counts or ratings are shown
because there are none to show.

## License

MIT, the same as the app.
