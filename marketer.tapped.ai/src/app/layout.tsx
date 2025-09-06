import { Analytics } from '@vercel/analytics/react';
import './globals.css';
import type { Metadata } from 'next';
import { Rubik } from 'next/font/google';

const rubik = Rubik({
  subsets: ['latin'],
  weight: ['300', '400', '500', '600', '700', '800', '900'],
});

const title = 'Your Personal Marketer';
const description = 'Get Music Marketing | create a marketing plan for your album, ep, or single | by Tapped Ai';
export const metadata: Metadata = {
  title,
  description,
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="en">
      <head>
        <link rel="icon" href="/favicon.ico" />
        <link
          rel="stylesheet"
          href="https://fonts.googleapis.com/icon?family=Material+Icons"
        />
        <meta
          name="description"
          content={metadata.description}
        />
        <meta property="og:site_name" content="tapped.ai" />
        <meta
          property="og:description"
          content={metadata.description}
        />
        <meta
          property="og:title"
          content={title}
        />
        <meta property="og:image" content="https://marketer.tapped.ai/og.png"></meta>
        <meta property="og:url" content="https://tapped.ai"></meta>
        <meta name="twitter:card" content="summary_large_image" />
        <meta
          name="twitter:title"
          content={title}
        />
        <meta
          name="twitter:description"
          content={metadata.description}
        />
        <meta property="twitter:image" content="https://marketer.tapped.ai/og.png"></meta>
      </head>
      <body className={rubik.className}>
        {children}
      </body>
      <Analytics />
    </html>
  );
}
