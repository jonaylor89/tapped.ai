import { Unsubscribe } from 'firebase/auth';
import { collection, doc, onSnapshot, increment, updateDoc } from 'firebase/firestore';
import { db } from './firebase';

const creditsRef = collection(db, 'credits');

export async function decrementUserCredits(userId: string): Promise<void> {
  const docRef = doc(creditsRef, userId);

  await updateDoc(docRef, {
    coverArtCredits: increment(-1),
  });
}

export function userCreditsListener(
  userId: string,
  callback: (credits: number) => void,
): Unsubscribe {
  const docRef = doc(creditsRef, userId);

  return onSnapshot(docRef, (docSnap) => {
    const docData = docSnap.data() ?? null;
    const creditCount = docData?.coverArtCredits ?? 0;
    callback(creditCount);
  });
}
