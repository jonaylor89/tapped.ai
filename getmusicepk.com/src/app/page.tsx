import Link from 'next/link'
import Image from 'next/image';
import Nav from '@/components/Nav';

export default function Home() {
  return (
    <>
      <Nav />
      <main className="h-[95vh] flex flex-col items-center md:items-start justify-center px-4 md:px-24">
        {/* Nav Bar */}
        <h1
          className='uppercase text-center md:text-start text-4xl md:text-9xl font-black w-3/4'
        >
          your {' '}
          <span className="text-transparent bg-clip-text bg-gradient-to-r from-blue-800 to-sky-300">
            electronic press kit
          </span>
        </h1>
        <h2 className='text-lg md:text-xl text-extrathin text-center md:text-start'>
          create an electronic press kit using just your{' '}
          <Link
            href="https://tapped.ai"
            className='underline text-transparent bg-clip-text bg-gradient-to-r from-blue-400 to-sky-300'
          >
            Tapped
          </Link>
          {' '}profile
        </h2>
        <div className='h-8' />
        <Link
          href="/login?returnUrl=/epk_form"
          className='bg-blue-700 text-white font-extrabold px-4 py-2 rounded-full'>
          get started
        </Link>
      </main>
      <section>
        <div className='flex justify-center items-center'>

        <blockquote
          className="twitter-tweet"
          data-theme="dark">
          <p lang="en" dir="ltr">
            i’m excited to announce our new product “epk generator”.<br />where you are able to create 3 music resumes in less than 3 minutes. <br />check it out here: <a href="https://t.co/zuWBPxRbo5">https://t.co/zuWBPxRbo5</a><a href="https://twitter.com/AntlerGlobal?ref_src=twsrc%5Etfw">@AntlerGlobal</a> is coming to an end, so that means we have to go in overdrive for <a href="https://twitter.com/tappedai?ref_src=twsrc%5Etfw">@tappedai</a>. <a href="https://t.co/pVeN9V3HVR">pic.twitter.com/pVeN9V3HVR</a>
            </p>
              &mdash; ilias anwar (@iliasanwar_) <a href="https://twitter.com/iliasanwar_/status/1722448416515506480?ref_src=twsrc%5Etfw">November 9, 2023</a>
            </blockquote>
            <script async src="https://platform.twitter.com/widgets.js" />
        </div>
          </section>
        </>
        );
}
