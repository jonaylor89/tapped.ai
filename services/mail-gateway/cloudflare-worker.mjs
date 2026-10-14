// SMTP transport only; Rust owns parsing, routing and durable inbox capture.
export default {
  async email(message, env) {
    if (!/^reply\+[a-z0-9._-]+@booking\.tapped\.ai$/i.test(message.to) || message.rawSize > 10 * 1024 * 1024) {
      message.setReject("Invalid recipient or message too large");
      return;
    }
    const body = await new Response(message.raw).arrayBuffer();
    const timestamp = String(Math.floor(Date.now() / 1000));
    const prefix = new TextEncoder().encode(`${timestamp}.${message.to}.`);
    const signed = new Uint8Array(prefix.length + body.byteLength);
    signed.set(prefix); signed.set(new Uint8Array(body), prefix.length);
    const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(env.MAIL_INGRESS_SECRET), {name:"HMAC",hash:"SHA-256"}, false, ["sign"]);
    const mac = await crypto.subtle.sign("HMAC", key, signed);
    const signature = Array.from(new Uint8Array(mac), x => x.toString(16).padStart(2,"0")).join("");
    const response = await fetch("https://api.tapped.ai/internal/mail/inbound", {
      method:"POST", redirect:"error", body,
      headers:{"content-type":"message/rfc822","x-tapped-timestamp":timestamp,"x-tapped-signature":signature,"x-tapped-envelope-to":message.to,"user-agent":"Tapped-SMTP-Transport/1.0"}
    });
    if (!response.ok && ![400,404,422].includes(response.status)) throw new Error("Rust mailbox unavailable");
  },
};
