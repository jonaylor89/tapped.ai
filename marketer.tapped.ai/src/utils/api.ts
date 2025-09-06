
import { httpsCallable } from 'firebase/functions';
import { functions } from '@/utils/firebase';

export async function checkoutSessionToClientReferenceId(checkoutSessionId: string) {
  try {
    const func = httpsCallable<{
            checkoutSessionId: string,
        }, {
            clientReferenceId: string,
        }>(functions, 'checkoutSessionToClientReferenceId');
    const res = await func({
      checkoutSessionId,
    });

    return res.data.clientReferenceId;
  } catch (e) {
    console.error(e);
    throw e;
  }
}
