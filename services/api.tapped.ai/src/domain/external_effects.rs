//! Durable provider effects. Application mutations enqueue here in their own Postgres transaction.
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use sqlx::{Postgres, Transaction};

pub async fn enqueue(
    tx: &mut Transaction<'_, Postgres>,
    id: &str,
    kind: &str,
    payload: Value,
) -> Result<(), sqlx::Error> {
    sqlx::query("INSERT INTO external_effect_outbox(id,kind,payload) VALUES($1,$2,$3) ON CONFLICT(id) DO NOTHING")
        .bind(id).bind(kind).bind(payload).execute(&mut **tx).await?;
    Ok(())
}

pub fn booking_email_recipients(booking: &Value, profiles: &[Value]) -> Vec<(String, String)> {
    // The deployed handlers check property presence, including explicit null/empty values.
    if booking["status"] != "pending" || booking.get("calendarEventId").is_some() {
        return vec![];
    }
    [
        ("requesterId", "bookingRequestSent"),
        ("requesteeId", "bookingRequestReceived"),
    ]
    .into_iter()
    .filter_map(|(role, template)| {
        let uid = booking[role].as_str().filter(|uid| !uid.is_empty())?;
        let user = profiles.iter().find(|user| user["id"] == uid)?;
        let email = user["email"].as_str().unwrap_or_default();
        // Preserve the deployed asymmetry: sent checks booking.addedByUser; received
        // checks requestee.addedByUser. Do not silently "fix" business behavior in a port.
        let added = if role == "requesterId" {
            &booking["addedByUser"]
        } else {
            &user["addedByUser"]
        };
        if email.is_empty()
            || email.ends_with("@tapped.ai")
            || user["unclaimed"] == true
            || user["deleted"] == true
            || added == &Value::Bool(true)
        {
            return None;
        }
        Some((email.to_owned(), template.into()))
    })
    .collect()
}

/// Called under the identity/profile lock: keeps the profile email in step with Auth.
pub async fn update_identity_email(
    tx: &mut Transaction<'_, Postgres>,
    uid: &str,
    email: &str,
) -> Result<(), sqlx::Error> {
    sqlx::query("UPDATE users SET email=$2 WHERE id=$1 AND NOT unclaimed AND NOT deleted AND email IS DISTINCT FROM $2")
        .bind(uid).bind(email).execute(&mut **tx).await?;
    Ok(())
}

/// The founders' automatic welcome messages, in order per founder.
const WELCOME_MESSAGES: [(&str, &[&str]); 2] = [
    (
        "8yYVxpQ7cURSzNfBsaBGF7A7kkv2",
        &[
            "welcome to tapped!",
            "I work with the engineering team so if you have any ideas on how to make the app better lemme know and I can send it to them",
        ],
    ),
    (
        "n4zIL6bOuPTqRC3dtsl6gyEBPQl1",
        &["welcome to the app! how did you find out about us?"],
    ),
];

/// Welcomes a newly created, claimed profile with direct messages from the founders, in the
/// transaction that creates it. Stable message IDs make a replayed creation a no-op.
pub async fn welcome_new_profile(
    tx: &mut Transaction<'_, Postgres>,
    doc: &Value,
) -> Result<(), sqlx::Error> {
    use crate::domain::direct_messages::store::{DmError, ServerMessage, post_server_message};
    let Some(uid) = doc["id"].as_str() else {
        return Ok(());
    };
    if doc["unclaimed"] == true || doc["deleted"] == true {
        return Ok(());
    }
    for (sender, messages) in WELCOME_MESSAGES {
        let active: bool =
            sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM users WHERE id=$1 AND NOT deleted)")
                .bind(sender)
                .fetch_one(&mut **tx)
                .await?;
        if sender == uid || !active {
            continue;
        }
        for (index, text) in messages.iter().enumerate() {
            let message = ServerMessage {
                event_id: format!("welcome:{sender}:{uid}:{index}"),
                thread_id: String::new(),
                sender_id: sender.into(),
                receiver_id: uid.into(),
                text: (*text).into(),
                frozen: false,
            };
            match post_server_message(tx, &message).await {
                Ok(_) => {}
                Err(DmError::Database(error)) => return Err(error),
                Err(error) => return Err(sqlx::Error::Protocol(error.to_string())),
            }
        }
    }
    Ok(())
}

pub async fn record_booking_emails(
    tx: &mut Transaction<'_, Postgres>,
    doc: &Value,
) -> Result<(), sqlx::Error> {
    let mut users = Vec::new();
    for field in ["requesterId", "requesteeId"] {
        if let Some(uid) = doc[field].as_str() {
            let user: Option<Value> = sqlx::query_scalar("SELECT doc FROM api_users WHERE id=$1")
                .bind(uid)
                .fetch_optional(&mut **tx)
                .await?;
            if let Some(user) = user {
                users.push(user);
            }
        }
    }
    for (email, template) in booking_email_recipients(doc, &users) {
        let id = format!(
            "booking-mail:{}:{template}",
            doc["id"].as_str().unwrap_or_default()
        );
        // The legacy extension resolved these exact template names at delivery time.
        enqueue(
            tx,
            &id,
            "mail",
            json!({"to":email,"template":template,"bookingId":doc["id"]}),
        )
        .await?;
    }
    Ok(())
}

