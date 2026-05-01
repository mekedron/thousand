const SUIT_GLYPHS = {H: '♥', D: '♦', C: '♣', S: '♠'};
const SUIT_COLORS = {
  H: 'var(--ds-hearts)',
  D: 'var(--ds-diamonds)',
  C: '#1a1611',
  S: '#1a1611',
};

/**
 * @param {{ suit: 'H' | 'D' | 'C' | 'S', size?: number, color?: string }} props
 */
export default function SuitGlyph({suit, size = 14, color}) {
  return (
    <span
      style={{
        color: color ?? SUIT_COLORS[suit],
        fontSize: size,
        fontFamily: 'var(--ds-font-display)',
        lineHeight: 1,
        display: 'inline-block',
      }}>
      {SUIT_GLYPHS[suit]}
    </span>
  );
}
