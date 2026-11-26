import {loadFont as loadKufi} from '@remotion/google-fonts/NotoKufiArabic';
import {loadFont as loadPlex} from '@remotion/google-fonts/IBMPlexSansArabic';
import {loadFont as loadJakarta} from '@remotion/google-fonts/PlusJakartaSans';
import {loadFont as loadInter} from '@remotion/google-fonts/Inter';
import type {Lang} from './copy';

// Waad Brand Identity Guidelines 2026: navy, gold, tech blue, sage; headings Noto Kufi Arabic / Plus Jakarta Sans, body IBM Plex Sans Arabic / Inter
export const NAVY = '#142039';
export const NAVY_DEEP = '#0B1426';
export const GOLD = '#C9B27B';
export const BLUE = '#217FE1';
export const SAGE = '#81988C';

const {fontFamily: KUFI} = loadKufi('normal', {weights: ['600', '700'], subsets: ['arabic', 'latin']});
const {fontFamily: PLEX} = loadPlex('normal', {weights: ['400', '500', '600'], subsets: ['arabic', 'latin']});
const {fontFamily: JAKARTA} = loadJakarta('normal', {weights: ['600', '700', '800'], subsets: ['latin']});
const {fontFamily: INTER} = loadInter('normal', {weights: ['400', '500', '600'], subsets: ['latin']});

export const head = (l: Lang) => (l === 'ar' ? KUFI : JAKARTA);
export const body = (l: Lang) => (l === 'ar' ? PLEX : INTER);
export const dir = (l: Lang) => (l === 'ar' ? 'rtl' : 'ltr');
