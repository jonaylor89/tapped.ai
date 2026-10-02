import type { ImageLoaderProps } from "next/image";

// Mirrors the `w<N>` imgproxy presets in docker-compose.prod.yml. `images.deviceSizes` and
// `images.imageSizes` in next.config.mjs list the same widths, so every requested width hits a preset.
const PRESET_WIDTHS = [64, 128, 256, 384, 640, 828, 1080, 1600];

// Mirrors IMGPROXY_ALLOWED_SOURCES; anything else is served as-is.
const PROXIED_SOURCES = [
	"https://firebasestorage.googleapis.com/v0/b/in-the-loop-306520.appspot.com/",
	"https://storage.googleapis.com/in-the-loop-306520.appspot.com/",
];

// Unset (local dev, previews) serves original images.
const proxyUrl = process.env.NEXT_PUBLIC_IMAGE_PROXY_URL;

const base64Url = (value: string): string =>
	btoa(value).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

export default function imageLoader({ src, width }: ImageLoaderProps): string {
	if (!proxyUrl || !PROXIED_SOURCES.some((prefix) => src.startsWith(prefix))) {
		return src;
	}

	const preset =
		PRESET_WIDTHS.find((presetWidth) => presetWidth >= width) ??
		PRESET_WIDTHS[PRESET_WIDTHS.length - 1];
	return `${proxyUrl}/unsafe/w${preset}/${base64Url(src)}`;
}
