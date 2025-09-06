'use client';

import Image from 'next/image';
import { useRouter } from 'next/navigation';

export default function SelectableImage({ prompt, imageUri }: {
    prompt?: string;
    imageUri: string;
}) {
  const router = useRouter();

  const selectImage = () => {
    router.push(`/editor?image_uri=${imageUri}&explicit_content=true`);
  };

  return (
    <div
      className="relative sm:w-[400px] h-[400px]"
    >
      <Image
        alt={`representation of: ${prompt ?? 'the prompt'}`}
        className={'rounded-md shadow-md h-full object-cover'}
        onClick={selectImage}
        src={imageUri}
        width={400}
        height={400}
        priority
      />
    </div>
  );
}
