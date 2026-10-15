import { configDotenv } from "dotenv";

// Compatibility filename: provider configuration only. No Auth, Firestore, FCM or Storage client.
configDotenv({ path: ".env" });
export const openaiApiKey = process.env.OPENAI_API_KEY ?? "";
export const slackWebhookUrl = process.env.SLACK_WEBHOOK_URL ?? "";
export const googlePlacesApiKey = process.env.GOOGLE_PLACES_API_KEY ?? "";
