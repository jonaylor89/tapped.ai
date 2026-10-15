"use client";

import {
	type Auth,
	browserPopupRedirectResolver,
	connectAuthEmulator,
	GoogleAuthProvider,
	getAuth,
	initializeAuth,
	inMemoryPersistence,
	OAuthProvider,
	signInWithEmailAndPassword,
	signInWithPopup,
	signOut,
	type User,
} from "firebase/auth";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { tappedApiUrl } from "@/data/tapped_api";
import { app } from "./firebase";

// Local stack only (platform/local): sign in against the Firebase Auth emulator.
const emulatorHost = process.env.NEXT_PUBLIC_FIREBASE_AUTH_EMULATOR_HOST;

// In-memory persistence: the Firebase session is only used to approve the request; the browser
// keeps nothing once the page closes.
function auth(): Auth {
	try {
		const created = initializeAuth(app, {
			persistence: inMemoryPersistence,
			popupRedirectResolver: browserPopupRedirectResolver,
		});
		if (emulatorHost)
			connectAuthEmulator(created, `http://${emulatorHost}`, { disableWarnings: true });
		return created;
	} catch {
		return getAuth(app);
	}
}

function message(error: unknown): string {
	const code = (error as { code?: string })?.code ?? "";
	if (code === "auth/popup-closed-by-user" || code === "auth/cancelled-popup-request") return "";
	if (["auth/invalid-credential", "auth/wrong-password", "auth/user-not-found"].includes(code)) {
		return "Incorrect email or password.";
	}
	if (code === "auth/too-many-requests") return "Too many attempts. Try again later.";
	return "Sign-in failed. Try again.";
}

export default function AuthorizeClient({
	clientName,
	redirectHost,
	request,
}: {
	clientName: string;
	redirectHost: string;
	request: string;
}) {
	const [user, setUser] = useState<User | null>(null);
	const [email, setEmail] = useState("");
	const [password, setPassword] = useState("");
	const [busy, setBusy] = useState(false);
	const [error, setError] = useState("");

	async function run(action: () => Promise<void>) {
		setBusy(true);
		setError("");
		try {
			await action();
		} catch (e) {
			setError(message(e));
		} finally {
			setBusy(false);
		}
	}

	const popup = (provider: GoogleAuthProvider | OAuthProvider) =>
		run(async () => setUser((await signInWithPopup(auth(), provider)).user));

	// The API answers both with where to send the browser: the client, with a code or an error.
	const finish = (action: "approve" | "deny") =>
		run(async () => {
			const headers: HeadersInit =
				action === "approve" && user ? { Authorization: `Bearer ${await user.getIdToken()}` } : {};
			const response = await fetch(
				`${tappedApiUrl}/oauth/authorization-requests/${encodeURIComponent(request)}/${action}`,
				{ method: "POST", headers }
			);
			const body = (await response.json().catch(() => ({}))) as {
				redirectTo?: string;
				error?: string;
			};
			if (!response.ok || !body.redirectTo) {
				setError(
					body.error ?? "Could not complete the connection. Start again from your MCP client."
				);
				return;
			}
			await signOut(auth());
			window.location.assign(body.redirectTo);
		});

	if (user) {
		return (
			<div className="space-y-4">
				<h1 className="font-semibold text-xl">Allow {clientName} to access your Tapped account?</h1>
				<p className="text-muted-foreground text-sm">
					Signed in as{" "}
					<span className="font-medium text-foreground">
						{user.email ?? user.displayName ?? user.uid}
					</span>
					.
				</p>
				<p className="text-sm">
					{clientName} will be able to read your bookings and opportunities, and search venues,
					performers and opportunities as you. It can't change anything in your account.
				</p>
				<p className="text-muted-foreground text-xs">
					You'll be sent back to <span className="font-mono">{redirectHost}</span>. Only continue if
					you started this from {clientName}. Remove the connector there to disconnect.
				</p>
				{error && <p className="text-destructive text-sm">{error}</p>}
				<div className="flex gap-2">
					<Button className="flex-1" onClick={() => finish("approve")} disabled={busy}>
						Allow
					</Button>
					<Button
						className="flex-1"
						variant="outline"
						disabled={busy}
						onClick={() => finish("deny")}
					>
						Cancel
					</Button>
				</div>
			</div>
		);
	}

	return (
		<div className="space-y-4">
			<h1 className="font-semibold text-xl">Sign in to Tapped</h1>
			<p className="text-muted-foreground text-sm">
				{clientName} wants to connect to your Tapped account. Sign in with the same method you use
				in the app.
			</p>
			<div className="space-y-2">
				<Button
					className="w-full"
					variant="outline"
					disabled={busy}
					onClick={() => popup(new GoogleAuthProvider())}
				>
					Continue with Google
				</Button>
				<Button
					className="w-full"
					variant="outline"
					disabled={busy}
					onClick={() => {
						const apple = new OAuthProvider("apple.com");
						apple.addScope("email");
						popup(apple);
					}}
				>
					Continue with Apple
				</Button>
			</div>
			<form
				className="space-y-2"
				onSubmit={(event) => {
					event.preventDefault();
					run(async () =>
						setUser((await signInWithEmailAndPassword(auth(), email, password)).user)
					);
				}}
			>
				<Input
					type="email"
					autoComplete="email"
					placeholder="Email"
					value={email}
					onChange={(e) => setEmail(e.target.value)}
					required
				/>
				<Input
					type="password"
					autoComplete="current-password"
					placeholder="Password"
					value={password}
					onChange={(e) => setPassword(e.target.value)}
					required
				/>
				<Button className="w-full" type="submit" disabled={busy}>
					Sign in with email
				</Button>
			</form>
			{error && <p className="text-destructive text-sm">{error}</p>}
			<p className="text-muted-foreground text-xs">
				No account? Create one in the Tapped app first.
			</p>
		</div>
	);
}
