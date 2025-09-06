import type { Locale } from './i18n-config';

// We enumerate all dictionaries here for better linting and typescript support
// We also get the default import for cleaner types
const dictionaries: {
  [key: string]: () => Promise<{ postIdeas: string[] }>
} = {
  en: () => import('../dictionaries/en.json').then((module) => module.default),
  nl: () => import('../dictionaries/nl.json').then((module) => module.default),
  es: () => import('../dictionaries/es.json').then((module) => module.default),
  de: () => import('../dictionaries/de.json').then((module) => module.default),
  fr: () => import('../dictionaries/fr.json').then((module) => module.default),
  zh: () => import('../dictionaries/zh.json').then((module) => module.default),
  hi: () => import('../dictionaries/hi.json').then((module) => module.default),
};

export const getDictionary = async (locale: Locale) =>
  dictionaries[locale]?.() ?? dictionaries.en();
