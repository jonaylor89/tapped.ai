"use client";

import { onAuthStateChanged, type User } from "firebase/auth";
import { useRouter } from "next/navigation";
import React, { createContext, type ReactNode, useContext, useEffect, useState } from "react";
import Loading from "@/components/loading";
import type { UserModel } from "@/types/user_model";
import { getCustomClaims } from "@/utils/auth";
import { getUser } from "@/utils/database";
import { auth } from "@/utils/firebase";

export const AuthContext = createContext<{
  authUser: User | null;
  user: UserModel | null;
  claim: string | null;
}>({ authUser: null, user: null, claim: null });

export const useAuth = () => useContext(AuthContext);

interface AuthContextProviderProps {
  children: ReactNode;
}

export function AuthContextProvider({ children }: AuthContextProviderProps): JSX.Element {
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
          router.push("/signup");
          return;
        }

        const claim = claims["stripeRole"] as string | null;
        if (claim === undefined || claim === null) {
          router.push("/signup");
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
      <AuthContext.Provider value={{ authUser, user, claim }}>{loading ? <Loading /> : children}</AuthContext.Provider>
    </>
  );
}
