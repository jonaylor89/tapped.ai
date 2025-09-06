import Link from 'next/link';
import { useCredits } from '@/context/CreditsProvider';

export default function CreditsChip({ className }: {
    className?: string;
}) {
  const { credits } = useCredits();

  if (credits === 0) {
    return (
      <>
        <Link
          href="/pricing"
          className="rounded-xl p-3 bg-red-500/10 text-red-500"
        >
                    click to get credits
        </Link>
      </>
    );
  }

  return (
    <>
      <Link
        href="/pricing"
        className={`rounded-xl p-3 bg-blue-500/10 text-blue-500 ${className}`}
      >
        {credits} credits
      </Link>
    </>
  );
}
