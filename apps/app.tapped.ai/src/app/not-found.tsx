import Link from "next/link";
import { Button } from "@/components/ui/button";

export default function NotFound() {
	return (
		<main className="relative min-h-screen overflow-hidden bg-background text-foreground">
			<div className="pointer-events-none absolute inset-0">
				<div className="absolute -left-24 top-24 h-72 w-72 rounded-full bg-sky-500/20 blur-3xl" />
				<div className="absolute -right-16 top-10 h-64 w-64 rounded-full bg-cyan-400/20 blur-3xl" />
				<div className="absolute bottom-0 right-10 h-72 w-72 rounded-full bg-emerald-400/10 blur-3xl" />
				<div className="absolute left-1/2 top-16 h-48 w-48 -translate-x-1/2 rounded-full border border-sky-500/30" />
				<div className="absolute left-1/2 top-28 h-3 w-3 -translate-x-1/2 rounded-full bg-sky-300 shadow-[0_0_20px_rgba(56,189,248,0.65)]" />
			</div>

			<section className="relative mx-auto flex min-h-screen max-w-6xl flex-col items-center justify-center gap-12 px-6 py-24 lg:flex-row lg:items-start">
				<div className="flex-1 space-y-6">
					<p className="text-xs font-semibold uppercase tracking-[0.4em] text-muted-foreground">
						tour routing error
					</p>
					<h1 className="text-5xl font-black leading-tight sm:text-6xl lg:text-7xl">
						This stage is off the map.
					</h1>
					<p className="max-w-xl text-lg text-muted-foreground">
						The setlist brought you to a venue that does not exist (yet). Let&apos;s get you back to
						live music insights, real locations, and performers who are actually booked.
					</p>
					<div className="flex flex-wrap gap-3">
						<Button asChild>
							<Link href="/">Back to home</Link>
						</Button>
						<Button asChild variant="secondary">
							<Link href="/search">Search performers</Link>
						</Button>
						<Button asChild variant="outline">
							<Link href="/map">Open the map</Link>
						</Button>
					</div>
				</div>

				<div className="w-full max-w-md flex-1 space-y-6 rounded-3xl border border-border/60 bg-background/70 p-6 shadow-lg backdrop-blur">
					<div className="space-y-2">
						<p className="text-xs font-semibold uppercase tracking-[0.4em] text-muted-foreground">
							suggested setlist
						</p>
						<h2 className="text-2xl font-semibold">Make the next stop count</h2>
						<p className="text-sm text-muted-foreground">
							Use these routes to get back on track with real demand signals.
						</p>
					</div>
					<div className="space-y-4">
						<div className="rounded-2xl border border-border/50 bg-muted/40 p-4">
							<p className="text-sm font-semibold">Featured performers</p>
							<p className="text-sm text-muted-foreground">
								Find artists trending in high-intent markets.
							</p>
						</div>
						<div className="rounded-2xl border border-border/50 bg-muted/40 p-4">
							<p className="text-sm font-semibold">Opportunity tracker</p>
							<p className="text-sm text-muted-foreground">
								Review live booking opportunities by location.
							</p>
						</div>
						<div className="rounded-2xl border border-border/50 bg-muted/40 p-4">
							<p className="text-sm font-semibold">Tour heat map</p>
							<p className="text-sm text-muted-foreground">
								See where fans are ready to buy tickets.
							</p>
						</div>
					</div>
					<div className="flex items-center justify-between rounded-2xl border border-sky-500/30 bg-sky-500/10 px-4 py-3 text-sm">
						<span className="font-semibold text-sky-200">Error code</span>
						<span className="font-mono text-sky-100">404</span>
					</div>
				</div>
			</section>
		</main>
	);
}
