import { BarChart3, CalendarDays, Map as MapIcon } from "lucide-react";
import Link from "next/link";
import { AppStoreButton, GooglePlayButton } from "@/components/appstorebuttons";
import { Button } from "@/components/ui/button";
import { APPLE_URL, GOOGLE_URL } from "@/utils/app_download";

export default function AboutPage() {
	return (
		<div className="min-h-screen bg-gradient-to-b from-background to-muted/20">
			{/* Hero Section */}

			<section className="relative px-6 pt-32 pb-20 md:pt-40 md:pb-32 lg:px-8">
				<div className="mx-auto max-w-4xl text-center">
					<h1 className="bg-gradient-to-r from-blue-600 to-cyan-500 bg-clip-text pb-2 font-extrabold text-4xl text-transparent tracking-tight sm:text-6xl">
						The Live Music Industry,
						<br /> Reimagined.
					</h1>

					<p className="mt-6 text-lg text-muted-foreground leading-8 md:text-xl">
						Discover venues, book gigs, and manage your tour—all from your pocket. Tapped is the
						only platform you need to take your music career to the next stage.
					</p>

					<div className="mt-10 flex flex-col items-center justify-center gap-4 sm:flex-row">
						<GooglePlayButton url={GOOGLE_URL} theme={"dark"} />

						<AppStoreButton url={APPLE_URL} theme={"dark"} />
					</div>
				</div>
			</section>

			{/* Video Section */}

			<section className="px-6 pb-24 lg:px-8">
				<div className="mx-auto max-w-5xl">
					<div className="relative overflow-hidden rounded-2xl bg-muted shadow-2xl ring-1 ring-gray-900/10">
						<div className="aspect-video">
							<iframe
								className="absolute inset-0 h-full w-full"
								src="https://www.youtube.com/embed/DPiogp-D4ig"
								title="Tapped Demo"
								allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
								allowFullScreen
							/>
						</div>
					</div>
				</div>
			</section>

			{/* Features Grid */}

			<section className="bg-muted/50 py-24 sm:py-32">
				<div className="mx-auto max-w-7xl px-6 lg:px-8">
					<div className="mx-auto max-w-2xl text-center">
						<h2 className="font-bold text-3xl tracking-tight sm:text-4xl">
							Everything you need to succeed
						</h2>

						<p className="mt-6 text-lg text-muted-foreground leading-8">
							Stop using spreadsheets and cold emails. Tapped brings the entire ecosystem into one
							beautiful app.
						</p>
					</div>

					<div className="mx-auto mt-16 max-w-2xl sm:mt-20 lg:mt-24 lg:max-w-none">
						<dl className="grid max-w-xl grid-cols-1 gap-x-8 gap-y-16 lg:max-w-none lg:grid-cols-3">
							<div className="flex flex-col items-center text-center">
								<div className="mb-6 flex h-16 w-16 items-center justify-center rounded-2xl bg-blue-600 text-white shadow-lg">
									<MapIcon className="h-8 w-8" />
								</div>

								<dt className="font-semibold text-xl leading-7">Smart Venue Discovery</dt>

								<dd className="mt-1 flex flex-auto flex-col text-base text-muted-foreground leading-7">
									<p className="flex-auto">
										Find the perfect venues for your sound. Filter by capacity, genre, and location
										to route your next tour with data-backed confidence.
									</p>
								</dd>
							</div>

							<div className="flex flex-col items-center text-center">
								<div className="mb-6 flex h-16 w-16 items-center justify-center rounded-2xl bg-cyan-500 text-white shadow-lg">
									<CalendarDays className="h-8 w-8" />
								</div>

								<dt className="font-semibold text-xl leading-7">Seamless Booking</dt>

								<dd className="mt-1 flex flex-auto flex-col text-base text-muted-foreground leading-7">
									<p className="flex-auto">
										Apply to perform at thousands of venues directly through the app. Manage your
										schedule, negotiate offers, and get confirmed instantly.
									</p>
								</dd>
							</div>

							<div className="flex flex-col items-center text-center">
								<div className="mb-6 flex h-16 w-16 items-center justify-center rounded-2xl bg-indigo-600 text-white shadow-lg">
									<BarChart3 className="h-8 w-8" />
								</div>

								<dt className="font-semibold text-xl leading-7">Data & Analytics</dt>

								<dd className="mt-1 flex flex-auto flex-col text-base text-muted-foreground leading-7">
									<p className="flex-auto">
										Track your growth, understand your audience, and leverage real data to prove
										your value to promoters and venues.
									</p>
								</dd>
							</div>
						</dl>
					</div>
				</div>
			</section>

			{/* CTA Section */}

			<section className="px-6 py-24 sm:px-6 sm:py-32 lg:px-8">
				<div className="mx-auto max-w-2xl text-center">
					<h2 className="font-bold text-3xl tracking-tight sm:text-4xl">
						Ready to take the stage?
						<br />
						Download Tapped today.
					</h2>

					<p className="mx-auto mt-6 max-w-xl text-lg text-muted-foreground leading-8">
						Join thousands of artists and venues who are already changing the way live music
						happens. Available for free on iOS and Android.
					</p>

					<div className="mt-10 flex flex-col items-center justify-center gap-4 sm:flex-row">
						<GooglePlayButton url={GOOGLE_URL} theme={"dark"} />

						<AppStoreButton url={APPLE_URL} theme={"dark"} />
					</div>

					<div className="mt-10">
						<Link href="/map">
							<Button variant="link" className="text-muted-foreground">
								Or continue exploring the map on web &rarr;
							</Button>
						</Link>
					</div>
				</div>
			</section>
		</div>
	);
}
