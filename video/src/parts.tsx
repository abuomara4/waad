import React from 'react';
import {AbsoluteFill, Easing, Img, interpolate, random, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import focusJson from '../public/shots/focus.json';
import {BLUE, GOLD, NAVY, NAVY_DEEP, body, dir} from './brand';
import type {Lang} from './copy';

const FOCUS = focusJson as Record<string, number[] | null>;
const EASE = Easing.bezier(0.16, 1, 0.3, 1);
const CL = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;

export const useTall = () => {
  const {width, height} = useVideoConfig();
  return height > width;
};
// a tablet / iPad frame (4:3): the computer layout, a little tighter
export const useTab = () => {
  const {width, height} = useVideoConfig();
  return width > height && width / height < 1.5;
};

// the navy backdrop: a soft glow and slowly drifting dots (echoes the owner's intro)
export const Backdrop: React.FC<{glow?: string}> = ({glow = BLUE}) => {
  const frame = useCurrentFrame();
  const {width, height} = useVideoConfig();
  const dots = new Array(52).fill(0).map((_, i) => ({
    x: random(`x${i}`) * width, y: random(`y${i}`) * height, r: 1.2 + random(`r${i}`) * 3.2,
    c: random(`c${i}`) > 0.55 ? '#5FD3A0' : BLUE, s: 0.12 + random(`s${i}`) * 0.3, o: 0.18 + random(`o${i}`) * 0.45,
  }));
  return (
    <AbsoluteFill style={{background: `radial-gradient(110% 85% at 50% 35%, ${NAVY} 0%, ${NAVY_DEEP} 78%)`}}>
      <AbsoluteFill style={{background: `radial-gradient(40% 35% at ${50 + Math.sin(frame / 90) * 12}% ${42 + Math.cos(frame / 110) * 8}%, ${glow}22 0%, transparent 70%)`}} />
      {dots.map((d, i) => (
        <div key={i} style={{position: 'absolute', left: d.x, top: (d.y - frame * d.s + height) % height, width: d.r * 2, height: d.r * 2, borderRadius: '50%', background: d.c, opacity: d.o, filter: 'blur(0.7px)'}} />
      ))}
    </AbsoluteFill>
  );
};

// a line that rises out of a mask, word by word (Arabic letters stay joined)
export const Words: React.FC<{lang: Lang; text: string; delay?: number; style?: React.CSSProperties; gold?: string[]}> = ({lang, text, delay = 0, style, gold = []}) => {
  const frame = useCurrentFrame();
  return (
    <div dir={dir(lang)} lang={lang} style={{textWrap: 'balance', ...style}}>
      {text.split(' ').map((w, i) => (
        <span key={i} style={{display: 'inline-block', overflow: 'hidden', verticalAlign: 'bottom', paddingBottom: '0.12em', marginInlineEnd: '0.26em'}}>
          <span
            style={{
              display: 'inline-block',
              color: gold.includes(w) ? GOLD : undefined,
              translate: interpolate(frame, [delay + i * 3, delay + i * 3 + 16], ['0px 110%', '0px 0%'], {...CL, easing: EASE}),
              opacity: interpolate(frame, [delay + i * 3, delay + i * 3 + 8], [0, 1], CL),
            }}
          >
            {w}
          </span>
        </span>
      ))}
    </div>
  );
};

export const Chip: React.FC<{lang: Lang; text: string; delay: number; size: number}> = ({lang, text, delay, size}) => {
  const frame = useCurrentFrame();
  const from = lang === 'ar' ? '40px 0px' : '-40px 0px';
  return (
    <div
      dir={dir(lang)}
      style={{
        display: 'flex', alignItems: 'center', gap: size * 0.5, fontFamily: body(lang), fontWeight: 500, fontSize: size, color: '#E6ECF5',
        opacity: interpolate(frame, [delay, delay + 12], [0, 1], CL),
        translate: interpolate(frame, [delay, delay + 18], [from, '0px 0px'], {...CL, easing: EASE}),
      }}
    >
      <span
        style={{
          width: size * 0.95, height: size * 0.95, borderRadius: '50%', background: GOLD, color: NAVY, display: 'grid', placeItems: 'center',
          fontSize: size * 0.6, fontWeight: 700, flex: 'none',
          scale: interpolate(frame, [delay + 4, delay + 16], [0.3, 1], {...CL, easing: Easing.bezier(0.34, 1.56, 0.64, 1)}),
        }}
      >
        ✓
      </span>
      <span>{text}</span>
    </div>
  );
};

// the cursor: glides to the highlighted part, presses, and a ripple answers
const Cursor: React.FC<{x: number; y: number; from: [number, number]; t0: number; size: number}> = ({x, y, from, t0, size}) => {
  const frame = useCurrentFrame();
  const p = interpolate(frame, [t0, t0 + 26], [0, 1], {...CL, easing: Easing.bezier(0.45, 0, 0.2, 1)});
  const cx = from[0] + (x - from[0]) * p, cy = from[1] + (y - from[1]) * p - Math.sin(p * Math.PI) * size * 1.4;
  const press = interpolate(frame, [t0 + 28, t0 + 31, t0 + 36], [1, 0.82, 1], CL);
  const ring = interpolate(frame, [t0 + 29, t0 + 52], [0, 1], CL);
  return (
    <>
      <div style={{position: 'absolute', left: x - size * 1.6, top: y - size * 1.6, width: size * 3.2, height: size * 3.2, borderRadius: '50%',
        border: `${size * 0.12}px solid ${GOLD}`, opacity: ring > 0 ? (1 - ring) * 0.9 : 0, scale: 0.3 + ring * 0.9}} />
      <svg viewBox="0 0 24 24" style={{position: 'absolute', left: cx, top: cy, width: size, height: size, scale: press, transformOrigin: '0 0',
        opacity: interpolate(frame, [t0 - 6, t0 + 2], [0, 1], CL), filter: 'drop-shadow(0 4px 8px rgba(0,0,0,.45))'}}>
        <path d="M3 2l17 10.2-7.6 1.5 4.3 7.6-3 1.7-4.3-7.6L3.8 20z" fill="#fff" stroke="#0B1426" strokeWidth="1.4" strokeLinejoin="round" />
      </svg>
    </>
  );
};

// a real screen in a computer window or a phone; the "camera" pushes in on the part that matters,
// a gold frame lights it up and the cursor presses it
export const Device: React.FC<{lang: Lang; shot: string; kind: 'desk' | 'phone'; w: number; t0?: number}> = ({lang, shot, kind, w, t0 = 26}) => {
  const frame = useCurrentFrame();
  const {durationInFrames} = useVideoConfig();
  const desk = kind === 'desk';
  const bar = desk ? w * 0.03 : 0, pad = desk ? 0 : w * 0.035;
  const vw = w - pad * 2, vh = desk ? vw * 0.625 : vw * 1.777;
  const f = FOCUS[`${lang}/${shot}-${kind}`] || [0.25, 0.25, 0.5, 0.5];
  // the zoom that makes the focus fill about 72% of the view, kept between 1.15 and 2.2
  // a phone screen is already narrow: only push in when the part is small, else a gentle 5% drift
  const z = Math.max(desk ? 1.15 : 1.05, Math.min(2.2, 0.8 / Math.max(f[2], f[3])));
  const cx = f[0] + f[2] / 2, cy = f[1] + f[3] / 2;
  const tx = Math.min(0, Math.max(vw - vw * z, vw / 2 - cx * vw * z));
  const ty = Math.min(0, Math.max(vh - vh * z, vh / 2 - cy * vh * z));
  const zoom = interpolate(frame, [t0, t0 + 34, durationInFrames - 8], [0, 1, 1.04], {...CL, easing: Easing.bezier(0.65, 0, 0.35, 1)});
  const s = 1 + (z - 1) * zoom;
  const ringIn = interpolate(frame, [t0 + 30, t0 + 44], [0, 1], CL);
  const enter = interpolate(frame, [0, 22], [0, 1], {...CL, easing: EASE});
  return (
    <div
      style={{
        width: w, borderRadius: desk ? 18 : w * 0.12, padding: pad, overflow: 'hidden', background: desk ? '#0E1830' : '#050A14',
        boxShadow: '0 50px 110px -30px rgba(0,0,0,.8), 0 0 0 1px rgba(255,255,255,.1)',
        opacity: enter, scale: 0.92 + enter * 0.08, translate: `0px ${(1 - enter) * 60}px`,
        rotate: desk ? `${interpolate(frame, [0, durationInFrames], [lang === 'ar' ? -0.6 : 0.6, 0])}deg` : '0deg',
      }}
    >
      {desk ? (
        <div style={{height: bar, background: '#1A2744', display: 'flex', alignItems: 'center', gap: w * 0.008, paddingInline: w * 0.014}}>
          {['#FF5F57', '#FEBC2E', '#28C840'].map((c) => <span key={c} style={{width: w * 0.0095, height: w * 0.0095, borderRadius: '50%', background: c}} />)}
        </div>
      ) : null}
      <div style={{position: 'relative', width: vw, height: vh, overflow: 'hidden', borderRadius: desk ? 0 : w * 0.09, background: '#111A2E'}}>
        <div style={{position: 'absolute', left: 0, top: 0, width: vw, height: vh, transformOrigin: '0 0', translate: `${tx * zoom}px ${ty * zoom}px`, scale: s}}>
          <Img src={staticFile(`shots/${lang}/${shot}-${kind}.png`)} style={{width: vw, height: vh, objectFit: 'cover', objectPosition: 'top center'}} />
          <div
            style={{
              position: 'absolute', left: `${f[0] * 100}%`, top: `${f[1] * 100}%`, width: `${f[2] * 100}%`, height: `${f[3] * 100}%`,
              borderRadius: 10, border: `${3 / s}px solid ${GOLD}`, opacity: ringIn,
              boxShadow: `0 0 0 ${9999}px rgba(5,10,20,${0.38 * ringIn}), 0 0 ${24 / s}px ${GOLD}88`,
            }}
          />
        </div>
        <Cursor x={cx * vw * z + tx} y={cy * vh * z + ty} from={[lang === 'ar' ? vw * 0.85 : vw * 0.15, vh * 0.95]} t0={t0 + 2} size={desk ? w * 0.03 : w * 0.07} />
      </div>
    </div>
  );
};

export const Logo: React.FC<{w: number}> = ({w}) => <Img src={staticFile('logo-dark.webp')} style={{width: w}} />;

// a warm light sweep over a cut (drawn in CSS so it renders the same everywhere)
export const LightSweep: React.FC<{reverse?: boolean}> = ({reverse = false}) => {
  const frame = useCurrentFrame();
  const {durationInFrames} = useVideoConfig();
  const p = interpolate(frame, [0, durationInFrames - 1], [0, 1], CL);
  const x = reverse ? 120 - p * 140 : -20 + p * 140;
  return (
    <AbsoluteFill style={{pointerEvents: 'none', mixBlendMode: 'screen', opacity: Math.sin(p * Math.PI) * 0.55,
      background: `radial-gradient(60% 90% at ${x}% 30%, rgba(255,196,110,.9) 0%, rgba(201,178,123,.35) 35%, transparent 70%)`}} />
  );
};
