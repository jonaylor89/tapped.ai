//! Realtime fan-out. Writers `pg_notify` inside their transaction (see `store::notify`); every API
//! process holds one `LISTEN` connection, and for each committed event builds the payload once per
//! locally connected member and pushes it to their SSE streams. Nothing is buffered across
//! reconnects: clients resync from the API on `ready`/`resync` and fill `seq` gaps themselves.
use serde_json::{Value, json};
use sqlx::{PgPool, Row, postgres::PgListener};
use std::{
    collections::HashMap,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, AtomicU64, Ordering},
    },
    time::Duration,
};
use tokio::sync::mpsc;
use uuid::Uuid;

use super::store::{self, NOTIFY_CHANNEL};

/// Events queued per connection before it counts as stalled and is closed (the client resyncs).
const CONNECTION_BUFFER: usize = 256;
/// Older streams of the same user are closed beyond this (several devices, plus reconnect overlap).
const MAX_CONNECTIONS_PER_USER: usize = 8;

pub type Payload = Arc<str>;

struct Subscriber {
    id: u64,
    sender: mpsc::Sender<Payload>,
}

#[derive(Default)]
struct Inner {
    subscribers: Mutex<HashMap<String, Vec<Subscriber>>>,
    next_id: AtomicU64,
    closed: AtomicBool,
}

/// Process-local registry of SSE connections. Cheap to clone.
#[derive(Clone, Default)]
pub struct Hub {
    inner: Arc<Inner>,
}

/// An open stream's registration; dropping it unregisters the connection.
pub struct Subscription {
    pub receiver: mpsc::Receiver<Payload>,
    uid: String,
    id: u64,
    hub: Hub,
}

impl Drop for Subscription {
    fn drop(&mut self) {
        self.hub.remove(&self.uid, self.id);
    }
}

#[derive(Debug, serde::Deserialize)]
struct Notification {
    k: String,
    c: Uuid,
    s: i64,
    u: Vec<String>,
}

impl Hub {
    /// `None` once the server is shutting down.
    pub fn subscribe(&self, uid: &str) -> Option<Subscription> {
        if self.inner.closed.load(Ordering::Acquire) {
            return None;
        }
        let (sender, receiver) = mpsc::channel(CONNECTION_BUFFER);
        let id = self.inner.next_id.fetch_add(1, Ordering::Relaxed);
        let mut subscribers = self.inner.subscribers.lock().expect("hub mutex poisoned");
        let connections = subscribers.entry(uid.to_owned()).or_default();
        if connections.len() >= MAX_CONNECTIONS_PER_USER {
            // Dropping the sender ends the oldest stream.
            connections.remove(0);
        }
        connections.push(Subscriber { id, sender });
        Some(Subscription {
            receiver,
            uid: uid.to_owned(),
            id,
            hub: self.clone(),
        })
    }

    fn remove(&self, uid: &str, id: u64) {
        let mut subscribers = self.inner.subscribers.lock().expect("hub mutex poisoned");
        if let Some(connections) = subscribers.get_mut(uid) {
            connections.retain(|subscriber| subscriber.id != id);
            if connections.is_empty() {
                subscribers.remove(uid);
            }
        }
    }

    pub fn connection_count(&self) -> usize {
        self.inner
            .subscribers
            .lock()
            .expect("hub mutex poisoned")
            .values()
            .map(Vec::len)
            .sum()
    }

    fn connected(&self, uids: &[String]) -> Vec<String> {
        let subscribers = self.inner.subscribers.lock().expect("hub mutex poisoned");
        uids.iter()
            .filter(|uid| subscribers.contains_key(*uid))
            .cloned()
            .collect()
    }

    /// Never blocks: a connection that cannot take the event is closed so its client resyncs,
    /// instead of silently missing an event or stalling everyone else.
    pub fn send(&self, uid: &str, payload: Payload) {
        let mut subscribers = self.inner.subscribers.lock().expect("hub mutex poisoned");
        if let Some(connections) = subscribers.get_mut(uid) {
            connections.retain(|subscriber| subscriber.sender.try_send(payload.clone()).is_ok());
            if connections.is_empty() {
                subscribers.remove(uid);
            }
        }
    }

    fn broadcast(&self, payload: Payload) {
        let mut subscribers = self.inner.subscribers.lock().expect("hub mutex poisoned");
        for connections in subscribers.values_mut() {
            connections.retain(|subscriber| subscriber.sender.try_send(payload.clone()).is_ok());
        }
        subscribers.retain(|_, connections| !connections.is_empty());
    }

    /// Ends every stream (graceful shutdown would otherwise wait for long-lived connections).
    pub fn close(&self) {
        self.inner.closed.store(true, Ordering::Release);
        self.inner
            .subscribers
            .lock()
            .expect("hub mutex poisoned")
            .clear();
    }

    /// Keeps one LISTEN connection open for the life of the process, reconnecting with backoff.
    pub fn spawn_listener(&self, pool: PgPool) -> tokio::task::JoinHandle<()> {
        let hub = self.clone();
        tokio::spawn(async move {
            let mut delay = Duration::from_millis(500);
            loop {
                match hub.listen(&pool).await {
                    Ok(()) => return,
                    Err(error) => {
                        tracing::warn!(?error, "direct message listener lost; reconnecting");
                        tokio::time::sleep(delay).await;
                        delay = (delay * 2).min(Duration::from_secs(30));
                    }
                }
            }
        })
    }

