
import { slackWebhookUrl } from "./firebase.js";

export async function notifyOnScrapeFailure({ error }: { error: string }) {
  await slackNotification({
    text: `most recent scrape failed with error: ${error} - ${new Date()}`,
  });
}

async function slackNotification(msg: { text: string }) {
  try {
    const response = await fetch(slackWebhookUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(msg),
    });
  
    if (!response.ok) {
      console.error(
        `[!!!] slack notification failed to send - ${response.status}`,
      );
      return;
    }
  
    console.log("[+] notification sent to slack successfully");
  } catch (error) {
    console.error(error);
  }
}
  