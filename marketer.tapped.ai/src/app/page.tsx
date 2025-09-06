'use client';

import Link from 'next/link';
import { useEffect, useState } from 'react';
import Partners from '@/components/partners';
import Nav from '@/components/Nav';

export default function Home() {
  const words = [
    'album',
    'ep',
    'single',
  ];

  const [word, setWord] = useState('');

  // eslint-disable-next-line sonarjs/cognitive-complexity
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
        <h1 className="text-4xl md:text-5xl md:w-1/2 my-2 font-extrabold text-white text-center">
            market your next <span className="text-transparent bg-clip-text bg-gradient-to-br from-pink-400 to-red-600">{word}</span>
        </h1>
        <div className="h-4 md:h-6"></div>
        <h2 className="text-lg md:text-2xl md:w-1/3 font-light my-2 text-center">
         create a marketing plan for your next project
         just like the majors
        </h2>
        <div className="flex flex-col md:flex-row items-center gap-2 my-2 md:my-4 mb-8">
          <Link
            href="/marketing_form"
            className="bg-white text-black font-bold text-xl rounded-full px-4 py-2 hover:scale-105 transform transition-all duration-200 ease-in-out"
          >start now</Link>
          <Link
            href="https://www.loom.com/embed/ff089c94893f42219be46fb37bdfdfdf?sid=839ef7f2-a3fb-4585-9fca-75e38593d6a9"
            className="text-white bg-black font-bold text-xl rounded-full px-4 py-2 hover:scale-105 transform transition-all duration-200 ease-in-out"
          >
            tutorial
          </Link>
        </div>
      </div>
      <div className="mb-8">
        <Partners />
      </div>
    </main>
  );
}