    async fn listen(&self, pool: &PgPool) -> anyhow::Result<()> {
        let mut listener = PgListener::connect_with(pool).await?;
        listener.listen(NOTIFY_CHANNEL).await?;
        // Anything committed while we were not listening is gone; connected clients refetch.
        self.broadcast(resync_payload());
        loop {
            if self.inner.closed.load(Ordering::Acquire) {
                return Ok(());
            }
            match listener.try_recv().await? {
                Some(notification) => {
                    match serde_json::from_str::<Notification>(notification.payload()) {
                        Ok(event) => {
                            if let Err(error) = self.dispatch(pool, event).await {
                                tracing::warn!(?error, "direct message event dropped; resyncing");
                                self.broadcast(resync_payload());
                            }
                        }
                        Err(_) => tracing::warn!("malformed direct message notification"),
                    }
                }
                // The connection dropped; the next `try_recv` reconnects and re-listens.
                None => self.broadcast(resync_payload()),
            }
        }
    }

    /// Builds each connected member's view of the event with one query, then fans it out.
    async fn dispatch(&self, pool: &PgPool, event: Notification) -> Result<(), sqlx::Error> {
        let local = self.connected(&event.u);
        if local.is_empty() {
            return Ok(());
        }
        let members = sqlx::query(
            "SELECT m.user_id,m.last_read_seq,greatest(c.last_seq-m.last_read_seq,0) AS unread,c.frozen,
               (SELECT coalesce(sum(greatest(c2.last_seq-m2.last_read_seq,0)),0)::bigint
                  FROM conversation_members m2 JOIN conversations c2 ON c2.id=m2.conversation_id
                 WHERE m2.user_id=m.user_id) AS total
             FROM conversation_members m JOIN conversations c ON c.id=m.conversation_id
             WHERE m.conversation_id=$1 AND m.user_id=ANY($2)",
        )
        .bind(event.c)
        .bind(&local)
        .fetch_all(pool)
        .await?;
        let message: Option<Value> = if event.k == "message" {
            let row = sqlx::query(
                "SELECT id,conversation_id,seq,author_id,body,attachments,created_at
                 FROM messages WHERE conversation_id=$1 AND seq=$2",
            )
            .bind(event.c)
            .bind(event.s)
            .fetch_optional(pool)
            .await?;
            match row {
                Some(row) => {
                    Some(serde_json::to_value(store::decode_message(&row)?).unwrap_or_default())
                }
                None => return Ok(()),
            }
        } else {
            None
        };
        for member in members {
            let uid: String = member.try_get("user_id")?;
            let mut payload = json!({
                "type": event.k,
                "conversationId": event.c,
                "lastReadSeq": member.try_get::<i64, _>("last_read_seq")?,
                "unreadCount": member.try_get::<i64, _>("unread")?,
                "unreadTotal": member.try_get::<i64, _>("total")?,
                "frozen": member.try_get::<bool, _>("frozen")?,
            });
            if let Some(message) = &message {
                payload["message"] = message.clone();
            }
            self.send(&uid, Arc::from(payload.to_string()));
        }
        Ok(())
    }
}

fn resync_payload() -> Payload {
    Arc::from(json!({"type": "resync"}).to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn stalled_connections_are_closed_instead_of_blocking() {
        let hub = Hub::default();
        let mut slow = hub.subscribe("a").unwrap();
        let mut fast = hub.subscribe("b").unwrap();
        for _ in 0..CONNECTION_BUFFER {
            hub.send("a", Arc::from("x"));
        }
        hub.send("a", Arc::from("overflow"));
        hub.send("b", Arc::from("y"));
        assert_eq!(fast.receiver.recv().await.as_deref(), Some("y"));
        let mut received = 0;
        while slow.receiver.recv().await.is_some() {
            received += 1;
        }
        assert_eq!(
            received, CONNECTION_BUFFER,
            "the stream ends after its buffer drains"
        );
        assert_eq!(hub.connection_count(), 1);
    }

    #[tokio::test]
    async fn dropping_a_subscription_unregisters_it_and_close_ends_streams() {
        let hub = Hub::default();
        let first = hub.subscribe("a").unwrap();
        let mut second = hub.subscribe("a").unwrap();
        drop(first);
        assert_eq!(hub.connection_count(), 1);
        hub.close();
        assert!(second.receiver.recv().await.is_none());
        assert!(hub.subscribe("a").is_none());
    }

    #[tokio::test]
    async fn the_oldest_connection_gives_way_beyond_the_per_user_cap() {
        let hub = Hub::default();
        let mut subscriptions: Vec<_> = (0..MAX_CONNECTIONS_PER_USER)
            .map(|_| hub.subscribe("a").unwrap())
            .collect();
        let _newest = hub.subscribe("a").unwrap();
        assert!(subscriptions[0].receiver.recv().await.is_none());
        assert_eq!(hub.connection_count(), MAX_CONNECTIONS_PER_USER);
        subscriptions.clear();
    }
}
