import React from 'react';
import {AbsoluteFill, Sequence, staticFile} from 'remotion';
import {Audio} from '@remotion/media';
import {TransitionSeries, linearTiming, springTiming} from '@remotion/transitions';
import {fade} from '@remotion/transitions/fade';
import {slide} from '@remotion/transitions/slide';
import {COPY, type Lang} from './copy';
import {LightSweep} from './parts';
import {COUNTER_DELAYS, CtaScene, FeatureScene, HookScene, IntroScene, NumbersScene} from './Scenes';

// timing (30 fps): intro 10 s, promise 3.5 s, six sections × 4.6 s, numbers 4 s, call to action 5 s
export const FPS = 30;
const INTRO = 300, HOOK = 105, FEAT = 138, NUMS = 120, CTA = 150;
const T_FADE = 15, T_CUT = 16;
const SCENES = [INTRO, HOOK, ...new Array(6).fill(FEAT), NUMS, CTA];
const TRANS = [T_FADE, ...new Array(SCENES.length - 2).fill(T_CUT)];
// where each scene starts once the transitions overlap
export const STARTS = SCENES.map((_, i) => SCENES.slice(0, i).reduce((a, b) => a + b, 0) - TRANS.slice(0, i).reduce((a, b) => a + b, 0));
export const TOTAL = SCENES.reduce((a, b) => a + b, 0) - TRANS.reduce((a, b) => a + b, 0);

const Sfx: React.FC<{at: number; src: string; volume?: number}> = ({at, src, volume = 0.5}) => (
  <Sequence from={Math.max(0, at)} durationInFrames={60} layout="none">
    <Audio src={staticFile(`sfx/${src}.wav`)} volume={volume} />
  </Sequence>
);

export const WaadTour: React.FC<{lang: Lang}> = ({lang}) => {
  const c = COPY[lang];
  // Arabic reads right to left, so the next section enters from the left; English the other way
  const next = slide({direction: lang === 'ar' ? 'from-left' : 'from-right'});
  const cut = springTiming({config: {damping: 200}, durationInFrames: T_CUT});
  const feats = STARTS.slice(2, 8);
  return (
    <AbsoluteFill style={{backgroundColor: '#0B1426'}}>
      <TransitionSeries>
        <TransitionSeries.Sequence name="Intro" durationInFrames={INTRO}><IntroScene /></TransitionSeries.Sequence>
        <TransitionSeries.Transition presentation={fade()} timing={linearTiming({durationInFrames: T_FADE})} />
        <TransitionSeries.Sequence name="Hook" durationInFrames={HOOK}><HookScene lang={lang} /></TransitionSeries.Sequence>
        {c.features.map((f, i) => (
          <React.Fragment key={f.shot}>
            <TransitionSeries.Transition presentation={next} timing={cut} />
            <TransitionSeries.Sequence name={f.shot} durationInFrames={FEAT}><FeatureScene lang={lang} f={f} i={i} /></TransitionSeries.Sequence>
          </React.Fragment>
        ))}
        <TransitionSeries.Transition presentation={fade()} timing={cut} />
        <TransitionSeries.Sequence name="Numbers" durationInFrames={NUMS}><NumbersScene lang={lang} /></TransitionSeries.Sequence>
        <TransitionSeries.Transition presentation={fade()} timing={cut} />
        <TransitionSeries.Sequence name="CTA" durationInFrames={CTA}><CtaScene lang={lang} /></TransitionSeries.Sequence>
      </TransitionSeries>

      {/* light sweeps over the cuts */}
      {STARTS.slice(2).map((s, i) => (
        <Sequence key={`l${i}`} from={s - 4} durationInFrames={T_CUT + 14} name="light">
          <LightSweep reverse={lang === 'ar'} />
        </Sequence>
      ))}

      {/* sound design: a whoosh on each cut, a click when the cursor presses, a pop on each number, a chime at the end */}
      <Sfx at={STARTS[1] - 6} src="whoosh" volume={0.35} />
      {STARTS.slice(2).map((s, i) => <Sfx key={`w${i}`} at={s - T_CUT} src="whoosh" volume={0.4} />)}
      {feats.map((s, i) => <Sfx key={`c${i}`} at={s + 56} src="click" volume={0.55} />)}
      {COUNTER_DELAYS.map((d, i) => <Sfx key={`p${i}`} at={STARTS[8] + d + 34} src="pop" volume={0.45} />)}
      <Sfx at={STARTS[9] + 12} src="ding" volume={0.5} />
    </AbsoluteFill>
  );
};
