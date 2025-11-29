"use client";

import { useState } from "react";
import ProfileHeader from "@/components/profile/ProfileHeader";
import SearchBar from "@/components/search/SearchBar";
import UnauthHeader from "@/components/unauth_header";
import type { UserModel } from "@/domain/types/user_model";

type Props = {
	initialPerformerOne: UserModel | null;
	initialPerformerTwo: UserModel | null;
};

export default function CompareClient({ initialPerformerOne, initialPerformerTwo }: Props) {
	const [performerOne, setPerformerOne] = useState<UserModel | null>(initialPerformerOne);
	const [performerTwo, setPerformerTwo] = useState<UserModel | null>(initialPerformerTwo);

	return (
		<>
			<UnauthHeader />
			<div className="mt-24 flex flex-col items-center">
				<div className="flex flex-row items-center justify-center gap-4">
					<SearchBar
						openDialog={false}
						onSelect={(user) => {
							setPerformerOne(user);
						}}
					/>
					<h3>vs</h3>
					<SearchBar
						openDialog={false}
						onSelect={(user) => {
							setPerformerTwo(user);
						}}
					/>
				</div>
				<div className="flex flex-row items-start justify-center gap-4">
					<div>
						{performerOne && (
							<div>
								<ProfileHeader user={performerOne} />
							</div>
						)}
					</div>
					<div>
						{performerTwo && (
							<div>
								<ProfileHeader user={performerTwo} />
							</div>
						)}
					</div>
				</div>
			</div>
		</>
	);
}
