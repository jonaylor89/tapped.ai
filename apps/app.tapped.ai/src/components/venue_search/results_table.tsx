"use client";

import { getCoreRowModel, useReactTable } from "@tanstack/react-table";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useCallback, useState } from "react";
import { DataTable } from "@/components/data_table";
import { columns } from "@/components/venue_search/columns";
import { useSearch } from "@/context/search";

export default function ResultsTable({
	capacity,
	genres,
	lat,
	lng,
	radius,
}: {
	capacity: number;
	genres: string[];
	lat: number;
	lng: number;
	radius: number;
}) {
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

	const { useSearchData } = useSearch();
	const { data } = useSearchData("", {
		hitsPerPage: 30,
		maxCapacity: capacity,
		venueGenres: genres,
		lat: lat,
		lng: lng,
		radius: radius,
	});
	const [rowSelection, setRowSelection] = useState({});
	const table = useReactTable({
		data: data ?? [],
		columns,
		getCoreRowModel: getCoreRowModel(),
		onRowSelectionChange: setRowSelection,
		state: {
			rowSelection,
		},
	});

	return (
		<div className="container mx-auto overflow-y-scroll py-10">
			<DataTable
				table={table}
				onRowClick={(row) => {
					router.push(`${pathname}?${createQueryString("username", row.username)}`);
				}}
			/>
		</div>
	);
}
