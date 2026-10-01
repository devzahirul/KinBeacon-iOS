# KinBeacon website

A responsive, buildless product website adapted from the supplied Convo website. Uses KinBeacon’s real iPhone screenshots and app icon.

## Preview

```sh
python3 -m http.server 4174 --directory dist
```

Open http://localhost:4174. The publishable website is `dist/`; all assets use relative local paths, including for GitHub Pages. No install or build step is needed.

## Contents

- Two-phone parent/child hero, six feature cards, privacy, pairing guide, developer overview, FAQs
- Twelve-screen gallery: six parent screens and six child screens
- Parent/child switch, arrow-key/Home/End navigation, full-size modal, Escape to close
- Responsive layouts, accessible tabs, reduced-motion support
- Accurate iOS availability and App Store preview status; no placeholder download links

## GitHub Pages

Website: https://devzahirul.github.io/KinBeacon-iOS/

GitHub Pages publishes the root of the `codex/kinbeacon-github-pages` branch. The website source is tracked on `main` under `website/dist/`, including `.nojekyll`. All paths are relative so the site works under `/KinBeacon-iOS/`.

After committing website changes on `main`, publish the updated static files with:

```sh
git subtree push --prefix website/dist origin codex/kinbeacon-github-pages
```

Local Sites metadata in `.openai/` is ignored; GitHub Pages is the publishing destination.
