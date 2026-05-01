import SuitGlyph from '../CardArt/SuitGlyph';
import styles from './MarriageValues.module.css';

const ROWS = [
  {suit: 'H', name: 'Hearts', value: 100},
  {suit: 'D', name: 'Diamonds', value: 80},
  {suit: 'C', name: 'Clubs', value: 60},
  {suit: 'S', name: 'Spades', value: 40},
];

export default function MarriageValues() {
  return (
    <div className={styles.grid}>
      {ROWS.map((r) => (
        <div key={r.suit} className={styles.tile}>
          <SuitGlyph suit={r.suit} size={28} />
          <div>
            <div className={styles.suitName}>{r.name}</div>
            <div className={styles.value}>+{r.value}</div>
          </div>
        </div>
      ))}
    </div>
  );
}
