import '@/app/globals.css';
import type { Metadata } from 'next';
import { Arimo } from 'next/font/google';
import { Analytics } from '@vercel/analytics/react';
import { i18n } from '@/i18n-config';

const arimo = Arimo({ subsets: ['latin'] });

export const metadata: Metadata = {
  title: 'Viral Social Media Ideas',
  description: 'Generate viral social media idea with Ai for musicians',
  applicationName: 'viral-social-media-ideas',
  referrer: 'origin-when-cross-origin',
  keywords: ['Social Media', 'Musicians', 'Viral', 'Ai', 'Ideas', 'Generator', 'Music'],
  authors: [{ name: 'Johannes', url: 'https://jonaylor.xyz' }],
  creator: 'Johannes Naylor',
  publisher: 'Johannes Naylor',
  metadataBase: new URL('https://viralsocialmediaideas.com/'),
  alternates: {
    canonical: '/',
    languages: {
      'en-US': '/en-US',
    },
  },
  openGraph: {
    title: 'Viral Social Media Ideas',
    description: 'Generate viral social media idea with Ai for musicians',
    url: 'https://viralsocialmediaideas.com/',
    siteName: 'Viral Social Media Ideas',
    images: [
      {
        url: 'https://viralsocialmediaideas.com/og.png',
        width: 800,
        height: 600,
      },
    ],
    locale: 'en_US',
    type: 'website',
  },
};

export async function generateStaticParams() {
  return i18n.locales.map((locale) => ({ lang: locale }));
}

export default function RootLayout({
  children,
  params,
}: {
  children: React.ReactNode
  params: { lang: string }
}) {
  return (
    <html lang={params.lang}>
      <meta name="twitter:card" content="summary_large_image" />
      <meta
        name="twitter:title"
        content="Viral Social Media Ideas"
      />
      <meta
        name="twitter:description"
        content="Generate viral social media idea with Ai for musicians"
      />
      <meta property="twitter:image" content="https://viralsocialmediaideas.com/og.png"></meta>
      <body className={arimo.className}>
        {children}
        <Analytics />
      </body>
    </html>
  );
}
