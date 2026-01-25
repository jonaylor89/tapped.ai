import Link from "next/link";
import { Button } from "../ui/button";

export default function BuyPremium() {
	return (
		<div className="flex w-full rounded-xl bg-blue-500 p-8">
			<div className="flex-1">
				<h3 className="font-bold text-xl">tapped premium</h3>
				<p>get more shows with the best tools for live music</p>
			</div>
			<Link href="/premium">
				<Button>upgrade</Button>
			</Link>
		</div>
	);
}
