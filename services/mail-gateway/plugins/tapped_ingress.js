"use strict";

const crypto = require("node:crypto");

exports.register = function register() {
  this.register_hook("lookup_rdns", "skipReverseDns");
  this.register_hook("rcpt", "acceptRecipient");
  this.register_hook("queue", "forwardMessage");
};

exports.skipReverseDns = function skipReverseDns(next) {
  next(OK, "unknown");
};

exports.acceptRecipient = function acceptRecipient(next, connection, params) {
  const domain = (process.env.BOOKING_EMAIL_DOMAIN || "booking.tapped.ai").toLowerCase();
  const address = params[0];
  if (address.host.toLowerCase() !== domain || !/^[a-z0-9][a-z0-9._-]{0,63}$/i.test(address.user)) {
    return next(DENY, "Recipient rejected");
  }
  return next(OK);
};

exports.forwardMessage = async function forwardMessage(next, connection) {
  try {
    const secret = process.env.MAIL_INGRESS_SECRET;
    const endpoint = process.env.MAIL_INGRESS_URL || "http://api:3000/internal/mail/inbound";
    if (!secret) throw new Error("MAIL_INGRESS_SECRET is required");
    const chunks = [];
    for await (const chunk of connection.transaction.message_stream) chunks.push(Buffer.from(chunk));
    const body = Buffer.concat(chunks);
    if (body.length === 0) throw new Error("message was not captured");
    const timestamp = Math.floor(Date.now() / 1000).toString();
    const recipient = connection.transaction.rcpt_to[0].address;
    const signature = crypto
      .createHmac("sha256", secret)
      .update(timestamp)
      .update(".")
      .update(recipient)
      .update(".")
      .update(body)
      .digest("hex");
    const response = await fetch(endpoint, {
      method: "POST",
      headers: {
        "content-type": "message/rfc822",
        "x-tapped-timestamp": timestamp,
        "x-tapped-signature": signature,
        "x-tapped-envelope-to": recipient,
      },
      body,
    });
    if (!response.ok && response.status !== 404 && response.status !== 422) {
      throw new Error(`mail ingress returned ${response.status}`);
    }
    if (response.status === 404 || response.status === 422) {
      connection.logwarn(this, `accepted orphan email: API returned ${response.status}`);
    }
    return next(OK, "Queued by Tapped");
  } catch (error) {
    connection.logerror(this, error.stack || error.message);
    return next(DENYSOFT, "Temporary delivery failure");
  }
};
