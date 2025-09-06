'use client';

import React, {
  ReactNode,
  createContext,
  useContext,
  useEffect,
  useState,
} from 'react';
import { userCreditsListener } from '@/utils/database';
import { useRouter } from 'next/navigation';
import { useAuth } from './AuthProvider';

export const CreditsContext = createContext<{
    credits: number;
}>({ credits: 0 });

export const useCredits = () => useContext(CreditsContext);

interface CreditsContextProviderProps {
    children: ReactNode;
}

export function CreditsContextProvider({
  children,
}: CreditsContextProviderProps): JSX.Element {
  const { authUser } =useAuth();
  const router = useRouter();
  const [credits, setCredits] = useState(0);

  useEffect(() => {
    if (authUser === null) {
      return;
    }

    const unsubscribe = userCreditsListener(authUser.uid, async (credits) => {
      setCredits(credits);
    });

    return () => unsubscribe();
  }, [router, authUser]);

  return (
    <>
      <CreditsContext.Provider value={{ credits }}>
        {children}
      </CreditsContext.Provider>
    </>
  );
}
