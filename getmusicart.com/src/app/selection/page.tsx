import Link from 'next/link';
import SelectableImage from '@/components/SelectableImage';

export default function Selection({
  searchParams,
}: {
    params: { slug: string };
    searchParams?: { [key: string]: string | undefined };
}) {
  const imageUris = searchParams?.image_uris;

  console.debug({ imageUris });

  if (imageUris === undefined || imageUris === null) {
    return (
      <div className="min-h-screen flex justify-center items-center">
        <h1
          className="text-center text-5xl tracking-tighter font-extrabold gray-800"
        >
                    no image urls provided
        </h1>
      </div>
    );
  }

  const selectionImageUris = imageUris.split(',');

  return (
    <>
      <div className="min-h-screen p-4 md:p-12 flex flex-col items-center">
        <h1 className="text-5xl tracking-tighter pb-10 font-bold">
                    pick your favorite
        </h1>
        <div className="w-full md:w-auto flex justify-center">
          <Link
            href="/prompting"
            className="w-full text-center text-2xl bg-blue-500/10 text-blue-500 hover:text-blue-700 py-4 px-16 rounded-xl"
          >
                        try again
          </Link>
        </div>
        <div className="h-6" />
        <div className="grid md:grid-cols-2 gap-4">
          {
            selectionImageUris.map((imageUri, index) => (
              <SelectableImage
                key={index}
                imageUri={imageUri} />
            ))
          }
        </div>
      </div>
    </>
  );
}
