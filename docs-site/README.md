# Thousand — Documentation Site

A [Docusaurus 3.10](https://docusaurus.io/blog/releases/3.10) static site
documenting the classic trick-taking card game **Thousand** (*Тысяча /
Tysiąc*).

The site enables Docusaurus's `future.v4: true` and `future.faster: true`
flags so the build runs on the Rspack/SWC/LightningCSS pipeline that will
become the default in Docusaurus v4.

## Repository layout

```
.
├── docs/        ← markdown content (intro, rules, strategy, variations)
└── docs-site/   ← this directory: Docusaurus app, build tooling, theme
```

The Docusaurus config (`docusaurus.config.js`) reads the markdown from
`../docs` so contributors editing content do not need to touch the
JavaScript build setup.

## Local development

From this directory:

```bash
npm install
npm start
```

This starts a hot-reloading dev server at <http://localhost:3000/thousand/>.

## Production build

```bash
npm run build
```

Outputs the static site to `docs-site/build/`.

## Deployment

The site is deployed automatically to **GitHub Pages** by the workflow in
[`.github/workflows/deploy.yml`](../.github/workflows/deploy.yml) on every
push to `main`. PRs trigger a build-only check via
[`.github/workflows/test-deploy.yml`](../.github/workflows/test-deploy.yml).

The published URL is <https://mekedron.github.io/thousand/>.

To enable deployment, in the GitHub repository settings:

1. Go to **Settings → Pages**.
2. Set **Source** to **GitHub Actions**.

No further configuration is required — the workflow handles the rest.
