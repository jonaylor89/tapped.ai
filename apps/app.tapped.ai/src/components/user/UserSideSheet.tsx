import { ArrowUpRight, Copy } from "lucide-react";
import Link from "next/link";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useEffect, useState } from "react";
import { LoadingSpinner } from "@/components/LoadingSpinner";
import ProfileHeader from "@/components/profile/ProfileHeader";
import { Button } from "@/components/ui/button";
import { Sheet, SheetContent, SheetDescription, SheetTitle } from "@/components/ui/sheet";
import { useToast } from "@/components/ui/use-toast";
import { usePublicProfile } from "@/hooks/use-public-profile";
import { trackEvent } from "@/utils/tracking";

export default function UserSideSheet() {
	const router = useRouter();
	const searchParams = useSearchParams();
	const pathname = usePathname();
	const { toast } = useToast();
	const username = searchParams.get("username");
	const isOpen = username !== null;

	const { user: selectedUser, loading, failed } = usePublicProfile(username);
	const [initialSearchParams, setInitialSearchParams] = useState<string | null>(null);

	useEffect(() => {
		// Store initial search params when the sheet opens
		if (!initialSearchParams) {
			setInitialSearchParams(searchParams.toString());
		}
	}, [searchParams, initialSearchParams]);

	const onOpenChange = (isOpen: boolean) => {
		if (!isOpen && initialSearchParams) {
			const params = new URLSearchParams(initialSearchParams);

			// Remove the username parameter if it exists
			params.delete("username");

			const newQueryString = params.toString() === "" ? "" : `?${params.toString()}`;
			const newUrl = `${pathname}${newQueryString}`;
			router.push(newUrl);
			setInitialSearchParams(null); // Reset for next open
		}
	};

	return (
		<Sheet open={isOpen} onOpenChange={onOpenChange}>
			<SheetContent className="overflow-y-scroll">
				<SheetTitle className="sr-only">User profile</SheetTitle>
				<SheetDescription className="sr-only">
					Profile, reviews, services and bookings.
				</SheetDescription>
				<div className="flex justify-start bg-background/10">
					<Button
						variant="secondary"
						onClick={() => {
							navigator.clipboard.writeText(`${window.location.origin}/u/${username}`);

							trackEvent("user_profile_link_copied", {
								user_id: selectedUser?.id,
							});

							toast({
								description: "link copied!",
							});
						}}
					>
						<div className="flex flex-row justify-center">
							<p>copy link</p>
							<Copy className="ml-2 h-4 w-4" />
						</div>
					</Button>
					<div className="w-2" />
					<Link href={`/u/${username}`} target="_blank" rel="noreferrer noopener">
						<Button variant="secondary">
							<div className="flex flex-row justify-center">
								<p>open profile</p>
								<ArrowUpRight className="ml-2 h-4 w-4" />
							</div>
						</Button>
					</Link>
				</div>
				<div className="flex justify-center">
					{selectedUser === null ? (
						<div className="flex min-h-screen items-center justify-center">
							{loading ? (
								<LoadingSpinner />
							) : (
								<p>{failed ? "Profile could not be refreshed." : "Profile unavailable."}</p>
							)}
						</div>
					) : (
						<div className="w-full overflow-y-scroll">
							<ProfileHeader key={selectedUser.id} user={selectedUser} full />
						</div>
					)}
				</div>
			</SheetContent>
		</Sheet>
	);
}
