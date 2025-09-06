'use client';

import StripePricingTable from '@/components/stripe/PricingTable';
import { useAuth } from '@/context/AuthProvider';
import { logout } from '@/utils/auth';
import Link from 'next/link';
import { useRouter } from 'next/navigation';

export default function SignUp() {
  const { authUser } =useAuth();
  const router = useRouter();
  const onLogout = async () => {
    await logout();
    router.push('/login');
  };

  if (authUser === null) {
    return (
      <div className="min-h-screen flex flex-col justify-center items-center">
        <h1 className="text-5xl tracking-tighter pb-10 font-bold">
                    please login
        </h1>
        <Link
          href="/login?return_url=/prompting"
          className="text-gray-500 px-4 py-2"
        >
                    login
        </Link>
      </div>
    );
  }

  return (
    <>
      <div className="min-h-screen flex flex-col justify-center items-center">
        <StripePricingTable user={authUser} />
        <div className="h-4" />
        <button
          onClick={onLogout}
          className='text-gray-500 px-4 py-2'
        >
                    logout
        </button>
      </div>
    </>
  );
}
