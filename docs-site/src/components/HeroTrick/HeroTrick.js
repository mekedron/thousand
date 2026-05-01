import CardArt from '../CardArt/CardArt';
import styles from './HeroTrick.module.css';

const TRICK_CARDS = [
  {rank: 'K', suit: 'D', x: 0, y: 30, rotMul: -1, rotAdd: 0, z: 3},
  {rank: '10', suit: 'H', x: -80, y: -30, rotMul: -1, rotAdd: -18, z: 1},
  {rank: 'A', suit: 'S', x: 80, y: -30, rotMul: 1, rotAdd: 16, z: 2},
];

const MEDALLIONS = [
  {suit: 'H', glyph: '♥', value: 100, angle: -90, color: 'var(--ds-hearts)'},
  {suit: 'D', glyph: '♦', value: 80, angle: 0, color: 'var(--ds-diamonds)'},
  {suit: 'C', glyph: '♣', value: 60, angle: 90, color: '#1a1611'},
  {suit: 'S', glyph: '♠', value: 40, angle: 180, color: '#1a1611'},
];

const MEDALLION_RADIUS = 250;

/**
 * @param {{ tilt?: number, showMedallions?: boolean, showNumeralBg?: boolean }} props
 */
export default function HeroTrick({
  tilt = 9,
  showMedallions = true,
  showNumeralBg = true,
}) {
  return (
    <div className={styles.stage} aria-hidden="true">
      <div className={styles.felt} />
      <div className={styles.brassRing} />
      {showNumeralBg && <div className={styles.numeral}>1000</div>}

      <div className={styles.cards}>
        {TRICK_CARDS.map((c, i) => {
          const rot = c.rotMul * tilt + c.rotAdd;
          return (
            <div
              key={i}
              className={styles.cardSlot}
              style={{
                transform: `translate(calc(-50% + ${c.x}px), calc(-50% + ${c.y}px)) rotate(${rot}deg)`,
                zIndex: c.z,
              }}>
              <CardArt rank={c.rank} suit={c.suit} />
            </div>
          );
        })}
      </div>

      {showMedallions &&
        MEDALLIONS.map((m) => {
          const rad = (m.angle * Math.PI) / 180;
          const x = Math.cos(rad) * MEDALLION_RADIUS;
          const y = Math.sin(rad) * MEDALLION_RADIUS;
          return (
            <div
              key={m.suit}
              className={styles.medallion}
              style={{
                transform: `translate(calc(-50% + ${x}px), calc(-50% + ${y}px))`,
              }}>
              <div className={styles.medallionGlyph} style={{color: m.color}}>
                {m.glyph}
              </div>
              <div className={styles.medallionValue}>+{m.value}</div>
            </div>
          );
        })}
    </div>
  );
}
