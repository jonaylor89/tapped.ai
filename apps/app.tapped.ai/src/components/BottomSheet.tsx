import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { Sheet as BSheet } from "react-modal-sheet";
import { styled } from "styled-components";
import { usePublicProfile } from "@/hooks/use-public-profile";
import { LoadingSpinner } from "./LoadingSpinner";
import ProfileHeader from "./profile/ProfileHeader";

const UserSheet = styled(BSheet)`
  .react-modal-sheet-container {
    background-color: #010f16ff !important;
  }

  .react-modal-sheet-backdrop {
    background-color: rgba(0, 0, 0, 0.3) !important;
  }

  .react-modal-sheet-drag-indicator {
    background-color: #666 !important;
  }
`;

export default function UserBottomSheet() {
	const router = useRouter();
	const searchParams = useSearchParams();
	const pathname = usePathname();
	const username = searchParams.get("username");
	const isOpen = username !== null;

	const { user: selectedUser, loading, failed } = usePublicProfile(username);
	const onClose = () => {
		const params = new URLSearchParams(searchParams.toString());
		params.delete("username");
		router.push(`${pathname}${params.size ? `?${params}` : ""}`);
	};

	return (
		<UserSheet isOpen={isOpen} onClose={onClose}>
			<BSheet.Container>
				<BSheet.Header />
				<BSheet.Content>
					<BSheet.Scroller>
						{selectedUser ? (
							<ProfileHeader key={selectedUser.id} user={selectedUser} full />
						) : loading ? (
							<LoadingSpinner />
						) : (
							<p>{failed ? "Profile could not be refreshed." : "Profile unavailable."}</p>
						)}
					</BSheet.Scroller>
				</BSheet.Content>
			</BSheet.Container>
			<BSheet.Backdrop />
		</UserSheet>
	);
}
