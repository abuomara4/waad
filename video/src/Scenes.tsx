import React from 'react';
import {AbsoluteFill, Easing, interpolate, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {Video} from '@remotion/media';
import {GOLD, body, dir, head} from './brand';
import {COPY, type Feature, type Lang} from './copy';
import {Backdrop, Chip, Device, Logo, useTall, Words} from './parts';

const CL = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;
const EASE = Easing.bezier(0.16, 1, 0.3, 1);

// the owner's brand intro (landscape for computers, portrait for phones)
export const IntroScene: React.FC = () => {
  const tall = useTall();
  return (
    <AbsoluteFill style={{backgroundColor: '#031214'}}>
      <Video src={staticFile(tall ? 'intro-tall.mp4' : 'intro-wide.mp4')} style={{width: '100%', height: '100%', objectFit: 'cover'}} />
    </AbsoluteFill>
  );
};

export const HookScene: React.FC<{lang: Lang}> = ({lang}) => {
  const tall = useTall();
  const frame = useCurrentFrame();
  const c = COPY[lang];
  const size = (tall ? 108 : 118) * (lang === 'en' ? 0.9 : 1);
  const line: React.CSSProperties = {fontFamily: head(lang), fontWeight: 700, fontSize: size, color: '#fff', lineHeight: lang === 'ar' ? 1.45 : 1.15, letterSpacing: lang === 'en' ? '-0.02em' : 0};
  // a slow push-in on the whole line, like a camera dolly
  const push = interpolate(frame, [0, 105], [1, 1.06]);
  return (
    <AbsoluteFill>
      <Backdrop />
      <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center', textAlign: 'center', padding: tall ? 80 : 160, gap: tall ? 44 : 36, scale: push}}>
        <div>
          <Words lang={lang} text={c.hook1} style={line} />
          <Words lang={lang} text={c.hook2} delay={9} gold={c.hookGold} style={line} />
        </div>
        <div style={{width: interpolate(frame, [20, 44], [0, tall ? 260 : 340], {...CL, easing: EASE}), height: 4, borderRadius: 2, background: GOLD}} />
        <div dir={dir(lang)} style={{fontFamily: body(lang), fontSize: tall ? 40 : 38, color: '#C9D4E6', lineHeight: 1.6, opacity: interpolate(frame, [30, 46], [0, 1], CL), translate: `0px ${interpolate(frame, [30, 50], [16, 0], {...CL, easing: EASE})}px`}}>
          {c.hookSub}
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

export const FeatureScene: React.FC<{lang: Lang; f: Feature; i: number}> = ({lang, f, i}) => {
  const tall = useTall();
  const frame = useCurrentFrame();
  const kick = (
    <div dir={dir(lang)} style={{display: 'flex', alignItems: 'center', gap: 18, fontFamily: body(lang), fontWeight: 600, fontSize: tall ? 38 : 32, color: GOLD, letterSpacing: lang === 'en' ? '0.08em' : 0, textTransform: lang === 'en' ? 'uppercase' : 'none', opacity: interpolate(frame, [0, 12], [0, 1], CL)}}>
      <span dir="ltr" style={{fontFamily: head('en'), fontWeight: 700, opacity: 0.7}}>{`0${i + 1}`}</span>
      <span style={{width: interpolate(frame, [2, 20], [0, 54], {...CL, easing: EASE}), height: 3, background: GOLD, borderRadius: 2}} />
      <span>{f.kicker}</span>
    </div>
  );
  const title = (
    <Words lang={lang} text={f.title} delay={4} gold={f.gold}
      style={{fontFamily: head(lang), fontWeight: 700, fontSize: tall ? (lang === 'en' ? 74 : 70) : (lang === 'en' ? 66 : 72), color: '#fff', lineHeight: lang === 'ar' ? 1.35 : 1.12, letterSpacing: lang === 'en' ? '-0.02em' : 0}} />
  );
  const list = (
    <div style={{display: 'flex', flexDirection: 'column', gap: tall ? 24 : 24, marginTop: tall ? 10 : 26}}>
      {f.points.map((p, k) => <Chip key={p} lang={lang} text={p} delay={20 + k * 9} size={tall ? 40 : 36} />)}
    </div>
  );
  if (tall) {
    return (
      <AbsoluteFill>
        <Backdrop />
        <AbsoluteFill dir={dir(lang)} style={{padding: '120px 76px 0', alignItems: 'flex-start', gap: 16}}>
          {kick}
          {title}
          {list}
        </AbsoluteFill>
        <AbsoluteFill style={{justifyContent: 'flex-start', alignItems: 'center', paddingTop: 760}}>
          <Device lang={lang} shot={f.shot} kind="phone" w={600} />
        </AbsoluteFill>
      </AbsoluteFill>
    );
  }
  return (
    <AbsoluteFill>
      <Backdrop />
      <AbsoluteFill dir={dir(lang)} style={{flexDirection: 'row', alignItems: 'center', padding: '0 100px', gap: 70}}>
        <div style={{flex: 'none', width: 660, display: 'flex', flexDirection: 'column', alignItems: 'flex-start', gap: 16}}>
          {kick}
          {title}
          {list}
        </div>
        <div style={{flex: 1, display: 'flex', justifyContent: 'center'}}>
          <Device lang={lang} shot={f.shot} kind="desk" w={1040} />
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

export const COUNTER_DELAYS = [0, 9, 18, 27];
const Counter: React.FC<{lang: Lang; to: number; label: string; delay: number; size: number}> = ({lang, to, label, delay, size}) => {
  const frame = useCurrentFrame();
  const n = Math.round(interpolate(frame, [delay, delay + 36], [0, to], {...CL, easing: EASE}));
  const land = interpolate(frame, [delay + 30, delay + 36, delay + 44], [1, 1.08, 1], CL);
  return (
    <div style={{display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 12, opacity: interpolate(frame, [delay, delay + 10], [0, 1], CL), translate: `0px ${interpolate(frame, [delay, delay + 20], [30, 0], {...CL, easing: EASE})}px`}}>
      <div dir="ltr" style={{fontFamily: head('en'), fontWeight: 800, fontSize: size, color: GOLD, lineHeight: 1, scale: land, fontVariantNumeric: 'tabular-nums'}}>{n}</div>
      <div dir={dir(lang)} style={{fontFamily: body(lang), fontWeight: 500, fontSize: size * 0.27, color: '#E6ECF5', textAlign: 'center', maxWidth: size * 2.6, lineHeight: 1.4}}>{label}</div>
    </div>
  );
};

export const NumbersScene: React.FC<{lang: Lang}> = ({lang}) => {
  const tall = useTall();
  const size = tall ? 160 : 140;
  return (
    <AbsoluteFill>
      <Backdrop />
      <AbsoluteFill dir={dir(lang)} style={{display: 'grid', gridTemplateColumns: tall ? '1fr 1fr' : 'repeat(4, 1fr)', gap: tall ? '120px 40px' : 40, padding: tall ? '0 60px' : '0 110px', alignContent: 'center', justifyItems: 'center'}}>
        {COPY[lang].numbers.map((x, k) => <Counter key={k} lang={lang} to={x.to} label={x.label} delay={COUNTER_DELAYS[k]} size={size} />)}
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

export const CtaScene: React.FC<{lang: Lang}> = ({lang}) => {
  const tall = useTall();
  const frame = useCurrentFrame();
  const {durationInFrames} = useVideoConfig();
  const c = COPY[lang];
  const shine = interpolate(frame, [40, 80], [-30, 130], CL);
  return (
    <AbsoluteFill>
      <Backdrop glow={GOLD} />
      <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center', gap: tall ? 50 : 40, textAlign: 'center', padding: tall ? 50 : 100, scale: interpolate(frame, [0, durationInFrames], [1, 1.04])}}>
        <div style={{position: 'relative', scale: interpolate(frame, [0, 22], [0.85, 1], {...CL, easing: EASE}), opacity: interpolate(frame, [0, 12], [0, 1], CL)}}>
          <Logo w={tall ? 500 : 440} />
          <div style={{position: 'absolute', inset: 0, background: `linear-gradient(105deg, transparent ${shine - 12}%, rgba(255,255,255,.55) ${shine}%, transparent ${shine + 12}%)`, mixBlendMode: 'overlay', WebkitMaskImage: `url(${staticFile('logo-dark.webp')})`, WebkitMaskSize: '100% 100%'}} />
        </div>
        <Words lang={lang} text={c.cta} delay={10} gold={c.ctaGold} style={{fontFamily: head(lang), fontWeight: 700, fontSize: (tall ? 82 : 92) * (lang === 'en' ? 0.92 : 1), color: '#fff', lineHeight: 1.3}} />
        <div
          style={{
            fontFamily: body(lang), fontWeight: 600, fontSize: tall ? 40 : 36, color: '#0B1426', background: GOLD, borderRadius: 8, padding: tall ? '22px 52px' : '18px 46px',
            opacity: interpolate(frame, [28, 40], [0, 1], CL), scale: interpolate(frame, [28, 42], [0.7, 1], {...CL, easing: Easing.bezier(0.34, 1.56, 0.64, 1)}),
          }}
        >
          {lang === 'ar' ? 'ابدأ تجربتك الآن' : 'Start your free trial'}
        </div>
        <div dir={dir(lang)} style={{fontFamily: body(lang), fontSize: tall ? 36 : 34, color: '#C9D4E6', opacity: interpolate(frame, [40, 54], [0, 1], CL)}}>
          {c.ctaSub}
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
