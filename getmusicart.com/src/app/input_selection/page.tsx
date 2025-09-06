'use client';

import Link from 'next/link';
import { toast, Toaster } from 'react-hot-toast';
import CreditsChip from '@/components/CreditsChip';
import { useAuth } from '@/context/AuthProvider';
import { useState } from 'react';
// import { decrementUserCredits } from '@/utils/database';
import { useCredits } from '@/context/CreditsProvider';
import { enqueueSpotifyTrack } from '@/utils/cyanite';

export default function InputSelection() {
  const { authUser } = useAuth();
  const { credits } = useCredits();
  const [spotifyLink, setSpotifyLink] = useState('');
  const [loading, setLoading] = useState(false);

  async function submitForm(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();

    if (authUser === null) {
      toast.error('please login first');
      return;
    }

    if (spotifyLink === '') {
      toast.error('please enter a spotify link');
      return;
    }

    try {
      setLoading(true);
      toast('generating your image...', { position: 'top-center' });
      // await decrementUserCredits(authUser.uid);
      await enqueueSpotifyTrack('4wteGC0HtLeZWjDcczc4Pw');
    } catch (e) {
      console.log(e);
      toast.error('something went wrong, please try again');
    }
    setLoading(false);
  }

  if (authUser === null) {
    return (
      <>
        <div className='min-h-screen flex justify-center items-center'>
          <p>fetching user...</p>
        </div>
      </>
    );
  }

  return (
    <>
      <Toaster />
      <div
        className="min-h-screen flex flex-col justify-center items-center px-6"
      >
        <div>
          <div className="md:block h-6" />
          <h1 className="text-5xl tracking-tighter pb-10 font-bold text-center">
                        enter a spotify link
          </h1>
          <div className="md:block h-6" />
          <form
            className="flex w-full sm:w-auto flex-col sm:flex-row mb-10"
            onSubmit={submitForm}
          >
            <input
              className="shadow-sm text-gray-700 rounded-xl px-4 py-3 mb-4 sm:mb-0 sm:min-w-[600px]"
              type="text"
              placeholder="https://open.spotify.com/track/...."
              onChange={(e) => setSpotifyLink(e.target.value)}
            />
            <div className="md:w-4" />
            <div className="flex flex-row">
              <CreditsChip className="md:hidden w-full text-center" />
              <div className="w-4 md:hidden" />
              <button
                className='w-full text-center text-lg rounded-xl bg-blue-600 text-white px-12 py-3 transition duration-300 ease-in-out hover:bg-blue-600'
                disabled={credits === 0}
                type="submit"
              >
                {loading && (
                  <svg
                    className="animate-spin h-5 w-5 text-white"
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                  >
                    <circle
                      className="opacity-25"
                      cx="12"
                      cy="12"
                      r="10"
                      stroke="currentColor"
                      strokeWidth="4"
                    ></circle>
                    <path
                      className="opacity-75"
                      fill="currentColor"
                      d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                    ></path>
                  </svg>
                )}
                {!loading ? 'Generate' : ''}
              </button>
            </div>
          </form>
        </div>
        <div className="flex flex-row justify-center items-center w-screen px-4 md:px-52 py-8">
          <div className="w-full h-px bg-gray-500" />
          <p className="px-6 text-gray-500">or</p>
          <div className="w-full h-px bg-gray-500" />
        </div>
        <div className="flex flex-col md:flex-row gap-4">
          <div>
            <Link
              href="/upload_track"
              className="text-center text-lg rounded-xl bg-gray-600/50 text-white px-12 py-3 transition duration-300 ease-in-out"
            >
                            upload your own track
            </Link>
          </div>
          {/* <div>
                <p>{`let us guide you ;)`}</p>
            </div> */}
          <div>
            <Link
              href="/prompting"
              className="text-center text-lg rounded-xl bg-gray-600/50 text-white px-12 py-3 transition duration-300 ease-in-out hover:bg-blue-600"
            >
                            use your own prompt
            </Link>
          </div>
        </div>
      </div >
    </>
  );
}
