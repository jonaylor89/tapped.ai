/* eslint-disable import/no-unresolved */

import { FieldValue } from "firebase-admin/firestore";
import * as functions from "firebase-functions";

import { creditsRef } from "./firebase";

const _giveUserCoverArtCredits = async (userId: string, amount: number) => {
  await creditsRef.doc(userId).set(
    {
      coverArtCredits: FieldValue.increment(amount),
    },
    { merge: true },
  );
};

export const giveUserCoverArtCreditsOnCreate = functions.auth.user().onCreate(async (user) => {
  await _giveUserCoverArtCredits(user.uid, 15);
});
