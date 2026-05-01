import clsx from 'clsx';
import CardArt from '../CardArt/CardArt';
import styles from './AppPromoTable.module.css';

const LEFT = {
  name: 'Vera A.',
  glyph: 'В',
  hue: 25,
  score: 285,
  cards: 8,
  bid: 110,
  passed: false,
};
const RIGHT = {
  name: 'Marek D.',
  glyph: 'M',
  hue: 220,
  score: 410,
  cards: 8,
  bid: null,
  passed: true,
};

const HAND = [
  {rank: 'A', suit: 'H', legal: false},
  {rank: 'K', suit: 'H', legal: false},
  {rank: 'Q', suit: 'S', legal: false},
  {rank: 'J', suit: 'C', legal: false},
  {rank: '10', suit: 'D', legal: true, selected: true},
  {rank: '9', suit: 'D', legal: true},
  {rank: 'Q', suit: 'D', legal: true},
];

const RACE = [
  {name: 'You', value: 530, brass: true},
  {name: 'Marek', value: 410},
  {name: 'Vera', value: 285},
];

function MiniOpponent({player, side, isTurn}) {
  const fan = [];
  const N = player.cards;
  for (let i = 0; i < N; i++) {
    const off = (i - (N - 1) / 2) * 9;
    const rot = (i - (N - 1) / 2) * 1.4;
    fan.push(
      <div
        key={i}
        className={styles.fanCard}
        style={{transform: `translateX(${off - 16}px) rotate(${rot}deg)`}}>
        <CardArt faceDown size="xs" />
      </div>,
    );
  }

  const avatarBg = `linear-gradient(135deg, hsl(${player.hue} 50% 45%), hsl(${player.hue} 50% 28%))`;

  return (
    <div
      className={clsx(
        styles.miniRow,
        side === 'right' && styles.miniRowReverse,
      )}>
      <div
        className={clsx(styles.avatar, isTurn && styles.avatarTurn)}
        style={{background: avatarBg}}>
        {player.glyph}
      </div>
      <div
        className={clsx(
          styles.miniMeta,
          side === 'right' && styles.miniMetaRight,
        )}>
        <div className={styles.miniName}>{player.name}</div>
        <div className={styles.miniRow2}>
          <span className={styles.miniScore}>{player.score}</span>
          {player.bid && <span className={styles.bidChip}>bid {player.bid}</span>}
          {player.passed && <span className={styles.passedChip}>passed</span>}
        </div>
        <div className={styles.fanWrap}>{fan}</div>
      </div>
    </div>
  );
}

export default function AppPromoTable() {
  const handMid = (HAND.length - 1) / 2;

  return (
    <div className={styles.frame}>
      <div className={styles.chrome}>
        <span className={clsx(styles.dot, styles.dotR)} />
        <span className={clsx(styles.dot, styles.dotY)} />
        <span className={clsx(styles.dot, styles.dotG)} />
        <div className={styles.chromeTitle}>Thousand · Deal 07</div>
      </div>

      <div className={styles.layout}>
        <div className={styles.felt}>
          <div className={styles.feltTexture} />

          <div className={styles.opponentLeft}>
            <MiniOpponent player={LEFT} side="left" />
          </div>
          <div className={styles.opponentRight}>
            <MiniOpponent player={RIGHT} side="right" />
          </div>

          <div className={styles.trumpIndicator}>
            <div className={styles.trumpLabel}>Trump</div>
            <div className={styles.trumpGlyph}>♦</div>
          </div>

          <div className={styles.trickArea}>
            <div className={styles.trickCardLeft}>
              <CardArt rank="A" suit="D" size="sm" />
            </div>
            <div className={styles.trickCardCenter}>
              <CardArt rank="K" suit="D" size="sm" />
            </div>
          </div>

          <div className={styles.handRow}>
            <div className={styles.handFan}>
              {HAND.map((c, i) => {
                const tilt = (i - handMid) * 4;
                const lift = Math.abs(i - handMid) * 2;
                const ty = c.selected ? -16 : lift;
                return (
                  <div
                    key={i}
                    className={clsx(
                      styles.handCard,
                      c.selected && styles.handCardSelected,
                      !c.legal && styles.handCardIllegal,
                    )}
                    style={{
                      transform: `translateY(${ty}px) rotate(${tilt}deg)`,
                      marginLeft: i === 0 ? 0 : -22,
                    }}>
                    <CardArt rank={c.rank} suit={c.suit} size="xs" />
                  </div>
                );
              })}
            </div>
          </div>

          <div className={styles.youLabel}>
            <div className={styles.youAvatar}>Y</div>
            <div>
              <div className={styles.youName}>You</div>
              <div className={styles.youRole}>declarer · 530</div>
            </div>
          </div>

          <div className={styles.hint}>must follow · ♦</div>
        </div>

        <div className={styles.rail}>
          <div className={styles.railRow}>
            <span className={styles.railLabel}>Deal 07</span>
            <span className={styles.railLabelBrass}>tricks</span>
          </div>
          <div className={styles.railDiv} />
          <div className={styles.railLabel}>Race to 1000</div>
          {RACE.map((p) => (
            <div key={p.name} className={styles.raceRow}>
              <div className={styles.raceHeader}>
                <span className={styles.raceName}>{p.name}</span>
                <span
                  className={clsx(styles.raceValue, p.brass && styles.raceValueBrass)}>
                  {p.value}
                </span>
              </div>
              <div className={styles.bar}>
                <div
                  className={clsx(styles.barFill, p.brass && styles.barFillBrass)}
                  style={{width: `${(p.value / 1000) * 100}%`}}
                />
              </div>
            </div>
          ))}
          <div className={styles.railDiv} />
          <div>
            <div className={styles.railLabel}>Contract</div>
            <div className={styles.contractValue}>110</div>
          </div>
          <div>
            <div className={styles.railLabel}>Trump</div>
            <div className={styles.railTrump}>♦</div>
          </div>
        </div>
      </div>

      <div className={styles.foot}>
        <span>v0.7.3 · Lua/Love2D</span>
        <span>Trick 4 of 8 · ♦ leads</span>
      </div>
    </div>
  );
}
