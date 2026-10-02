import { tappedApiUrl } from "@/data/tapped_api";
import type { UserModel } from "@/domain/types/user_model";
import CompareClient from "./CompareClient";

const defaultOneUsername = "noah_kahan";
const defaultTwoUsername = "bad_bunny";

async function getUserByUsername(username: string): Promise<UserModel | null> {
	try {
		const res = await fetch(
			`${tappedApiUrl}/app/v1/users/username/${encodeURIComponent(username)}`,
			{
				next: { revalidate: 3600 },
			}
		);
		if (!res.ok) {
			return null;
		}
		return res.json();
	} catch {
		return null;
	}
}

export default async function Page() {
	const [performerOne, performerTwo] = await Promise.all([
		getUserByUsername(defaultOneUsername),
		getUserByUsername(defaultTwoUsername),
	]);

	return <CompareClient initialPerformerOne={performerOne} initialPerformerTwo={performerTwo} />;
}
