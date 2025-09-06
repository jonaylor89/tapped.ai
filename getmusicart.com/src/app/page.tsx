
import Nav from '@/components/Nav';
import { shuffle } from '@/utils/shuffle';
import Link from 'next/link';
import Image from 'next/image';

export default function Home() {
  const coverArtExamples: string[] = [
    '512.adventure.png',
    '512.big.png',
    '512.small.png',
    '512.dentist.png',
    '512.justin.png',
    '512.pokemon.png',
    '512.punk.jpeg',
    '512.tcc.png',
    '512.two_blue.png',
    '512.what.png',
    '512.blackandwhite.png',
    '512.drake.png',
    '512.green.png',
  ];
  const shuffledExamples = shuffle(coverArtExamples);

  const firstHalf = shuffledExamples.slice(0, shuffledExamples.length / 2);
  const secondHalf = shuffledExamples.slice(shuffledExamples.length / 2);

  return (
    <>
      <Nav />
      <div className="min-h-[90vh] md:min-h-[70vh] flex flex-col justify-center items-center px-6">
        <h1
          className="md:w-1/2 text-center text-6xl tracking-tighter font-extrabold gray-800"
        >
          create beautiful cover art in minutes.
        </h1>
        <div className="h-6" />
        <h2 className='md:w-1/2 text-center font-thin text-lg text-gray-300'>
          design, edit, and export cover art for your next project.
        </h2>
        <div className="h-6" />
        <div className='w-full md:w-1/2 flex flex-col md:flex-row justify-center'>
          <Link
            href="/login?return_url=/prompting"
            className='w-full text-center text-lg rounded-xl bg-blue-600 text-white px-12 py-3 transition duration-300 ease-in-out hover:bg-blue-600'
          >
            get started
          </Link>
          <div className="h-2 md:w-2" />
          <Link
            href="/login?return_url=/pricing"
            className='w-full md:w-1/2 text-center text-lg rounded-xl bg-white/10 text-white px-12 py-3 transition duration-300 ease-in-out'
          >
            pricing
          </Link>
        </div>
      </div>
      <div>
        <div className="overflow-hidden w-screen">
          <div className="relative flex flex-row">
            <div className="flex flex-row animate-marquee whitespace-nowrap">
              {firstHalf.map((image, i) => (
                <div
                  key={i}
                  className="w-48 h-64 md:w-64 md:h-72 relative flex-shrink-0 m-2 hover:scale-105 transform transition-all duration-200 ease-in-out">
                  <Image
                    src={`/images/marque/${image}`}
                    alt={`cover art example: ${image}`}
                    priority
                    fill
                    style={{ objectFit: 'cover' }}
                    className='rounded-2xl'
                  />
                </div>
              ))}
            </div>
            <div className="absolute flex flex-row animate-marquee2 whitespace-nowrap">
              {firstHalf.map((image, i) => (
                <div
                  key={i}
                  className="w-48 h-64 md:w-64 md:h-72 relative flex-shrink-0 m-2 hover:scale-105 transform transition-all duration-200 ease-in-out">
                  <Image
                    src={`/images/marque/${image}`}
                    alt={`cover art example: ${image}`}
                    priority
                    fill
                    style={{ objectFit: 'cover' }}
                    className='rounded-2xl'
                  />
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
      <div>
        <div className="overflow-hidden w-screen">
          <div className="relative flex flex-row">
            <div className="flex flex-row animate-marquee whitespace-nowrap">
              {secondHalf.map((image, i) => (
                <div
                  key={i}
                  className="w-48 h-64 md:w-64 md:h-72 relative flex-shrink-0 m-2 hover:scale-105 transform transition-all duration-200 ease-in-out">
                  <Image
                    src={`/images/marque/${image}`}
                    alt={`cover art example: ${image}`}
                    priority
                    fill
                    style={{ objectFit: 'cover' }}
                    className='rounded-2xl'
                  />
                </div>
              ))}
            </div>
            <div className="absolute flex flex-row animate-marquee2 whitespace-nowrap">
              {secondHalf.map((image, i) => (
                <div
                  key={i}
                  className="w-48 h-64 md:w-64 md:h-72 relative flex-shrink-0 m-2 hover:scale-105 transform transition-all duration-200 ease-in-out">
                  <Image
                    src={`/images/marque/${image}`}
                    alt={`cover art example: ${image}`}
                    priority
                    fill
                    style={{ objectFit: 'cover' }}
                    className='rounded-2xl'
                  />
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
      <div className='h-12' />
    </>
  );
}
