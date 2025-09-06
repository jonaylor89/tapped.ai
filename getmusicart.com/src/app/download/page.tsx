import Image from 'next/image';
import { toBase64 } from '@/utils/base64';
import { shimmer } from '@/utils/shimmer';
import { getUrl } from '@/utils/url';

export default function Download({ searchParams }: {
    searchParams?: { [key: string]: string | undefined };
}) {
  const imageUri = searchParams?.image_uri;

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

  return (
    <>
      <div className="min-h-screen flex flex-col justify-center px-4">
        <div className="rounded-xl shadow-md flex flex-col justify-center items-center rounded-xl">
          <Image
            src={getUrl(imageUri)}
            alt="generated image"
            width={512}
            height={512}
            className="rounded-md shadow-md object-cover"
            placeholder={`data:image/svg+xml;base64,${toBase64(shimmer(512, 512))}`}
            priority
          />
        </div>
        <div className="h-6" />
        <div className="flex flex-col justfy-center gap-4">
          <a
            href={`${imageUri}&width=3000&height=3000`}
            download="ai_art_3000x3000.png"
            target="_blank"
            rel="noreferrer"
            className='text-center text-2xl font-bold px-12 py-2 rounded-xl bg-white/10 text-white/75 hover:scale-105 transform transition-all duration-200 ease-in-out'
          >
                        get as 3000x3000
          </a>
          <a
            href={`${imageUri}&width=1024&height=1024`}
            download="ai_art_1024x1024.png"
            target="_blank"
            rel="noreferrer"
            className='text-center text-2xl font-bold px-12 py-2 rounded-xl bg-white/10 text-white/75 hover:scale-105 transform transition-all duration-200 ease-in-out'
          >
                        get as 1024x1024
          </a>
          <a
            href={`${imageUri}&width=500&height=500`}
            download="ai_art_500x500.png"
            target="_blank"
            rel="noreferrer"
            className='text-center text-2xl font-bold px-12 py-2 rounded-xl bg-white/10 text-white/75 hover:scale-105 transform transition-all duration-200 ease-in-out'
          >
                        get as 500x500
          </a>
          <a
            href={`${imageUri}&width=128&height=128`}
            download="ai_art_128x128.png"
            target="_blank"
            rel="noreferrer"
            className='text-center text-2xl font-bold px-12 py-2 rounded-xl bg-white/10 text-white/75 hover:scale-105 transform transition-all duration-200 ease-in-out'
          >
                        get as 128x128
          </a>
        </div>
      </div>
    </>
  );
}
