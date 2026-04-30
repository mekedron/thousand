import clsx from 'clsx';
import Heading from '@theme/Heading';
import Link from '@docusaurus/Link';
import styles from './styles.module.css';

const FeatureList = [
  {
    title: 'Learn the Rules',
    to: '/docs/rules/setup',
    description: (
      <>
        A clear, step-by-step walkthrough of a single deal — dealing,
        bidding, the talon, marriages, trick-taking, and scoring.
      </>
    ),
  },
  {
    title: 'Understand the Roles',
    to: '/docs/equipment/players-and-roles',
    description: (
      <>
        Forehand, middlehand, dealer, declarer, defenders. How positions
        and per-deal roles fit together at a 3-player table.
      </>
    ),
  },
  {
    title: 'Explore Variations',
    to: '/docs/variations',
    description: (
      <>
        Russian, Polish, Ukrainian, 2-player, 4-player partnership rules,
        and the most common house-rule tweaks worth agreeing in advance.
      </>
    ),
  },
];

function Feature({title, description, to}) {
  return (
    <div className={clsx('col col--4')}>
      <div className="text--center padding-horiz--md">
        <Heading as="h3">
          <Link to={to}>{title}</Link>
        </Heading>
        <p>{description}</p>
      </div>
    </div>
  );
}

export default function HomepageFeatures() {
  return (
    <section className={styles.features}>
      <div className="container">
        <div className="row">
          {FeatureList.map((props, idx) => (
            <Feature key={idx} {...props} />
          ))}
        </div>
      </div>
    </section>
  );
}
