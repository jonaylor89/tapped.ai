"use client";

import { getCoreRowModel, useReactTable } from "@tanstack/react-table";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { DataTable } from "@/components/data_table";
import { getInterestedUsersForOpportunity } from "@/data/database";
import { type UserModel, userAudienceSize } from "@/domain/types/user_model";
import { columns } from "./columns";

export default function ApplicantsTable({ opId }: { opId: string }) {
	const router = useRouter();
	const pathname = usePathname();
	const searchParams = useSearchParams();

	const createQueryString = useCallback(
		(name: string, value: string) => {
			const params = new URLSearchParams(searchParams.toString());
			params.set(name, value);

			return params.toString();
		},
		[searchParams]
	);

	const [applicants, setApplicants] = useState<UserModel[]>([]);
	const table = useReactTable({
		data: applicants,
		columns,
		getCoreRowModel: getCoreRowModel(),
		// onRowSelectionChange: setRowSelection,
	});

	useEffect(() => {
		const fetchApplicants = async () => {
			const apps = await getInterestedUsersForOpportunity(opId);
			const sorted = apps.sort((a, b) => {
				const aAudience = userAudienceSize(a);
				const bAudience = userAudienceSize(b);
				return bAudience - aAudience;
			});
			setApplicants(sorted);
		};
		fetchApplicants();
	}, [opId]);

	return (
		<DataTable
			table={table}
			onRowClick={(row) => {
				router.push(`${pathname}?${createQueryString("username", row.username)}`);
			}}
		/>
	);
}
