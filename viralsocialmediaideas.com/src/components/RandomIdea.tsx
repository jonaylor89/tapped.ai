'use client';

import { useEffect, useState } from 'react';
import { randomChoice } from '@/utils/random';
import { track } from '@vercel/analytics';

const RandomIdea = ({ ideas }: {
    ideas: string[]
}) => {
  const [idea, setIdea] = useState('');
  const [loading, setLoading] = useState(true);

  const newPostIdea = async () => {
    setLoading(true);
    const idea = randomChoice(ideas);
    track('new-idea', {
      idea,
    });
    setIdea(idea);
    setTimeout(() => {
      setLoading(false);
    }, 500);
  };

  useEffect(() => {
    newPostIdea();
  }, []);

  useEffect(() => {
    const handleKeyboardEvent = (event: KeyboardEvent) => {
      if (event.code === 'Space') {
        newPostIdea();
      }
    };

    document.addEventListener('keyup', handleKeyboardEvent);
    // clean up
    return () => {
      document.removeEventListener('keyup', handleKeyboardEvent);
    };
  }, []);

  if (loading) {
    return (
      <>
        <div>
          <h3
            className='text-2xl font-bold text-center text-white'
          >creating something special for you...</h3>
          <div className="h-8" />
          <div className='flex justify-center'>
            <div
              className="inline-block h-12 w-12 animate-spin rounded-full border-4 border-solid border-current border-r-transparent align-[-0.125em] motion-reduce:animate-[spin_1.5s_linear_infinite]"
              role="status">
              <span
                className="!absolute !-m-px !h-px !w-px !overflow-hidden !whitespace-nowrap !border-0 !p-0 ![clip:rect(0,0,0,0)]"
              >Loading...</span>
            </div>
          </div>
        </div>
      </>
    );
  }

  return (
    <>
      <div className="flex flex-col justify-center items-center text-center lg:max-w-5xl lg:w-full pb-12">
        <div className="text-5xl font-extrabold m-2 md:w-2/3 text-white lowercase">
          {idea}
        </div>
        <div className="p-6"></div>
        <button
          className="bg-black p-4 rounded-full text-white font-bold text-lg"
          onClick={newPostIdea}>
          show me the next idea!
        </button>
        <div className="p-2"></div>
        <div className="hidden md:block">
          or press space
        </div>
      </div>
    </>
  );
};

export default RandomIdea;
