import { createHmac } from "node:crypto";

export interface Header {
  Name: string;
  Value: string;
}

export interface Attachment {
  Name: string;
  Content: string;
  ContentType: string;
  ContentID?: string;
}

export interface EmailMessage {
  From: string;
  To: string;
  Cc?: string;
  Subject: string;
  HtmlBody?: string;
  TextBody?: string;
  Headers?: Header[];
  Attachments?: Attachment[];
  MessageStream?: string;
  TrackOpens?: boolean;
}

export type Message = EmailMessage;
export namespace Models {
  export type Message = EmailMessage;
}

export class ServerClient {
  constructor(private readonly secret: string) {}

  async sendEmail(message: EmailMessage): Promise<{ MessageID: string }> {
    const body = JSON.stringify(message);
    const timestamp = Math.floor(Date.now() / 1000).toString();
    const signature = createHmac("sha256", this.secret)
      .update(timestamp)
      .update(".")
      .update("")
      .update(".")
      .update(body)
      .digest("hex");
    const apiUrl = process.env.TAPPED_API_URL ?? "https://api.tapped.ai";
    const response = await fetch(`${apiUrl}/internal/mail/outbound`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-tapped-timestamp": timestamp,
        "x-tapped-signature": signature,
      },
      body,
    });
    if (!response.ok) {
      throw new Error(`Tapped mail API returned ${response.status}: ${await response.text()}`);
    }
    const messageId = message.Headers?.find((header) => header.Name.toLowerCase() === "message-id")?.Value ?? "queued";
    return { MessageID: messageId };
  }
}
