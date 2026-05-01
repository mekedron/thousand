import clsx from 'clsx';
import Link from '@docusaurus/Link';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import Layout from '@theme/Layout';
import HeroTrick from '@site/src/components/HeroTrick/HeroTrick';
import AppPromoTable from '@site/src/components/AppPromoTable/AppPromoTable';

import styles from './index.module.css';

const TLDR = [
  {
    n: '01',
    title: 'Learn the rules',
    copy: 'A clear, step-by-step walkthrough of a single deal — dealing, bidding, the talon, marriages, trick-taking, and scoring.',
    linkLabel: 'Start with Setup →',
    to: '/docs/rules/setup',
  },
  {
    n: '02',
    title: 'Understand the roles',
    copy: 'Forehand, middlehand, dealer, declarer, defenders. How positions and per-deal roles fit together at a 3-player table.',
    linkLabel: 'Players & roles →',
    to: '/docs/equipment/players-and-roles',
  },
  {
    n: '03',
    title: 'Explore variations',
    copy: 'Russian, Polish, Ukrainian, 2-player, 4-player partnership rules, and the most common house-rule tweaks worth agreeing in advance.',
    linkLabel: 'Read the catalogue →',
    to: '/docs/variations',
  },
];

const VARIANTS = [
  {n: 'Russian', p: '3p', note: 'Reference rules', to: '/docs/variations/russian'},
  {n: 'Polish', p: '3p', note: 'Tysiąc · explicit must-trump', to: '/docs/variations/polish'},
  {n: 'Ukrainian', p: '3p', note: 'With the bolt rule', to: '/docs/variations/ukrainian'},
  {n: 'Two-player', p: '2p', note: 'Schnapsen-like', to: '/docs/variations/two-player'},
  {n: 'Four-player', p: '4p', note: 'Fixed partnerships', to: '/docs/variations/four-player'},
];

function Hero() {
  return (
    <section className={styles.hero}>
      <div className={styles.heroGrid}>
        <div>
          <div className={clsx(styles.eyebrow, styles.eyebrowBrass)}>
            Тысяча · Tysiąc · Тисяча
          </div>
          <h1 className={styles.heroTitle}>
            The classic
            <br />
            <em className={styles.heroTitleAccent}>thousand-point</em>
            <br />
            card game.
          </h1>
          <p className={styles.heroLead}>
            A canonical reference for the rules, a catalogue of the regional
            variations, and a free open-source app to play it on your laptop.
          </p>
          <div className={styles.heroCtaRow}>
            <Link className={clsx(styles.btn, styles.btnBrass)} to="/docs/intro">
              Read the rules <span aria-hidden="true">→</span>
            </Link>
            <Link
              className={clsx(styles.btn, styles.btnGhost)}
              to="/docs/development/roadmap">
              Download the app
            </Link>
            <Link
              className={clsx(styles.btn, styles.btnGhost)}
              to="/docs/development/roadmap">
              Play in browser
            </Link>
          </div>
          <div className={styles.heroStats}>
            <span>★ Open source</span>
            <span aria-hidden="true">•</span>
            <span>5 regional variants</span>
            <span aria-hidden="true">•</span>
            <span>macOS · Linux · iOS</span>
          </div>
        </div>
        <HeroTrick tilt={9} showMedallions showNumeralBg />
      </div>
    </section>
  );
}

function Tldr() {
  return (
    <section className={clsx(styles.section, styles.tldr)}>
      <div className={clsx(styles.eyebrow, styles.tldrLabel)}>
        What this site is
      </div>
      <div className={styles.tldrGrid}>
        {TLDR.map((c) => (
          <div key={c.n} className={styles.tldrCard}>
            <div className={clsx(styles.eyebrow, styles.tldrNumber)}>{c.n}</div>
            <div className={styles.tldrTitle}>{c.title}</div>
            <p className={styles.tldrCopy}>{c.copy}</p>
            <Link className={styles.tldrLink} to={c.to}>
              {c.linkLabel}
            </Link>
          </div>
        ))}
      </div>
    </section>
  );
}

function Variants() {
  return (
    <section className={clsx(styles.section, styles.variants)}>
      <div className={styles.eyebrow} style={{marginBottom: 14}}>
        Five canonical variants — pick yours
      </div>
      <div className={styles.variantsGrid}>
        {VARIANTS.map((v) => (
          <Link key={v.n} className={styles.variantCard} to={v.to}>
            <div className={styles.eyebrow}>{v.p}</div>
            <div className={styles.variantTitle}>{v.n}</div>
            <div className={styles.variantNote}>{v.note}</div>
          </Link>
        ))}
      </div>
    </section>
  );
}

function AppPromo() {
  return (
    <section className={styles.promo}>
      <div className={styles.promoGrid}>
        <div>
          <div className={clsx(styles.eyebrow, styles.promoEyebrow)}>The app</div>
          <h2 className={styles.promoTitle}>Play it tonight.</h2>
          <p className={styles.promoLead}>
            An open-source desktop app written in Lua/Love2D. Three-player
            hot-seat today; algorithmic AI opponents and named-character chat
            in upcoming phases.
          </p>
          <div className={styles.promoCtas}>
            <Link className={clsx(styles.btn, styles.btnBrass)} to="/docs/development/roadmap">
              Download for macOS
            </Link>
            <Link className={clsx(styles.btn, styles.btnFootDark)} to="/docs/development/roadmap">
              Linux .AppImage
            </Link>
            <Link className={clsx(styles.btn, styles.btnFootDark)} to="/docs/development/roadmap">
              iOS TestFlight
            </Link>
          </div>
          <div className={styles.promoMeta}>
            <span>Lua / Love2D</span>
            <span>MIT</span>
            <span>Open source</span>
          </div>
        </div>
        <AppPromoTable />
      </div>
    </section>
  );
}

function Quote() {
  return (
    <section className={clsx(styles.section, styles.quote)}>
      <div className={styles.quoteInner}>
        <div className={clsx(styles.eyebrow, styles.eyebrowBrass)}>
          From the introduction
        </div>
        <p className={styles.quoteText}>
          “Two tables in the same city will often disagree on details.{' '}
          <em>Always agree the house rules before the first deal.</em>”
        </p>
      </div>
    </section>
  );
}

export default function Home() {
  const {siteConfig} = useDocusaurusContext();
  return (
    <Layout
      title={siteConfig.title}
      description="A guide to the classic trick-taking card game Thousand (Тысяча / Tysiąc) — rules, roles, scoring, and regional variations.">
      <main className={styles.landing} data-theme="light">
        <Hero />
        <Tldr />
        <Variants />
        <AppPromo />
        <Quote />
      </main>
    </Layout>
  );
}
