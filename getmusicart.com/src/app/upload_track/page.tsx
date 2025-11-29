"use client";

import { useAuth } from "@/context/AuthProvider";
import { useCredits } from "@/context/CreditsProvider";

export default function UploadTrack() {
  const { authUser } = useAuth();
  const { credits } = useCredits();
  console.log({ credits });

  if (authUser === null) {
    return (
      <div className="min-h-screen flex justify-center items-center">
        <p>fetching user...</p>
      </div>
    );
  }

  return (
    <form>
      <input type="file" />
    </form>
  );
}
