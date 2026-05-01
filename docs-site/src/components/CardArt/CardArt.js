import clsx from 'clsx';
import styles from './CardArt.module.css';

const SUIT_GLYPHS = {H: '♥', D: '♦', C: '♣', S: '♠'};
const SUIT_CLASS = {
  H: styles.hearts,
  D: styles.diamonds,
  C: styles.clubs,
  S: styles.spades,
};

/**
 * @param {{
 *   rank?: string,
 *   suit?: 'H' | 'D' | 'C' | 'S',
 *   size?: 'md' | 'sm' | 'xs',
 *   faceDown?: boolean,
 *   selected?: boolean,
 *   illegal?: boolean,
 *   className?: string,
 *   style?: React.CSSProperties,
 * }} props
 */
export default function CardArt({
  rank,
  suit,
  size = 'md',
  faceDown,
  selected,
  illegal,
  className,
  style,
}) {
  const sizeClass = size === 'sm' ? styles.sm : size === 'xs' ? styles.xs : null;
  const suitClass = suit && !faceDown ? SUIT_CLASS[suit] : null;

  const cls = clsx(
    styles.card,
    sizeClass,
    suitClass,
    faceDown && styles.faceDown,
    selected && styles.selected,
    illegal && styles.illegal,
    className,
  );

  if (faceDown) {
    return <div className={cls} style={style} aria-hidden="true" />;
  }

  const glyph = suit ? SUIT_GLYPHS[suit] : '';
  return (
    <div className={cls} style={style} aria-label={`${rank} of ${suit}`}>
      <div className={clsx(styles.corner, styles.cornerTL)}>
        <span className={styles.rank}>{rank}</span>
        <span className={styles.suit}>{glyph}</span>
      </div>
      <div className={styles.pip}>{glyph}</div>
      <div className={clsx(styles.corner, styles.cornerBR)}>
        <span className={styles.rank}>{rank}</span>
        <span className={styles.suit}>{glyph}</span>
      </div>
    </div>
  );
}
