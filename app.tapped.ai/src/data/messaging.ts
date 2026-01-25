import { httpsCallable } from "firebase/functions";
import { functions } from "@/utils/firebase";

export async function getStreamToken(userId: string): Promise<string> {
	console.debug("getting stream token");
	const callable = httpsCallable(functions, "ext-auth-chat-getStreamUserToken");
	const res = await callable({ userId });
	return res.data as string;
}
