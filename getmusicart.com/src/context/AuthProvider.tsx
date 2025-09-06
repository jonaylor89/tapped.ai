'use client';

import React, {
  ReactNode,
  createContext,
  useContext,
  useEffect,
  useState,
} from 'react';
import { auth } from '@/utils/firebase';
import { User, onAuthStateChanged } from 'firebase/auth';
import { getCustomClaims } from '@/utils/auth';
import { useRouter } from 'next/navigation';
import Loading from '@/components/Loading';

export const AuthContext = createContext<{
  authUser: User | null;
  claim: string | null;
}>({ authUser: null, claim: null });

export const useAuth = () => useContext(AuthContext);

interface AuthContextProviderProps {
  children: ReactNode;
}

export function AuthContextProvider({
  children,
}: AuthContextProviderProps): JSX.Element {
  const router = useRouter();
  const [authUser, setAuthUser] = useState<User | null>(null);
  const [claim, setClaim] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const unsubscribe = onAuthStateChanged(auth, async (authUser) => {
      if (authUser) {
        const claims = await getCustomClaims();
        const claim = (claims?.stripeRole ?? null) as string | null;

        setAuthUser(authUser);
        setClaim(claim);
      } else {
        setAuthUser(null);
      }
      setLoading(false);
    });

    return () => unsubscribe();
  }, [router]);

  return (
    <>
      <AuthContext.Provider value={{ authUser, claim }}>
        {loading ? <Loading /> : children}
      </AuthContext.Provider>
    </>
  );
}
