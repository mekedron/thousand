// @ts-check
// `@type` JSDoc annotations allow editor autocompletion and type checking
// (when paired with `@ts-check`).
// See: https://docusaurus.io/docs/api/docusaurus-config

import {themes as prismThemes} from 'prism-react-renderer';

/** @type {import('@docusaurus/types').Config} */
const config = {
  title: 'Thousand',
  tagline: 'A guide to the classic trick-taking card game',
  favicon: 'img/favicon.ico',

  // Future flags — see https://docusaurus.io/docs/api/docusaurus-config#future
  // v4 turns on every Docusaurus v4 preparation flag at once
  // (siteStorageNamespacing, fasterByDefault, mdx1CompatDisabledByDefault).
  // `faster` enables the new Rspack/SWC/LightningCSS build pipeline.
  future: {
    v4: true,
    faster: true,
  },

  // Production URL and base path for GitHub Pages (project site at
  // https://mekedron.github.io/thousand/).
  url: 'https://mekedron.github.io',
  baseUrl: '/thousand/',
  trailingSlash: false,

  // GitHub Pages deployment config.
  organizationName: 'mekedron',
  projectName: 'thousand',
  deploymentBranch: 'gh-pages',

  onBrokenLinks: 'throw',
  markdown: {
    hooks: {
      onBrokenMarkdownLinks: 'warn',
    },
  },

  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

  // Brand fonts: Instrument Serif for display, Geist for body, Geist Mono for code.
  stylesheets: [
    {
      href: 'https://fonts.googleapis.com',
      rel: 'preconnect',
    },
    {
      href: 'https://fonts.gstatic.com',
      rel: 'preconnect',
      crossorigin: 'anonymous',
    },
    {
      href: 'https://fonts.googleapis.com/css2?family=Instrument+Serif:ital@0;1&family=Geist:wght@400;500;600;700&family=Geist+Mono:wght@400;500&display=swap',
      rel: 'stylesheet',
    },
  ],

  presets: [
    [
      'classic',
      /** @type {import('@docusaurus/preset-classic').Options} */
      ({
        docs: {
          // Markdown lives at the repo root in `docs/`, while this
          // Docusaurus app lives in `docs-site/`. The path is resolved
          // relative to the Docusaurus root.
          path: '../docs',
          sidebarPath: './sidebars.js',
          editUrl:
            'https://github.com/mekedron/thousand/tree/main/docs/',
          // Custom admonition keywords on top of the built-in
          // note/tip/info/warning/danger. Styling lives in
          // src/css/custom.css under .theme-admonition-<keyword>.
          admonitions: {
            keywords: ['strategy', 'variant', 'example'],
            extendDefaults: true,
          },
        },
        // No blog — this site is documentation only.
        blog: false,
        theme: {
          customCss: './src/css/custom.css',
        },
      }),
    ],
  ],

  themeConfig:
    /** @type {import('@docusaurus/preset-classic').ThemeConfig} */
    ({
      image: 'img/docusaurus-social-card.jpg',
      colorMode: {
        respectPrefersColorScheme: true,
      },
      navbar: {
        title: 'Thousand',
        logo: {
          alt: 'Thousand card game logo',
          src: 'img/logo.svg',
        },
        items: [
          {
            type: 'docSidebar',
            sidebarId: 'tutorialSidebar',
            position: 'left',
            label: 'Documentation',
          },
          {
            to: '/docs/rules/setup',
            label: 'Rules',
            position: 'left',
          },
          {
            to: '/docs/variations',
            label: 'Variations',
            position: 'left',
          },
          {
            to: '/docs/strategy',
            label: 'Strategy',
            position: 'left',
          },
          {
            href: 'https://github.com/mekedron/thousand',
            label: 'GitHub',
            position: 'right',
          },
        ],
      },
      footer: {
        style: 'dark',
        logo: {
          alt: 'Thousand card game',
          src: 'img/logo.svg',
          width: 32,
          height: 32,
        },
        links: [
          {
            title: 'Documentation',
            items: [
              {label: 'Introduction', to: '/docs/intro'},
              {label: 'Equipment', to: '/docs/equipment/deck'},
              {label: 'Rules of Play', to: '/docs/rules/setup'},
              {label: 'Strategy', to: '/docs/strategy'},
              {label: 'Variations', to: '/docs/variations'},
            ],
          },
          {
            title: 'Project',
            items: [
              {
                label: 'GitHub',
                href: 'https://github.com/mekedron/thousand',
              },
              {
                label: 'Roadmap',
                to: '/docs/development/roadmap',
              },
              {
                label: 'Architecture',
                to: '/docs/development/architecture',
              },
            ],
          },
          {
            title: 'Play',
            items: [
              {
                label: 'Download (coming soon)',
                href: 'https://github.com/mekedron/thousand/releases',
              },
            ],
          },
        ],
        copyright: `A digital reading room for the classic Eastern-European card game. Open source, open rules. © ${new Date().getFullYear()}.`,
      },
      prism: {
        theme: prismThemes.github,
        darkTheme: prismThemes.dracula,
      },
    }),
};

export default config;
