import { slackWebhookUrl } from "../firebase";

export async function notifyScapeStart({
  runId,
  eventCount,
}: {
  runId: string;
  eventCount: number;
}) {
  await slackNotification({
    text: `scrape run ${runId} started with ${eventCount} events - ${new Date()}`,
  });
}

export async function notifyOnScrapeSuccess({
  runId,
  eventCount,
}: {
  runId: string;
  eventCount: number;
}) {
  if (eventCount === 0) {
    await slackNotification({
      text: `no new events in scrape run ${runId} - ${new Date()}`,
    });
  }

  await slackNotification({
    text: `scrape run ${runId} succeeded with ${eventCount} new events - ${new Date()}`,
  });
}

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
