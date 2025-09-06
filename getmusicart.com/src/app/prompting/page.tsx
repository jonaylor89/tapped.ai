'use client';

import CreditsChip from '@/components/CreditsChip';
import ProcessingAnimation from '@/components/ProcessingAnimation';
import { useAuth } from '@/context/AuthProvider';
import { useCredits } from '@/context/CreditsProvider';
import { decrementUserCredits } from '@/utils/database';
import { sleep } from '@/utils/sleep';
import { createUrl } from '@/utils/url';
import Image from 'next/image';
import { useRouter, useSearchParams } from 'next/navigation';
import { useEffect, useState } from 'react';
import { toast, Toaster } from 'react-hot-toast';

const MAX_REPLIES = 100;
const POLL_INVERVAL = 2 * 1000; // 2 seconds

export default function Prompting() {
  const { authUser } = useAuth();
  const { credits } = useCredits();
  const router = useRouter();
  const searchParams = useSearchParams();

  const [prompt, setPrompt] = useState('');
  const [loading, setLoading] = useState(false);
  const [processing, setProcessing] = useState(false);

  const inferenceId = searchParams.get('inference_id') ?? null;
  const modelId = searchParams.get('model_id') ?? null;

  useEffect(() => {
    const startPolling = async () => {
      if (inferenceId === null || modelId === null) {
        return;
      }

      setProcessing(true);
      await pollInference({
        inferenceId,
        modelId,
      });
      setProcessing(false);
    };
    startPolling();
  }, [inferenceId, modelId]);

  const redirectWithInference = ({ id, modelId }: {
    id: string;
    modelId: string;
  }) => {
    const newParams = new URLSearchParams(searchParams.toString());
    newParams.set('inference_id', id);
    newParams.set('model_id', modelId);
    router.push(createUrl('/prompting', newParams));
  };

  // const fetchMessageId = async (messageId: string) => {
  //   const res = await fetch(`/api/poll_redis?id=${messageId}`);
  //   if (res.status === 500) {
  //     toast.error("Something went wrong, please try again");
  //     console.log({ text: await res.text() });
  //     return true;
  //   }

  //   if (res.status !== 200) {
  //     console.log({ status: res.status })
  //     return false;
  //   }

  //   const json = await res.json();
  //   if (json.status === "pending") {
  //     return false;
  //   }

  //   console.log({ dalleJson: json });
  //   const { payload } = json as {
  //     payload: {
  //       data: { b64_json: string }[]
  //     }
  //   };
  //   console.log({ itemsCount: payload.data.length });

  //   // setImage(payload.data[0].b64_json);
  //   // setCanShowImage(true);
  //   return true;
  // }

  // const pollMessageId = async (messageId: string) => {
  //   for (let i = 0; i < MAX_REPLIES; i++) {
  //     const success = await fetchMessageId(messageId);
  //     if (success) {
  //       break;
  //     }
  //     console.log(`pending - ${i}`);
  //     await sleep(POLL_INVERVAL);
  //   }
  // };

  const pollInference = async ({ inferenceId, modelId }: {
    inferenceId: string;
    modelId: string;
  }) => {
    for (let i = 0; i < MAX_REPLIES; i++) {
      const res = await fetch(`/api/poll_inference?inferenceId=${inferenceId}&modelId=${modelId}`);
      if (res.status === 500) {
        toast.error('Something went wrong, please try again');
        console.log({ text: await res.text() });
        return true;
      }

      const json = await res.json();
      const status = json.status;
      console.log({ status, retry: i });

      if (json.status === 'finished') {
        const { images } = json;
        const imageUris = images.map((image: { uri: string }) => image.uri);
        router.push(
          `/selection?image_uris=${imageUris.join(',')}`
        );
        return;
      }
      await sleep(POLL_INVERVAL);
    }
  };

  async function submitForm(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();

    if (authUser === null) {
      toast.error('please login first');
      return;
    }

    if (prompt === '') {
      toast.error('please enter a prompt');
      return;
    }

    try {
      setLoading(true);
      toast('generating your image...', { position: 'top-center' });
      // const response = await fetch(`/api/enqueue_dalle?prompt=${prompt}`);
      // console.log({ status: response.status });
      // const json = await response.json();
      // console.log({ json });
      // const { id } = json;

      const res = await fetch(`/api/generate_image?prompt=${prompt}`);
      const json2 = await res.json();
      const { id, modelId } = json2;

      console.log({ id, modelId });

      if (id === undefined) {
        toast.error('something went wrong, please try again');
        return;
      }

      await decrementUserCredits(authUser.uid);

      // await pollMessageId(id);
      redirectWithInference({ id, modelId });
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

  if (processing) {
    return (
      <ProcessingAnimation />
    );
  }

  return (
    <>
      <div className="min-h-screen px-4">
        <Toaster />
        <div className="min-h-screen flex flex-col items-center justify-end md:justify-center">
          <div className="md:hidden">
            <Image
              src="/images/molecule.png"
              alt="molecule cover art"
              width={400}
              height={400}
              className="rounded-xl shadow-md h-full object-cover"
              priority
            />
          </div>
          <div className="md:block h-6" />
          <h1 className="text-5xl tracking-tighter pb-10 font-bold text-center">
            describe your cover art
          </h1>
          <div className="md:block h-6" />
          <form
            className="flex w-full sm:w-auto flex-col sm:flex-row mb-10"
            onSubmit={submitForm}
          >
            <input
              className="shadow-sm text-gray-700 rounded-xl px-4 py-3 mb-4 sm:mb-0 sm:min-w-[600px]"
              type="text"
              placeholder="type here..."
              onChange={(e) => setPrompt(e.target.value)}
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
          <CreditsChip
            className="hidden md:block text-center"
          />
        </div>
        <div className="md:block h-6" />
      </div>
    </>
  );
}
