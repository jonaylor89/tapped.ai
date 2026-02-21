import Link from "next/link";
import { FaSpotify } from "react-icons/fa";
import { Button } from "@/components/ui/button";

export default function InstagramButton({ spotifyId }: { spotifyId: string }) {
	return (
		<Link href={spotifyId} target="_blank" rel="noreferrer">
			<Button variant="outline" size="icon">
				<FaSpotify className="h-6 w-6" />
			</Button>
		</Link>
	);
}
