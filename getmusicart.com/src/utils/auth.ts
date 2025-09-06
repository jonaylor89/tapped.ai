import {
  signInWithEmailAndPassword,
  createUserWithEmailAndPassword,
  GoogleAuthProvider,
  signInWithPopup,
} from 'firebase/auth';
import { auth } from '@/utils/firebase';

export type Credentials = { email: string; password: string };

export type LoginResult = { uid: string };

export type SignupResult = { uid: string };

export async function loginWithCredentials({ email, password }: Credentials) {
  console.debug('loginWithCredentials', { email });
  const loginResult = await signInWithEmailAndPassword(
    auth,
    email,
    password,
  );
  return { uid: loginResult.user.uid };
}

export async function signupWithCredentials({ email, password }: Credentials) {
  console.debug('signup');
  const loginResult = await createUserWithEmailAndPassword(
    auth,
    email,
    password,
  );
  return { uid: loginResult.user.uid };
}

export async function loginWithGoogle() {
  console.debug('loginWithGoogle');
  const provider = new GoogleAuthProvider();
  const loginResult = await signInWithPopup(auth, provider);

  return { uid: loginResult.user.uid };
}

export async function logout() {
  console.debug('logout');
  await auth.signOut();
}

export async function getCustomClaims() {
  console.log({ currentUser: auth.currentUser });
  const token = await auth.currentUser?.getIdToken(true);
  console.debug({ token });
  const decodedToken = await auth.currentUser?.getIdTokenResult();
  console.debug({ claims: decodedToken?.claims });
  return decodedToken?.claims;
}
