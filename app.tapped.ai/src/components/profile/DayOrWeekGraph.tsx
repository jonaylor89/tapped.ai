"use client";

import dynamic from "next/dynamic";
import { Card } from "../ui/card";

const Chart = dynamic(
	() =>
		import("chart.js/auto").then((mod) => {
			mod.default.register(mod.BarElement);
			return import("react-chartjs-2").then((chartjs) => chartjs.Bar);
		}),
	{
		ssr: false,
		loading: () => <div className="h-[200px] w-full animate-pulse bg-muted rounded-md" />,
	}
);

export default function DayOfWeekGraph({
	dayOfWeekData,
	label = "when are shows?",
}: {
	dayOfWeekData: number[];
	label?: string;
}) {
	if (dayOfWeekData.length !== 7) {
		return null;
	}

	if (dayOfWeekData.every((x) => x === 0)) {
		return null;
	}

	const data = {
		labels: ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"],
		datasets: [
			{
				label,
				data: dayOfWeekData,
				backgroundColor: [
					"rgba(255, 99, 132, 0.2)",
					"rgba(255, 159, 64, 0.2)",
					"rgba(255, 205, 86, 0.2)",
					"rgba(75, 192, 192, 0.2)",
					"rgba(54, 162, 235, 0.2)",
					"rgba(153, 102, 255, 0.2)",
					"rgba(201, 203, 207, 0.2)",
				],
				borderColor: [
					"rgb(255, 99, 132)",
					"rgb(255, 159, 64)",
					"rgb(255, 205, 86)",
					"rgb(75, 192, 192)",
					"rgb(54, 162, 235)",
					"rgb(153, 102, 255)",
					"rgb(201, 203, 207)",
				],
				borderWidth: 1,
			},
		],
	};

	return (
		<Card>
			<Chart data={data} options={{}} height={200} width={400} />
		</Card>
	);
}
