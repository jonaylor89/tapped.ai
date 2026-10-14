import { Storage } from "@google-cloud/storage";
import { configDotenv } from "dotenv";

// Compatibility filename: provider configuration only. No Auth, Firestore or FCM client.
configDotenv({ path: ".env.local" });
export const projectId = "in-the-loop-306520";
export const storage = new Storage({ projectId });
export const bucket = storage.bucket(`${projectId}.appspot.com`);
export const openaiApiKey = process.env.OPENAI_API_KEY ?? "";
export const slackWebhookUrl = process.env.SLACK_WEBHOOK_URL ?? "";
export const googlePlacesApiKey = process.env.GOOGLE_PLACES_API_KEY ?? "";
