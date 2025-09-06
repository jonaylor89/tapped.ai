import type { Metadata } from 'next';
import { Rubik } from 'next/font/google';
import './globals.css';
import { AuthContextProvider } from '@/context/AuthProvider';
import { Analytics } from '@vercel/analytics/react';
import { CreditsContextProvider } from '@/context/CreditsProvider';

const rubik = Rubik({
  subsets: ['latin'],
  weight: ['300', '400', '500', '700', '800', '900'],
});

const title = 'cover art generator';
const description = 'Generate cover art for your music';
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
          content={description}
        />
        <meta property="og:site_name" content="tapped.ai" />
        <meta
          property="og:description"
          content={description}
        />
        <meta
          property="og:title"
          content={title}
        />
        <meta property="og:image" content="https://getmusicart.com/og.png"></meta>
        <meta property="og:url" content="https://tapped.ai"></meta>
        <meta name="twitter:card" content="summary_large_image" />
        <meta
          name="twitter:title"
          content={title}
        />
        <meta
          name="twitter:description"
          content={description}
        />
        <meta property="twitter:image" content="https://getmusicart.com/og.png"></meta>
      </head>
      <body className={rubik.className}>
        <AuthContextProvider>
          <CreditsContextProvider>
            {children}
          </CreditsContextProvider>
        </AuthContextProvider>
      </body>
      <Analytics />
    </html>
  );
}
