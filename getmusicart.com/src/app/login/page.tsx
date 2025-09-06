'use client';

import Image from 'next/image';
import { useRouter, useSearchParams } from 'next/navigation';
import { useAuth } from '@/context/AuthProvider';
import ContinueWithGoogleButton from '@/components/ContinueWithGoogleButton';

export default function Login() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const returnUrl = searchParams.get('return_url') || '/prompting';
  console.log({ returnUrl });

  const { authUser } = useAuth();
  if (authUser) {
    router.push(returnUrl);
    return;
  }

  const onLogin = () => {
    router.push(returnUrl);
  };

  return (
    <div className="flex flex-col justify-center items-center min-h-screen rounded-lg p-16">
      <div className="flex items-center justify-center pb-5">
        <Image
          src="/images/icon_1024.png"
          alt="Tapped_Logo"
          width={124}
          height={124}
        />
      </div>

      <ContinueWithGoogleButton onClick={onLogin} />
    </div>
  );
}
