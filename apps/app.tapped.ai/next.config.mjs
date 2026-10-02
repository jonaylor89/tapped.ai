const nextConfig = {
	reactStrictMode: true,
	images: {
		// Firebase Storage images are resized by imgproxy (img.tapped.ai), not Vercel; see src/lib/image-loader.ts.
		loader: "custom",
		loaderFile: "./src/lib/image-loader.ts",
		// Together these are the imgproxy `w<N>` preset ladder.
		imageSizes: [64, 128, 256, 384],
		deviceSizes: [640, 828, 1080, 1600],
		dangerouslyAllowSVG: true,
		remotePatterns: [
			{
				protocol: "https",
				hostname: "firebasestorage.googleapis.com",
			},
			{
				protocol: "http",
				hostname: "localhost",
				port: "3000",
			},
			{
				protocol: "https",
				hostname: "files.stripe.com",
			},
			{
				protocol: "https",
				hostname: "res.cloudinary.com",
			},
			{
				protocol: "https",
				hostname: "storage.googleapis.com",
			},
			{
				protocol: "https",
				hostname: "songbyrddc.com",
			},
			{
				protocol: "https",
				hostname: "lh3.googleusercontent.com",
			},
			{
				protocol: "https",
				hostname: "images.squarespace-cdn.com",
			},
		],
	},
	async rewrites() {
		return [
			{
				source: "/ingest/static/:path*",
				destination: "https://us-assets.i.posthog.com/static/:path*",
			},
			{
				source: "/ingest/:path*",
				destination: "https://us.i.posthog.com/:path*",
			},
			{
				source: "/ingest/decide",
				destination: "https://us.i.posthog.com/decide",
			},
			{
				source: "/roadmap",
				destination:
					"https://tappedapp.notion.site/Technical-Roadmap-4edc036572bd4d89913f5cd5a4cde0f6?pvs=4",
			},
		];
	},
	// This is required to support PostHog trailing slash API requests
	skipTrailingSlashRedirect: true,
	eslint: {
		ignoreDuringBuilds: true,
	},
};

export default nextConfig;
