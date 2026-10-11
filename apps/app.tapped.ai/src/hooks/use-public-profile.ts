"use client";

import { useEffect, useState } from "react";
import {
	getCachedUserByUsername,
	getPublicProfileDetails,
	getUserByUsername,
} from "@/data/database";
import type { UserModel } from "@/domain/types/user_model";

// Render the normalized public snapshot immediately on SPA navigation; refresh by ID without
// the username endpoint's edge/process cache. Never keep another selected user's late response.
export function usePublicProfile(username: string | null) {
	const [hydrated, setHydrated] = useState(false);
	const [state, setState] = useState<{
		username: string | null;
		user: UserModel | null;
		loading: boolean;
		failed: boolean;
	}>({ username: null, user: null, loading: false, failed: false });
	useEffect(() => {
		setHydrated(true);
	}, []);
	useEffect(() => {
		let active = true;
		if (!username) {
			setState({ username, user: null, loading: false, failed: false });
			return;
		}
		const snapshot = getCachedUserByUsername(username);
		setState({ username, user: snapshot, loading: true, failed: false });
		const refresh = async () => {
			const user = snapshot ?? (await getUserByUsername(username));
			if (!active) return;
			if (!user) {
				setState({ username, user: null, loading: false, failed: false });
				return;
			}
			setState({ username, user, loading: true, failed: false });
			const details = await getPublicProfileDetails(user.id, true);
			if (active)
				setState({ username, user: details?.user ?? null, loading: false, failed: false });
		};
		void refresh().catch(() => {
			if (active) setState((previous) => ({ ...previous, loading: false, failed: true }));
		});
		return () => {
			active = false;
		};
	}, [username]);
	const matching = state.username === username;
	return {
		user: hydrated
			? matching
				? state.user
				: username
					? getCachedUserByUsername(username)
					: null
			: null,
		loading: username !== null && (!matching || state.loading),
		failed: matching && state.failed,
	};
}
