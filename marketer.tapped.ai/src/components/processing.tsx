'use client';
import { useState, useEffect } from 'react';


export default function Processing() {
  const words = ['...'];
  const [periods, setPeriods] = useState('...');
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

      setPeriods(part);
    }, 50);
    return () => clearInterval(timer);
  }, []);

  return (
    <div className="h-screen flex justify-center items-center">
      <div id="loading-gif" className="relative">
        <div className="absolute top-0 left-0 w-screen">
          <div className="flex h-screen justify-center items-center">
            <div className="bg-black p-6 rounded-xl">
              <h1 className="text-4xl">processing{periods}</h1>
              <div className="h-6"></div>
              <p className="text-white">
                hang tight while we work our magic
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