pub fn activity_notification(kind: &str) -> Option<(&'static str, &'static str)> {
    match kind {
        "bookingRequest" => Some((
            "New Booking Request",
            "You just got a new booking request 🔥",
        )),
        "bookingUpdate" => Some((
            "Booking Update",
            "There was an update to one of your bookings",
        )),
        "bookingReminder" => Some(("Booking Reminder", "You have a booking coming up soon!!!")),
        "searchAppearance" => Some((
            "You're on the map!",
            "you've showed up in new searches this week 👀",
        )),
        _ => None,
    }
}

pub async fn record_activity(
    tx: &mut Transaction<'_, Postgres>,
    id: &str,
    uid: &str,
    kind: &str,
    booking: &str,
) -> Result<(), sqlx::Error> {
    let Some((title, body)) = activity_notification(kind) else {
        return Ok(());
    };
    let email: Option<String> =
        sqlx::query_scalar("SELECT email FROM users WHERE id=$1 AND NOT deleted")
            .bind(uid)
            .fetch_optional(&mut **tx)
            .await?;
    if email.is_none_or(|email| email.ends_with("@tapped.ai")) {
        return Ok(());
    }
    let tokens: Vec<(String, String, Option<String>)> = sqlx::query_as(
        "SELECT token,provider,apns_environment FROM device_tokens WHERE user_id=$1",
    )
    .bind(uid)
    .fetch_all(&mut **tx)
    .await?;
    for (token, provider, environment) in tokens {
        let key = format!(
            "push:{id}:{}",
            hex::encode(Sha256::digest(token.as_bytes()))
        );
        enqueue(tx,&key,"push",json!({"token":token,"provider":provider,"environment":environment,"uid":uid,"title":title,"body":body,"activityId":id,"bookingId":booking})).await?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn booking_mail_retains_legacy_filters_and_recipients() {
        let profiles = vec![
            json!({"id":"booker","email":"booker@example.test"}),
            json!({"id":"artist","email":"artist@example.test"}),
        ];
        let mut booking = json!({"status":"pending","requesterId":"booker","requesteeId":"artist"});
        assert_eq!(
            booking_email_recipients(&booking, &profiles),
            vec![
                ("booker@example.test".into(), "bookingRequestSent".into()),
                (
                    "artist@example.test".into(),
                    "bookingRequestReceived".into()
                )
            ]
        );
        booking["addedByUser"] = json!(true);
        assert_eq!(
            booking_email_recipients(&booking, &profiles),
            vec![(
                "artist@example.test".into(),
                "bookingRequestReceived".into()
            )]
        );
        booking.as_object_mut().unwrap().remove("addedByUser");
        for value in [json!(null), json!(""), json!("calendar-id")] {
            booking["calendarEventId"] = value;
            assert!(booking_email_recipients(&booking, &profiles).is_empty());
        }
        booking.as_object_mut().unwrap().remove("calendarEventId");
        booking["status"] = json!("confirmed");
        assert!(booking_email_recipients(&booking, &profiles).is_empty());
        booking["status"] = json!("pending");
        for mut user in [
            json!({"email":"johannes@tapped.ai"}),
            json!({"email":""}),
            json!({"email":"venue@example.test","unclaimed":true}),
            json!({"email":"venue@example.test","deleted":true}),
        ] {
            user["id"] = json!("booker");
            assert!(booking_email_recipients(&booking, &[user]).is_empty());
        }
    }
    #[test]
    fn booking_mail_roles_are_bound_to_participants_even_for_self_bookings() {
        let user = json!({"id":"same","email":"same@example.test"});
        let booking = json!({"status":"pending","requesterId":"same","requesteeId":"same"});
        assert_eq!(
            booking_email_recipients(&booking, std::slice::from_ref(&user)).len(),
            2
        );
        assert!(
            booking_email_recipients(
                &booking,
                &[json!({"id":"other","email":"other@example.test"})]
            )
            .is_empty()
        );
        assert_eq!(
            booking_email_recipients(
                &booking,
                &[json!({"id":"same","email":"same@example.test","addedByUser":true})]
            ),
            vec![("same@example.test".into(), "bookingRequestSent".into())]
        );
        assert_eq!(
            booking_email_recipients(
                &json!({"status":"pending","requesterId":null,"requesteeId":"same"}),
                &[user]
            ),
            vec![("same@example.test".into(), "bookingRequestReceived".into())]
        );
    }
    #[test]
    fn unsupported_activity_does_not_send_push() {
        assert!(activity_notification("follow").is_none());
        assert!(activity_notification("bookingRequest").is_some());
    }
}
