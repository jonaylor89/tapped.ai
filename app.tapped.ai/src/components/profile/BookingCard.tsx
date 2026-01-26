import Image from "next/image";
import Link from "next/link";
import { type Booking, bookingImage } from "@/domain/types/booking";
import type { UserModel } from "@/domain/types/user_model";

export default function BookingCard({ booking, user }: { booking: Booking; user: UserModel }) {
	const bookerImageSrc = bookingImage(booking, user);
	const startTimeStr = booking.startTime.toDateString();

	return (
		<Link href={`/booking/${booking.id}`} className="group">
			<div className="relative h-[156px] w-[156px] overflow-hidden rounded-lg">
				<Image
					src={bookerImageSrc}
					alt={"booking image"}
					className="aspect-square rounded-lg transition-all duration-150 ease-in-out group-hover:scale-105"
					objectFit="cover"
					fill
				/>
			</div>
			<div className="w-6" />
			<p className="line-clamp-2 text-ellipsis font-bold">{booking.name ?? "live performance"}</p>
			<div className="w-3" />
			<div>
				<p className="font-thin text-gray-300 text-xs">{startTimeStr}</p>
			</div>
		</Link>
	);
}
