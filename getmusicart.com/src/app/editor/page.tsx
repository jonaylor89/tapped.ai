'use client';

import Image from 'next/image';
import Link from 'next/link';
import { useSearchParams, useRouter } from 'next/navigation';
import { toBase64 } from '@/utils/base64';
import { shimmer } from '@/utils/shimmer';
import { createUrl } from '@/utils/url';
import { useAuth } from '@/context/AuthProvider';

const editorUri = '/api/og';

export default function Editor() {
  const { authUser } = useAuth();
  const router = useRouter();
  const searchParams = useSearchParams();

  const imageUri = searchParams.get('image_uri');
  const explicitContent = searchParams.get('explicit_content') === 'true' ?
    true :
    false;

  if (authUser === null) {
    return (
      <>
        <div className='min-h-screen flex justify-center items-center'>
          <p>fetching user...</p>
        </div>
      </>
    );
  }

  if (imageUri === undefined || imageUri === null) {
    return (
      <div className="min-h-screen flex justify-center items-center">
        <h1
          className="text-center text-5xl tracking-tighter font-extrabold gray-800"
        >
                    no image url provided
        </h1>
      </div>
    );
  }

  function toggleExplicitContent(e: React.ChangeEvent<HTMLInputElement>) {
    const checked = e.target.checked;
    const newParams = new URLSearchParams(searchParams.toString());

    if (checked) {
      newParams.set('explicit_content', checked.toString());
    } else {
      newParams.delete('explicit_content');
    }

    router.push(createUrl('/editor', newParams));
  }

  const imageLoader = ({ src, width, quality }: {
        src: string;
        width: number;
        quality?: number;
    }) => {
    return `${src
    }?w=${width
    }&q=${quality || 75
    }&image_uri=${encodeURIComponent(imageUri)
    }&explicit_content=${explicitContent
    }`;
  };

  return (
    <>
      <div className="min-h-screen flex flex-col justify-center items-center px-4">
        <div className="flex flex-col justify-center items-center md:w-1/3">
          <div className="rounded-xl shadow-md flex flex-col justify-center items-center rounded-xl">
            <Image
              src={editorUri}
              loader={imageLoader}
              alt="generated image"
              width={512}
              height={512}
              className="rounded-md shadow-md object-cover"
              placeholder={`data:image/svg+xml;base64,${toBase64(shimmer(512, 512))}`}
              priority
            />
          </div>
          <form>
            <div className="inline-flex items-center">
              <input
                id="ripple-on"
                type="checkbox"
                className="before:content[''] peer relative h-5 w-5 cursor-pointer appearance-none rounded-md border border-blue-gray-200 transition-all before:absolute before:top-2/4 before:left-2/4 before:block before:h-12 before:w-12 before:-translate-y-2/4 before:-translate-x-2/4 before:rounded-full before:bg-blue-gray-500 before:opacity-0 before:transition-opacity checked:border-blue-500 checked:bg-blue-500 checked:before:bg-blue-500 hover:before:opacity-10"
                checked={explicitContent}
                onChange={toggleExplicitContent}
              />
              <div className="absolute text-white transition-opacity opacity-0 pointer-events-none top-2/4 left-2/4 -translate-y-2/4 -translate-x-2/4 peer-checked:opacity-100">
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  className="h-3.5 w-3.5"
                  viewBox="0 0 20 20"
                  fill="currentColor"
                  stroke="currentColor"
                  strokeWidth="1"
                >
                  <path
                    fillRule="evenodd"
                    d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
                    clipRule="evenodd"
                  ></path>
                </svg>
              </div>
              <label
                className="mt-px font-light text-gray-300 cursor-pointer select-none"
                htmlFor="ripple-on"
              >
                explicit content warning
              </label>
            </div>
          </form>
          <div className="h-6" />
          <Link
            // eslint-disable-next-line sonarjs/no-nested-template-literals
            href={`/download?image_uri=${encodeURIComponent(`${editorUri
            }?image_uri=${encodeURIComponent(imageUri)
            }&explicit_content=${explicitContent
            }`)
            }`}
            className='w-full text-center text-2xl font-bold px-12 py-2 rounded-xl bg-white/10 text-white/75 hover:scale-105 transform transition-all duration-200 ease-in-out'
          >
                        done
          </Link>
        </div>
      </div>
    </>
  );
}
