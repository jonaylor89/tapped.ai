import posthog from "posthog-js";

const features = {
	"map-city-center": {
		name: "Map City Center",
		variations: ["control", "los_angles", "chicago", "miami", "san_francisco", "atlanta"],
	},
} as const;
type FeatureKey = keyof typeof features;
type FeatureValue = {
	[K in FeatureKey]: (typeof features)[K]["variations"][number];
};

export const useFeatureFlag = <K extends FeatureKey>(
	featureKey: K,
	defaultValue: (typeof features)[K]["variations"][number] = "control"
): { value: FeatureValue[K] } => {
	const val = (posthog.getFeatureFlag(featureKey) ?? defaultValue) as FeatureValue[K];
	return { value: val };
};
