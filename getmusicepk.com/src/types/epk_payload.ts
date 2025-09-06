import { EpkForm } from "./epk_form";

export type EpkPayload = Omit<EpkForm, "id" | "userId" | "timestamp"> & {
    twitterHandle: string | null;
    tiktokHandle: string | null;
    instagramHandle: string | null;
    tappedRating: string;
  }; 