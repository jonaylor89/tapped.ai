#!/usr/bin/env python3
"""Backfill legacy Firestore venue-contact threads into the deployed mail bridge."""

import hashlib
import hmac
import json
import os
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from datetime import datetime


def access_token() -> str:
    configured = os.environ.get("GOOGLE_OAUTH_ACCESS_TOKEN")
    if configured:
        return configured
    return subprocess.check_output(
        ["gcloud", "auth", "application-default", "print-access-token"],
        text=True,
    ).strip()


def decode(value):
    if "stringValue" in value:
        return value["stringValue"]
    if "booleanValue" in value:
        return value["booleanValue"]
    if "integerValue" in value:
        return int(value["integerValue"])
    if "doubleValue" in value:
        return value["doubleValue"]
    if "nullValue" in value:
        return None
    if "arrayValue" in value:
        return [decode(item) for item in value["arrayValue"].get("values", [])]
    if "mapValue" in value:
        return {key: decode(item) for key, item in value["mapValue"].get("fields", {}).items()}
    if "timestampValue" in value:
        return value["timestampValue"]
    return None


def request_json(url: str, token: str, payload=None, headers=None):
    body = None if payload is None else json.dumps(payload, separators=(",", ":")).encode()
    request = urllib.request.Request(
        url,
        data=body,
        headers={
            "Authorization": f"Bearer {token}",
            "content-type": "application/json",
            **(headers or {}),
        },
        method="GET" if body is None else "POST",
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        data = response.read()
        return json.loads(data) if data else None


def performer_username(project_id: str, token: str, performer_id: str) -> str | None:
    encoded = urllib.parse.quote(performer_id, safe="")
    document = request_json(
        f"https://firestore.googleapis.com/v1/projects/{project_id}/databases/(default)/documents/users/{encoded}",
        token,
    )
    return decode(document.get("fields", {}).get("username", {}))


def send_record(api_url: str, secret: str, endpoint: str, record: dict) -> None:
    body = json.dumps(record, separators=(",", ":")).encode()
    timestamp = str(int(time.time()))
    signature = hmac.new(secret.encode(), timestamp.encode() + b".." + body, hashlib.sha256).hexdigest()
    request = urllib.request.Request(
        f"{api_url}/internal/mail/{endpoint}",
        data=body,
        headers={
            "content-type": "application/json",
            "x-tapped-timestamp": timestamp,
            "x-tapped-signature": signature,
        },
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        if response.status != 204:
            raise RuntimeError(f"unexpected backfill response: {response.status}")


def message_id(fields: dict) -> str | None:
    for header in fields.get("Headers") or []:
        if (header.get("Name") or "").lower() == "message-id":
            return header.get("Value")
    return fields.get("MessageID")


def main() -> None:
    apply = "--apply" in sys.argv
    project_id = os.environ.get("FIREBASE_PROJECT_ID", "in-the-loop-306520")
    api_url = os.environ.get("TAPPED_API_URL", "https://api.tapped.ai").rstrip("/")
    secret = os.environ.get("MAIL_API_SECRET")
    if apply and not secret:
        raise RuntimeError("MAIL_API_SECRET is required with --apply")

    token = access_token()
    results = request_json(
        f"https://firestore.googleapis.com/v1/projects/{project_id}/databases/(default)/documents:runQuery",
        token,
        {"structuredQuery": {"from": [{"collectionId": "venuesContacted", "allDescendants": True}]}},
    )
    messages = request_json(
        f"https://firestore.googleapis.com/v1/projects/{project_id}/databases/(default)/documents:runQuery",
        token,
        {"structuredQuery": {"from": [{"collectionId": "emailsSent", "allDescendants": True}]}},
    )
    messages_by_thread: dict[tuple[str, str], list[dict]] = {}
    for result in messages:
        document = result.get("document")
        if not document:
            continue
        path = document["name"].split("/documents/", 1)[1].split("/")
        if len(path) < 6:
            continue
        fields = {key: decode(value) for key, value in document.get("fields", {}).items()}
        identifier = message_id(fields)
        recipients = [item.strip() for item in (fields.get("To") or "").split(",") if item.strip()]
        if not identifier or not fields.get("From") or not recipients:
            continue
        created_at = int(datetime.fromisoformat(document["createTime"].replace("Z", "+00:00")).timestamp())
        performer_id, venue_id = path[-5], path[-3]
        messages_by_thread.setdefault((performer_id, venue_id), []).append({
            "thread_id": f"{performer_id}:{venue_id}",
            "message_id": identifier,
            "direction": "outbound",
            "from": fields["From"],
            "to": recipients,
            "subject": fields.get("Subject") or "",
            "text_body": fields.get("TextBody") or "",
            "html_body": fields.get("HtmlBody"),
            "created_at": created_at,
        })

    stats = {"mode": "apply" if apply else "dry-run", "scanned": 0, "eligible": 0, "skipped": 0, "threads_written": 0, "messages_eligible": 0, "messages_written": 0}

    for result in results:
        document = result.get("document")
        if not document:
            continue
        stats["scanned"] += 1
        fields = {key: decode(value) for key, value in document.get("fields", {}).items()}
        path = document["name"].split("/documents/", 1)[1].split("/")
        if len(path) < 4:
            stats["skipped"] += 1
            continue
        performer_id, venue_id = path[-3], path[-1]
        username = (fields.get("user") or {}).get("username") or performer_username(project_id, token, performer_id)
        recipients = [email for email in fields.get("allEmails") or [] if isinstance(email, str) and email]
        if not recipients and fields.get("bookingEmail"):
            recipients = [fields["bookingEmail"]]
        latest_message_id = fields.get("latestMessageId")
        subject = fields.get("subject")
        if not username or not recipients or not latest_message_id or not subject:
            stats["skipped"] += 1
            continue

        thread = {
            "id": f"{performer_id}:{venue_id}",
            "performer_id": performer_id,
            "performer_username": username,
            "venue_id": venue_id,
            "recipients": recipients,
            "subject": subject,
            "latest_message_id": latest_message_id,
        }
        stats["eligible"] += 1
        thread_messages = messages_by_thread.get((performer_id, venue_id), [])
        stats["messages_eligible"] += len(thread_messages)
        if apply:
            send_record(api_url, secret, "backfill-thread", thread)
            stats["threads_written"] += 1
            for message in thread_messages:
                send_record(api_url, secret, "backfill-message", message)
                stats["messages_written"] += 1

    print(json.dumps(stats, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"mail thread backfill failed: {error}", file=sys.stderr)
        raise
