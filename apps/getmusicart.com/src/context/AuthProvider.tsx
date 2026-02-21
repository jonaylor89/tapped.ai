"use client";

import { onAuthStateChanged, type User } from "firebase/auth";
import { useRouter } from "next/navigation";
import { createContext, type ReactNode, useContext, useEffect, useState } from "react";
import Loading from "@/components/Loading";
import { getCustomClaims } from "@/utils/auth";
import { auth } from "@/utils/firebase";

export const AuthContext = createContext<{
  authUser: User | null;
  claim: string | null;
}>({ authUser: null, claim: null });

export const useAuth = () => useContext(AuthContext);

interface AuthContextProviderProps {
  children: ReactNode;
}

export function AuthContextProvider({ children }: AuthContextProviderProps): JSX.Element {
  const _router = useRouter();
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
  }, []);

  return <AuthContext.Provider value={{ authUser, claim }}>{loading ? <Loading /> : children}</AuthContext.Provider>;
}
