"use client";

import { useRouter } from "next/navigation";
import { createContext, type ReactNode, useContext, useEffect, useState } from "react";
import { userCreditsListener } from "@/utils/database";
import { useAuth } from "./AuthProvider";

export const CreditsContext = createContext<{
  credits: number;
}>({ credits: 0 });

export const useCredits = () => useContext(CreditsContext);

interface CreditsContextProviderProps {
  children: ReactNode;
}

export function CreditsContextProvider({ children }: CreditsContextProviderProps): JSX.Element {
  const { authUser } = useAuth();
  const _router = useRouter();
  const [credits, setCredits] = useState(0);

  useEffect(() => {
    if (authUser === null) {
      return;
    }

    const unsubscribe = userCreditsListener(authUser.uid, async (credits) => {
      setCredits(credits);
    });

    return () => unsubscribe();
  }, [authUser]);

  return <CreditsContext.Provider value={{ credits }}>{children}</CreditsContext.Provider>;
}
