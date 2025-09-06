'use client';

import Link from 'next/link';
import { useEffect, useState } from 'react';
import Partners from '@/components/partners';
import Nav from '@/components/Nav';

const paymentLink = process.env.NEXT_PUBLIC_STRIPE_PAYMENT_LINK ?? '';

export default function Home() {
  const words = [
    'tips',
    'insights',
    'statistics',
  ];

  const [word, setWord] = useState('');

  useEffect(() => {
    const len = words.length;
    const skipDelay = 15;

    let forwards = true;
    let skipCount = 0;
    let i = 0;
    let offset = 0;

    const timer = setInterval(() => {
      if (forwards) {
        if (offset >= words[i].length) {
          ++skipCount;
          if (skipCount === skipDelay) {
            forwards = false;
            skipCount = 0;
          }
        }
      } else {
        if (offset === 0) {
          forwards = true;
          ++i;
          offset = 0;
          if (i >= len) {
            i = 0;
          }
        }
      }
      const part = words[i].substr(0, offset);
      if (skipCount === 0) {
        if (forwards) {
          ++offset;
        } else {
          --offset;
        }
      }

      setWord(part);
    }, 100);

    return () => clearInterval(timer);
  }, []);

  return (
    <main className="relative h-screen flex flex-col blueShapesBackground p-2 md:p-0">
      <div className="firstCircle md:block"></div>
      <div className="secondCircle md:block"></div>
      <div className="thirdCircle hidden md:block"></div>
      <Nav />
      <div className="flex-grow flex flex-col justify-center items-center">
        <h1 className="text-4xl md:text-5xl md:w-3/4 my-2 font-extrabold text-white text-center">
            get music marketing <span className="text-transparent bg-clip-text bg-gradient-to-br from-pink-400 to-red-600">{word}</span>
        </h1>
        <div className="h-4 md:h-6"></div>
        <h2 className="text-lg md:text-2xl md:w-1/3 font-light my-2 text-center">
         sign up for the best music
         marketing advice weekly.
        </h2>
        <div className="my-2 md:my-4">
          <Link
            href={paymentLink}
            className="bg-white text-black font-bold text-xl rounded-full px-4 py-2 hover:scale-105 transform transition-all duration-200 ease-in-out"
          >sign up</Link>
        </div>
        <h2 className="text-lg md:text-2xl md:w-1/3 font-light my-2 text-center">
            to access our full <a href="https://tapped.ai" className="underline hover:text-[#63b2fd]">suite</a>
        </h2>
      </div>

      <div className="mb-8">
        <Partners />
      </div>
    </main>
  );
}
