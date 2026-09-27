#!/usr/bin/env python3
"""Post-deploy Stream ↔ email smoke test using real Firebase, SMTP, IMAP, and Stream services."""

import base64
import email
import hashlib
import hmac
import imaplib
import json
import os
import smtplib
import ssl
import sys
import time
import urllib.parse
import urllib.request
import uuid
from email.message import EmailMessage


def required(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise RuntimeError(f"{name} is required")
    return value


def request_json(url: str, payload: dict, headers: dict[str, str] | None = None) -> dict:
    request = urllib.request.Request(
        url,
        data=json.dumps(payload, separators=(",", ":")).encode(),
        headers={"content-type": "application/json", **(headers or {})},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        body = response.read()
        return json.loads(body) if body else {}


def stream_token(secret: str) -> str:
    encode = lambda value: base64.urlsafe_b64encode(value).rstrip(b"=")
    header = encode(b'{"alg":"HS256","typ":"JWT"}')
    payload = encode(b'{"server":true}')
    signature = encode(hmac.new(secret.encode(), header + b"." + payload, hashlib.sha256).digest())
    return b".".join((header, payload, signature)).decode()


def wait_for_email(host: str, username: str, password: str, marker: str, timeout: int) -> tuple[str, str]:
    deadline = time.time() + timeout
    while time.time() < deadline:
        with imaplib.IMAP4_SSL(host) as mailbox:
            mailbox.login(username, password)
            mailbox.select("INBOX")
            _, result = mailbox.search(None, "TEXT", f'"{marker}"')
            ids = result[0].split()
            if ids:
                message_id = ids[-1]
                _, raw = mailbox.fetch(message_id, "(RFC822)")
                parsed = email.message_from_bytes(raw[0][1])
                mailbox.store(message_id, "+FLAGS", "\\Deleted")
                mailbox.expunge()
                return parsed["Message-ID"], email.utils.parseaddr(parsed["From"])[1]
        time.sleep(5)
    raise TimeoutError(f"email containing {marker!r} did not arrive within {timeout}s")


def send_reply(host: str, port: int, sender: str, recipient: str, parent_id: str, marker: str) -> None:
    message = EmailMessage()
    message["From"] = sender
    message["To"] = recipient
    message["Subject"] = f"Re: deployed mail smoke {marker}"
    message["Message-ID"] = f"<{uuid.uuid4()}@smoke.tapped.ai>"
    message["In-Reply-To"] = parent_id
    message["References"] = parent_id
    message.set_content(marker)
    with smtplib.SMTP(host, port, timeout=30) as smtp:
        smtp.ehlo()
        if smtp.has_extn("STARTTLS"):
            smtp.starttls(context=ssl.create_default_context())
            smtp.ehlo()
        smtp.send_message(message)


def stream_has_message(api_key: str, secret: str, performer_id: str, venue_id: str, marker: str) -> bool:
    query = urllib.parse.urlencode({"api_key": api_key})
    response = request_json(
        f"https://chat.stream-io-api.com/channels/messaging/query?{query}",
        {"data": {"members": [performer_id, venue_id], "created_by_id": venue_id}, "state": True},
        {"Authorization": stream_token(secret)},
    )
    messages = response.get("messages") or response.get("channel", {}).get("messages") or []
    return any(message.get("text") == marker for message in messages)


def main() -> None:
    api_url = required("MAIL_SMOKE_API_URL").rstrip("/")
    web_api_key = required("FIREBASE_WEB_API_KEY")
    test_email = required("FIREBASE_TEST_EMAIL")
    test_password = required("FIREBASE_TEST_PASSWORD")
    venue_id = required("MAIL_SMOKE_VENUE_ID")
    imap_host = required("MAIL_SMOKE_IMAP_HOST")
    imap_username = required("MAIL_SMOKE_IMAP_USERNAME")
    imap_password = required("MAIL_SMOKE_IMAP_PASSWORD")
    smtp_host = required("MAIL_SMOKE_SMTP_HOST")
    smtp_port = int(os.environ.get("MAIL_SMOKE_SMTP_PORT") or "25")
    stream_key = required("STREAM_KEY")
    stream_secret = required("STREAM_SECRET")
    timeout = int(os.environ.get("MAIL_SMOKE_TIMEOUT_SECONDS", "180"))

    auth = request_json(
        f"https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key={urllib.parse.quote(web_api_key)}",
        {"email": test_email, "password": test_password, "returnSecureToken": True},
    )
    performer_id = auth["localId"]
    marker = f"mail-smoke-{uuid.uuid4()}"
    subject = f"deployed mail smoke {marker}"
    request_json(
        f"{api_url}/app/v1/venue-email-threads",
        {"id": marker, "venue_id": venue_id, "subject": subject, "text_body": marker},
        {"Authorization": f"Bearer {auth['idToken']}"},
    )

    parent_id, reply_address = wait_for_email(imap_host, imap_username, imap_password, marker, timeout)
    send_reply(smtp_host, smtp_port, imap_username, reply_address, parent_id, marker)

    deadline = time.time() + timeout
    while time.time() < deadline:
        if stream_has_message(stream_key, stream_secret, performer_id, venue_id, marker):
            print(json.dumps({"status": "passed", "marker": marker}))
            return
        time.sleep(5)
    raise TimeoutError(f"Stream message {marker!r} did not arrive within {timeout}s")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"mail deployment smoke failed: {error}", file=sys.stderr)
        raise
