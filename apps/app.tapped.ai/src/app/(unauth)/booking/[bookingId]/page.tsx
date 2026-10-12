import Image from "next/image";
import Link from "next/link";
import { notFound } from "next/navigation";
import { getBookingById, getUserById } from "@/data/database";
import { publicEventUrl } from "@/lib/public-booking";

// Only confirmed public performance history, never private notes, rates or service details.
export default async function BookingPage({ params }: { params: Promise<{ bookingId: string }> }) {
	const { bookingId } = await params;
	const booking = await getBookingById(bookingId);
	if (!booking) notFound();
	const [performer, booker] = await Promise.all([
		booking.requesteeId ? getUserById(booking.requesteeId) : null,
		booking.requesterId ? getUserById(booking.requesterId) : null,
	]);
	const eventUrl = publicEventUrl(booking.eventUrl);
	return (
		<main className="mx-auto grid max-w-4xl gap-10 px-6 py-16 md:grid-cols-[1fr_2fr]">
			<div className="relative aspect-square overflow-hidden rounded-lg bg-muted">
				<Image
					src={booking.flierUrl ?? "/images/default_images/daftpunk.jpg"}
					alt="Performance flier"
					fill
					sizes="(max-width: 768px) 100vw, 320px"
					className="object-cover"
				/>
			</div>
			<article className="border-t-2 border-yellow-500 pt-6">
				<p className="text-sm uppercase tracking-widest text-muted-foreground">
					Performance history · confirmed
				</p>
				<h1 className="my-4 text-4xl font-bold">{booking.name}</h1>
				{booking.startTime && (
					<time dateTime={booking.startTime.toISOString()} className="text-lg">
						{booking.startTime.toLocaleString("en-US", {
							dateStyle: "long",
							timeStyle: "short",
							timeZone: "UTC",
						})}{" "}
						UTC
					</time>
				)}
				<dl className="my-8 grid gap-4 border-y py-6">
					<div>
						<dt className="text-sm text-muted-foreground">Performer</dt>
						<dd>
							{performer ? (
								<Link
									className="underline underline-offset-4"
									href={`/u/${encodeURIComponent(performer.username)}`}
								>
									{performer.artistName || performer.username}
								</Link>
							) : (
								"Profile unavailable"
							)}
						</dd>
					</div>
					<div>
						<dt className="text-sm text-muted-foreground">Booker</dt>
						<dd>
							{booker ? (
								<Link
									className="underline underline-offset-4"
									href={`/u/${encodeURIComponent(booker.username)}`}
								>
									{booker.artistName || booker.username}
								</Link>
							) : (
								"Profile unavailable"
							)}
						</dd>
					</div>
				</dl>
				{eventUrl && (
					<a
						className="underline underline-offset-4"
						href={eventUrl}
						target="_blank"
						rel="noopener noreferrer"
					>
						Event website ↗
					</a>
				)}
			</article>
		</main>
	);
}
