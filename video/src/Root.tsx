import React from 'react';
import {Composition, Folder} from 'remotion';
import {FPS, TOTAL, WaadTour} from './WaadTour';

// the website's tour, one per language: wide (computers), tablet / iPad (4:3) and tall (phones)
export const RemotionRoot: React.FC = () => (
  <Folder name="Website">
    <Composition id="TourWideAr" component={WaadTour} durationInFrames={TOTAL} fps={FPS} width={1920} height={1080} defaultProps={{lang: 'ar' as const}} />
    <Composition id="TourTallAr" component={WaadTour} durationInFrames={TOTAL} fps={FPS} width={1080} height={1920} defaultProps={{lang: 'ar' as const}} />
    <Composition id="TourTabAr" component={WaadTour} durationInFrames={TOTAL} fps={FPS} width={1440} height={1080} defaultProps={{lang: 'ar' as const}} />
    <Composition id="TourWideEn" component={WaadTour} durationInFrames={TOTAL} fps={FPS} width={1920} height={1080} defaultProps={{lang: 'en' as const}} />
    <Composition id="TourTallEn" component={WaadTour} durationInFrames={TOTAL} fps={FPS} width={1080} height={1920} defaultProps={{lang: 'en' as const}} />
    <Composition id="TourTabEn" component={WaadTour} durationInFrames={TOTAL} fps={FPS} width={1440} height={1080} defaultProps={{lang: 'en' as const}} />
  </Folder>
);
