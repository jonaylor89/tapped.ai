'use client';

import { useCredits } from '@/context/CreditsProvider';
import { useAuth } from '@/context/AuthProvider';

export default function UploadTrack() {
  const { authUser } = useAuth();
  const { credits } = useCredits();
  console.log({ credits });

  if (authUser === null) {
    return (
      <>
        <div className='min-h-screen flex justify-center items-center'>
          <p>fetching user...</p>
        </div>
      </>
    );
  }

  return (
    <>
      <form>
        <input type="file" />
      </form>
    </>
  );
}
