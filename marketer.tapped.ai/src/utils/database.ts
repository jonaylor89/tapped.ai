
import type { MarketingForm } from '@/types/marketing_form';
import type { MarketingPlan } from '@/types/marketing_plan';

import { doc, collection, setDoc, onSnapshot } from '@firebase/firestore';
import { db } from '@/utils/firebase';
import { Timestamp, getDoc, getDocs, limit, query, where } from 'firebase/firestore';
import { AccessCode } from '@/types/access_code';

const GUEST_PLANS_COLLECTION = 'guestMarketingPlans';
const FORMS_COLLECTION = 'marketingForms';

export function marketingPlanListener(
  clientReferenceId: string,
  callback: (data: MarketingPlan) => void,
) {
  console.log({ clientReferenceId });
  const docRef = doc(db, GUEST_PLANS_COLLECTION, clientReferenceId);
  onSnapshot(docRef, (doc) => {
    const marketingPlan = doc.data() as MarketingPlan;
    console.log({ marketingPlan });
    callback(marketingPlan);
  });
}

export async function createEmptyMarketingPlan({ clientReferenceId }: {
    clientReferenceId: string;
}) {
  console.log({ clientReferenceId });
  const marketingPlan: MarketingPlan = {
    clientReferenceId,
    status: 'initial',
  };

  const docRef = doc(db, GUEST_PLANS_COLLECTION, clientReferenceId);
  await setDoc(docRef, marketingPlan);
}

export async function saveForm(form: MarketingForm) {
  console.log({ form });
  try {
    const collectionRef = collection(db, FORMS_COLLECTION);
    const docRef = doc(collectionRef, form.id);
    await setDoc(docRef, {
      ...form,
      timestamp: Timestamp.now(),
    });
  } catch (e) {
    console.error(e);
    throw e;
  }
}

export async function getAccessCode(code: string): Promise<AccessCode | null> {
  const accessCodeCollection = collection(db, 'accessCodes');
  const queryRef = query(accessCodeCollection, where('code', '==', code), limit(1));
  const querySnapshot = await getDocs(queryRef);

  if (querySnapshot.empty) {
    return null;
  }

  const dataStuff = querySnapshot.docs[0].data();
  return {
    code: dataStuff.code || '',
    used: dataStuff.used || false,
    permacode: dataStuff.permacode || false,
  };
}


export async function useAccessCode({ code, clientReferenceId }: {
  code: string;
  clientReferenceId: string;
}): Promise<void> {
  const accessCodeCollection = collection(db, 'accessCodes');
  const queryRef = query(accessCodeCollection, where('code', '==', code), limit(1));
  const querySnapshot = await getDocs(queryRef);

  if (querySnapshot.empty) {
    throw new Error('Access code not found');
  }

  const docRef = querySnapshot.docs[0].ref;
  await setDoc(docRef, {
    used: true,
    clientReferenceId,
    usedAt: Timestamp.now(),
  }, {
    merge: true,
  });
}
