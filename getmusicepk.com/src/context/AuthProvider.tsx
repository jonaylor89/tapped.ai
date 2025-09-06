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
import { UserModel } from '@/types/user_model';
import { getUser } from '@/utils/database';
import { getCustomClaims } from '@/utils/auth';
import { useRouter } from 'next/navigation';
import Loading from '@/components/loading';

export const AuthContext = createContext<{
  authUser: User | null;
  user: UserModel | null;
  claim: string | null;
}>({ authUser: null, user: null, claim: null });

export const useAuth = () => useContext(AuthContext);

interface AuthContextProviderProps {
  children: ReactNode;
}

export function AuthContextProvider({
  children,
}: AuthContextProviderProps): JSX.Element {
  const router = useRouter();
  const [authUser, setAuthUser] = useState<User | null>(null);
  const [user, setUser] = useState<UserModel | null>(null);
  const [claim, setClaim] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const unsubscribe = onAuthStateChanged(auth, async (authUser) => {
      if (authUser) {
        const claims = await getCustomClaims();
        if (claims === undefined || claims === null) {
          router.push('/signup');
          return;
        }

        const claim = claims['stripeRole'] as string | null;
        if (claim === undefined || claim === null) {
          router.push('/signup');
          return;
        }

        const currentUser = await getUser(authUser.uid);

        setAuthUser(authUser);
        setUser(currentUser);
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
      <AuthContext.Provider value={{ authUser, user, claim }}>
        {loading ? <Loading /> : children}
      </AuthContext.Provider>
    </>
  );
}