"use client";

import Image from "next/image";
import Link from "next/link";
import { useEffect, useState } from "react";
import { getServiceById, getUserById } from "@/data/database";
import { type Booking, bookingImage } from "@/domain/types/booking";
import type { Option } from "@/domain/types/option";
import type { Service } from "@/domain/types/service";
import type { UserModel } from "@/domain/types/user_model";

export default function BookingCard({ booking, user }: { booking: Booking; user: UserModel }) {
	const [_booker, setBooker] = useState<Option<UserModel>>(null);
	const [_performer, setPerformer] = useState<Option<UserModel>>(null);
	const [_service, setService] = useState<Option<Service>>(null); // TODO: [service, setService

	useEffect(() => {
		const fetchUsers = async () => {
			if (booking === null) {
				return;
			}

			const requesterId = booking.requesterId;
			const booker = await (() => {
				if (requesterId === undefined || requesterId === null) {
					return null;
				}

				return getUserById(requesterId);
			})();

			const performer = await getUserById(booking.requesteeId);
			setBooker(booker);
			setPerformer(performer);
		};
		fetchUsers();
	}, [booking]);

	useEffect(() => {
		const fetchService = async () => {
			if (booking === null) {
				return;
			}

			if (booking.serviceId === undefined || booking.serviceId === null) {
				return;
			}

			const bookingService = await getServiceById({
				userId: user.id,
				serviceId: booking.serviceId,
			});

			setService(bookingService);
		};
		fetchService();
	}, [booking, user]);

	// const isRequester = user.id == booker?.id;

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
