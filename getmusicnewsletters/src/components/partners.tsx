import Image from 'next/image';
import Link from 'next/link';

const Partners = () => {
  return (
    <div className='flex flex-col md:flex-row justify-center items-center gap-8'>
      <Link
        href="https://tapped.ai"
        target="_blank"
        rel="noopener noreferrer"
      >
        <Image
          src='/images/tapped_reverse.png'
          width={75}
          height={75}
          alt='tapped logo'
        />
      </Link>
    </div>
  );
};

export default Partners;
