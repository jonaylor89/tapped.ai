import { getApp, getApps, initializeApp } from "firebase/app";

// Firebase Auth exists only for this MCP OAuth consent page; the rest of the site has no sign-in.
// biome.json rejects `firebase/*` imports anywhere else. All application data is served by the Rust API.
const app = getApps().length
	? getApp()
	: initializeApp({
			apiKey: process.env.NEXT_PUBLIC_FIREBASE_API_KEY || "",
			authDomain: process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN || "",
			projectId: process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID || "",
			messagingSenderId: process.env.NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID || "",
			appId: process.env.NEXT_PUBLIC_FIREBASE_APP_ID || "",
		});
export { app };
