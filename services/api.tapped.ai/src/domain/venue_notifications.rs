//! Durable jobs behind `POST /app/v1/opportunity-venue-notifications`.
//!
//! The handler validates the request and records a job in the mail store, then returns. Composing
//! the email (an LLM call per venue), queueing it for mail-worker, the Stream mirror and Slack all
//! happen here, off the request path. Jobs survive restarts: a claimed job holds a lease, and a
//! job whose lease expires (the process died mid-job) is claimed again. Each venue's email has an
//! `event_id` derived from the job, so a retried job never queues a second email for a venue.

use async_trait::async_trait;
use chrono::Utc;
use futures::{StreamExt, future::join_all};
use rusqlite::{Connection, OptionalExtension, params};
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{
    collections::{HashMap, HashSet},
    time::Duration,
};
use uuid::Uuid;

use super::{
    mail_bridge::{
        EmailThread, InMemoryMailStore, QueuedEmail, SqliteMailStore, StreamDelivery, notify_slack,
    },
    mail_composer::{ComposeVenueEmail, OpportunityContext},
    models::{booking::Booking, opportunity::Opportunity, user::UserModel},
};
use crate::state::AppStateDyn;

/// A repeat of the same request within this window returns the original job instead of a new one.
pub const IDEMPOTENCY_WINDOW: Duration = Duration::from_secs(24 * 60 * 60);
/// Attempts before a job is marked `failed`. Backoff between attempts is 30s, doubling, capped at 1h.
pub const MAX_ATTEMPTS: u32 = 8;
/// How long a claimed job is reserved before another claim may take it over.
const LEASE: Duration = Duration::from_secs(10 * 60);
const POLL_INTERVAL: Duration = Duration::from_secs(5);
const CLAIM_BATCH: usize = 8;
const VENUE_CONCURRENCY: usize = 4;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum JobStatus {
    /// Waiting to run, or waiting to retry after a failed attempt.
    Queued,
    /// A worker is composing and queueing the emails.
    Processing,
    /// Emails are queued for every venue that should get one; mail-worker delivers them.
    Completed,
    /// Gave up after the maximum number of attempts.
    Failed,
}

impl JobStatus {
    fn as_str(self) -> &'static str {
        match self {
            Self::Queued => "queued",
            Self::Processing => "processing",
            Self::Completed => "completed",
            Self::Failed => "failed",
        }
    }

    fn parse(value: &str) -> anyhow::Result<Self> {
        Ok(match value {
            "queued" => Self::Queued,
            "processing" => Self::Processing,
            "completed" => Self::Completed,
            "failed" => Self::Failed,
            other => anyhow::bail!("unknown venue notification job status {other:?}"),
        })
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct VenueNotificationJob {
    pub id: String,
    pub performer_id: String,
    pub idempotency_key: String,
    pub opportunity_ids: Vec<String>,
    pub note: String,
    pub status: JobStatus,
    pub attempts: u32,
    pub venues_notified: Option<usize>,
    pub last_error: Option<String>,
    /// When a queued job may next run, or when a processing job's lease expires (unix seconds).
    pub available_at: i64,
    pub created_at: i64,
}

impl VenueNotificationJob {
    pub fn new(
        performer_id: String,
        idempotency_key: String,
        opportunity_ids: Vec<String>,
        note: String,
    ) -> Self {
        let now = Utc::now().timestamp();
        Self {
            id: Uuid::new_v4().to_string(),
            performer_id,
            idempotency_key,
            opportunity_ids,
            note,
            status: JobStatus::Queued,
            attempts: 0,
            venues_notified: None,
            last_error: None,
            available_at: now,
            created_at: now,
        }
    }
}

/// A stable key for "the same request": the client's `Idempotency-Key` when it sends one,
/// otherwise the performer, the set of opportunities and the note.
pub fn idempotency_key(
    performer_id: &str,
    client_key: Option<&str>,
    opportunity_ids: &[String],
    note: &str,
) -> String {
    let mut hasher = Sha256::new();
    hasher.update(performer_id.as_bytes());
    hasher.update([0]);
    match client_key {
        Some(key) => {
            hasher.update(b"client:");
            hasher.update(key.as_bytes());
        }
        None => {
            let mut ids: Vec<&str> = opportunity_ids.iter().map(String::as_str).collect();
            ids.sort_unstable();
            ids.dedup();
            for id in ids {
                hasher.update(id.as_bytes());
                hasher.update([0]);
            }
            hasher.update([0]);
            hasher.update(note.as_bytes());
        }
    }
    hex::encode(hasher.finalize())
}

fn backoff_seconds(attempts: u32) -> i64 {
    (30_i64 << attempts.min(7)).min(3_600)
}

/// Job persistence. Implemented by both mail stores so jobs share the durable SQLite file that
/// mail-worker drains.
#[async_trait]
pub trait VenueNotificationJobs: Send + Sync {
    /// Records `job`, unless the performer already has a job with the same idempotency key created
    /// at or after `dedupe_since`. Returns whichever job is on record.
    async fn enqueue_venue_notification(
        &self,
        job: VenueNotificationJob,
        dedupe_since: i64,
    ) -> anyhow::Result<VenueNotificationJob>;
    async fn venue_notification(&self, id: &str) -> anyhow::Result<Option<VenueNotificationJob>>;
    /// Leases up to `limit` due jobs and counts the attempt.
    async fn claim_venue_notifications(
        &self,
        limit: usize,
    ) -> anyhow::Result<Vec<VenueNotificationJob>>;
    async fn complete_venue_notification(
        &self,
        id: &str,
        venues_notified: usize,
    ) -> anyhow::Result<()>;
    /// Schedules a retry with backoff, or marks the job `failed` after [`MAX_ATTEMPTS`].
    async fn fail_venue_notification(&self, id: &str, error: &str) -> anyhow::Result<()>;
    async fn outbound_exists(&self, event_id: &str) -> anyhow::Result<bool>;
}

#[async_trait]
impl VenueNotificationJobs for InMemoryMailStore {
    async fn enqueue_venue_notification(
        &self,
        job: VenueNotificationJob,
        dedupe_since: i64,
    ) -> anyhow::Result<VenueNotificationJob> {
        let mut jobs = self.venue_notification_jobs.lock().unwrap();
        if let Some(existing) = jobs.iter().find(|existing| {
            existing.performer_id == job.performer_id
                && existing.idempotency_key == job.idempotency_key
                && existing.created_at >= dedupe_since
        }) {
            return Ok(existing.clone());
        }
        jobs.push(job.clone());
        Ok(job)
    }

    async fn venue_notification(&self, id: &str) -> anyhow::Result<Option<VenueNotificationJob>> {
        Ok(self
            .venue_notification_jobs
            .lock()
            .unwrap()
            .iter()
            .find(|job| job.id == id)
            .cloned())
    }

    async fn claim_venue_notifications(
        &self,
        limit: usize,
    ) -> anyhow::Result<Vec<VenueNotificationJob>> {
        let now = Utc::now().timestamp();
        let mut jobs = self.venue_notification_jobs.lock().unwrap();
        let mut claimed = Vec::new();
        for job in jobs.iter_mut() {
            if !matches!(job.status, JobStatus::Queued | JobStatus::Processing)
                || job.available_at > now
            {
                continue;
            }
            if job.attempts >= MAX_ATTEMPTS {
                job.status = JobStatus::Failed;
                continue;
            }
            if claimed.len() == limit {
                break;
            }
            job.status = JobStatus::Processing;
            job.attempts += 1;
            job.available_at = now + LEASE.as_secs() as i64;
            claimed.push(job.clone());
        }
        Ok(claimed)
    }

    async fn complete_venue_notification(
        &self,
        id: &str,
        venues_notified: usize,
    ) -> anyhow::Result<()> {
        if let Some(job) = self
            .venue_notification_jobs
            .lock()
            .unwrap()
            .iter_mut()
            .find(|job| job.id == id)
        {
            job.status = JobStatus::Completed;
            job.venues_notified = Some(venues_notified);
            job.last_error = None;
        }
        Ok(())
    }

    async fn fail_venue_notification(&self, id: &str, error: &str) -> anyhow::Result<()> {
        if let Some(job) = self
            .venue_notification_jobs
            .lock()
            .unwrap()
            .iter_mut()
            .find(|job| job.id == id)
        {
            job.last_error = Some(error.to_owned());
            if job.attempts >= MAX_ATTEMPTS {
                job.status = JobStatus::Failed;
            } else {
                job.status = JobStatus::Queued;
                job.available_at = Utc::now().timestamp() + backoff_seconds(job.attempts);
            }
        }
        Ok(())
    }

    async fn outbound_exists(&self, event_id: &str) -> anyhow::Result<bool> {
        Ok(self
            .outbound()
            .iter()
            .any(|email| email.event_id == event_id))
    }
}

pub(crate) fn migrate(connection: &Connection) -> rusqlite::Result<()> {
    connection.execute_batch(
        "CREATE TABLE IF NOT EXISTS venue_notification_jobs (
           id TEXT PRIMARY KEY, performer_id TEXT NOT NULL, idempotency_key TEXT NOT NULL,
           opportunity_ids TEXT NOT NULL, note TEXT NOT NULL, status TEXT NOT NULL,
           attempts INTEGER NOT NULL DEFAULT 0, venues_notified INTEGER, last_error TEXT,
           available_at INTEGER NOT NULL, created_at INTEGER NOT NULL
         );
         CREATE INDEX IF NOT EXISTS venue_notification_jobs_idempotency
           ON venue_notification_jobs(performer_id, idempotency_key, created_at);
         CREATE INDEX IF NOT EXISTS venue_notification_jobs_due
           ON venue_notification_jobs(status, available_at);",
    )
}

const JOB_COLUMNS: &str = "id,performer_id,idempotency_key,opportunity_ids,note,status,attempts,\
                           venues_notified,last_error,available_at,created_at";

fn decode_job(row: &rusqlite::Row<'_>) -> rusqlite::Result<(VenueNotificationJob, String, String)> {
    let job = VenueNotificationJob {
        id: row.get(0)?,
        performer_id: row.get(1)?,
        idempotency_key: row.get(2)?,
        opportunity_ids: vec![],
        note: row.get(4)?,
        status: JobStatus::Queued,
        attempts: row.get(6)?,
        venues_notified: row.get::<_, Option<i64>>(7)?.map(|count| count as usize),
        last_error: row.get(8)?,
        available_at: row.get(9)?,
        created_at: row.get(10)?,
    };
    Ok((job, row.get(3)?, row.get(5)?))
}

fn finish_decode(
    (mut job, opportunity_ids, status): (VenueNotificationJob, String, String),
) -> anyhow::Result<VenueNotificationJob> {
    job.opportunity_ids = serde_json::from_str(&opportunity_ids)?;
    job.status = JobStatus::parse(&status)?;
    Ok(job)
}

fn select_job(connection: &Connection, id: &str) -> anyhow::Result<Option<VenueNotificationJob>> {
    connection
        .query_row(
            &format!("SELECT {JOB_COLUMNS} FROM venue_notification_jobs WHERE id=?1"),
            params![id],
            decode_job,
        )
        .optional()?
        .map(finish_decode)
        .transpose()
}

#[async_trait]
impl VenueNotificationJobs for SqliteMailStore {
    async fn enqueue_venue_notification(
        &self,
        job: VenueNotificationJob,
        dedupe_since: i64,
    ) -> anyhow::Result<VenueNotificationJob> {
        let mut connection = self.connection.lock().unwrap();
        let transaction = connection.transaction()?;
        let existing = transaction
            .query_row(
                &format!(
                    "SELECT {JOB_COLUMNS} FROM venue_notification_jobs
                     WHERE performer_id=?1 AND idempotency_key=?2 AND created_at>=?3
                     ORDER BY created_at LIMIT 1"
                ),
                params![job.performer_id, job.idempotency_key, dedupe_since],
                decode_job,
            )
            .optional()?;
        if let Some(existing) = existing {
            return finish_decode(existing);
        }
        transaction.execute(
            &format!(
                "INSERT INTO venue_notification_jobs ({JOB_COLUMNS})
                 VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11)"
            ),
            params![
                job.id,
                job.performer_id,
                job.idempotency_key,
                serde_json::to_string(&job.opportunity_ids)?,
                job.note,
                job.status.as_str(),
                job.attempts,
                job.venues_notified.map(|count| count as i64),
                job.last_error,
                job.available_at,
                job.created_at,
            ],
        )?;
        transaction.commit()?;
        Ok(job)
    }

    async fn venue_notification(&self, id: &str) -> anyhow::Result<Option<VenueNotificationJob>> {
        select_job(&self.connection.lock().unwrap(), id)
    }

    async fn claim_venue_notifications(
        &self,
        limit: usize,
    ) -> anyhow::Result<Vec<VenueNotificationJob>> {
        let now = Utc::now().timestamp();
        let mut connection = self.connection.lock().unwrap();
        let transaction = connection.transaction()?;
        // A job that used up its attempts and then lost its lease (crashed mid-attempt) is done.
        transaction.execute(
            "UPDATE venue_notification_jobs SET status='failed'
             WHERE status='processing' AND available_at<=?1 AND attempts>=?2",
            params![now, MAX_ATTEMPTS],
        )?;
        let ids: Vec<String> = {
            let mut statement = transaction.prepare(
                "SELECT id FROM venue_notification_jobs
                 WHERE status IN ('queued','processing') AND available_at<=?1
                 ORDER BY available_at LIMIT ?2",
            )?;
            statement
                .query_map(params![now, limit as i64], |row| row.get(0))?
                .collect::<Result<_, _>>()?
        };
        let mut claimed = Vec::with_capacity(ids.len());
        for id in ids {
            transaction.execute(
                "UPDATE venue_notification_jobs
                 SET status='processing',attempts=attempts+1,available_at=?1 WHERE id=?2",
                params![now + LEASE.as_secs() as i64, id],
            )?;
            claimed.extend(select_job(&transaction, &id)?);
        }
        transaction.commit()?;
        Ok(claimed)
    }

    async fn complete_venue_notification(
        &self,
        id: &str,
        venues_notified: usize,
    ) -> anyhow::Result<()> {
        self.connection.lock().unwrap().execute(
            "UPDATE venue_notification_jobs
             SET status='completed',venues_notified=?1,last_error=NULL WHERE id=?2",
            params![venues_notified as i64, id],
        )?;
        Ok(())
    }

    async fn fail_venue_notification(&self, id: &str, error: &str) -> anyhow::Result<()> {
        let connection = self.connection.lock().unwrap();
        let Some(job) = select_job(&connection, id)? else {
            return Ok(());
        };
        let (status, available_at) = if job.attempts >= MAX_ATTEMPTS {
            (JobStatus::Failed, job.available_at)
        } else {
            (
                JobStatus::Queued,
                Utc::now().timestamp() + backoff_seconds(job.attempts),
            )
        };
        connection.execute(
            "UPDATE venue_notification_jobs SET status=?1,available_at=?2,last_error=?3 WHERE id=?4",
            params![status.as_str(), available_at, error, id],
        )?;
        Ok(())
    }

    async fn outbound_exists(&self, event_id: &str) -> anyhow::Result<bool> {
        Ok(self
            .connection
            .lock()
            .unwrap()
            .query_row(
                "SELECT 1 FROM email_outbox WHERE event_id=?1",
                params![event_id],
                |_| Ok(()),
            )
            .optional()?
            .is_some())
    }
}

/// Polls for due jobs (new, retrying, or with an expired lease) until the process exits.
pub async fn run_worker(state: AppStateDyn) {
    loop {
        match process_due(&state).await {
            Ok(0) => tokio::time::sleep(POLL_INTERVAL).await,
            Ok(_) => {}
            Err(error) => {
                tracing::error!(?error, "failed to claim venue notification jobs");
                tokio::time::sleep(POLL_INTERVAL).await;
            }
        }
    }
}

/// Claims and runs one batch of due jobs; returns how many were claimed. A performer's jobs run
/// one after another, in claim order, so two jobs for the same venue share one email thread.
pub async fn process_due(state: &AppStateDyn) -> anyhow::Result<usize> {
    let jobs = state
        .mail
        .store
        .claim_venue_notifications(CLAIM_BATCH)
        .await?;
    let claimed = jobs.len();
    let mut by_performer: Vec<Vec<&VenueNotificationJob>> = Vec::new();
    for job in &jobs {
        match by_performer
            .iter_mut()
            .find(|group| group[0].performer_id == job.performer_id)
        {
            Some(group) => group.push(job),
            None => by_performer.push(vec![job]),
        }
    }
    let groups: Vec<_> = by_performer
        .into_iter()
        .map(|group| async move {
            for job in group {
                run_job(state, job).await;
            }
        })
        .collect();
    join_all(groups).await;
    Ok(claimed)
}

async fn run_job(state: &AppStateDyn, job: &VenueNotificationJob) {
    let result = match notify_venues(state, job).await {
        Ok(venues_notified) => {
            tracing::info!(
                job_id = job.id,
                venues_notified,
                "venue notification job completed"
            );
            state
                .mail
                .store
                .complete_venue_notification(&job.id, venues_notified)
                .await
        }
        Err(error) => {
            tracing::warn!(
                ?error,
                job_id = job.id,
                attempt = job.attempts,
                "venue notification job failed"
            );
            state
                .mail
                .store
                .fail_venue_notification(&job.id, &format!("{error:#}"))
                .await
        }
    };
    if let Err(error) = result {
        tracing::error!(
            ?error,
            job_id = job.id,
            "failed to record venue notification job result"
        );
    }
}

struct VenueOpportunities<'a> {
    opportunities: Vec<&'a Opportunity>,
    other_performers: Vec<String>,
}

fn push_unique(names: &mut Vec<String>, name: &str) {
    if !name.is_empty() && !names.iter().any(|existing| existing == name) {
        names.push(name.to_owned());
    }
}

/// Emails every unclaimed venue behind the job's opportunities. Returns how many venues have an
/// email queued for this job, including ones queued by an earlier attempt.
async fn notify_venues(state: &AppStateDyn, job: &VenueNotificationJob) -> anyhow::Result<usize> {
    let database = &state.database;
    let (performer, opportunities) = futures::join!(
        database.get_user_by_id(&job.performer_id),
        join_all(
            job.opportunity_ids
                .iter()
                .map(|id| database.get_opportunity_by_id(id))
        ),
    );
    let performer = performer?;
    if performer.username.is_empty() {
        tracing::warn!(job_id = job.id, "performer has no username; skipping job");
        return Ok(0);
    }
    let opportunities: Vec<Opportunity> = opportunities
        .into_iter()
        .filter_map(Result::ok)
        .filter(|opportunity| opportunity.user_id != job.performer_id)
        .filter(|opportunity| opportunity.reference_event_id.is_some())
        .collect();

    let reference_ids: HashSet<&str> = opportunities
        .iter()
        .filter_map(|opportunity| opportunity.reference_event_id.as_deref())
        .collect();
    let reference_ids: Vec<&str> = reference_ids.into_iter().collect();
    let booking_lookups: Vec<_> = reference_ids
        .iter()
        .map(|reference_id| database.get_bookings_by_reference_event_id(reference_id))
        .collect();
    let bookings: HashMap<&str, Vec<Booking>> = reference_ids
        .iter()
        .copied()
        .zip(join_all(booking_lookups).await)
        .filter_map(|(reference_id, bookings)| Some((reference_id, bookings.ok()?)))
        .collect();

    let mut by_venue: HashMap<String, Vec<&Opportunity>> = HashMap::new();
    let mut user_ids: HashSet<String> = HashSet::new();
    for opportunity in &opportunities {
        let Some(bookings) = opportunity
            .reference_event_id
            .as_deref()
            .and_then(|reference_id| bookings.get(reference_id))
        else {
            continue;
        };
        let Some(venue_id) = bookings
            .iter()
            .find_map(|booking| booking.requester_id.as_deref())
        else {
            continue;
        };
        by_venue
            .entry(venue_id.to_owned())
            .or_default()
            .push(opportunity);
        user_ids.insert(venue_id.to_owned());
        user_ids.extend(bookings.iter().map(|booking| booking.requestee_id.clone()));
    }
    let user_ids: Vec<String> = user_ids.into_iter().collect();
    let user_lookups: Vec<_> = user_ids
        .iter()
        .map(|id| database.get_user_by_id(id))
        .collect();
    let users: HashMap<String, UserModel> = user_ids
        .iter()
        .cloned()
        .zip(join_all(user_lookups).await)
        .filter_map(|(id, user)| Some((id, user.ok()?)))
        .collect();

    let venues: Vec<(String, VenueOpportunities<'_>)> = by_venue
        .into_iter()
        .map(|(venue_id, opportunities)| {
            let mut other_performers = Vec::new();
            for booking in opportunities
                .iter()
                .filter_map(|opportunity| bookings.get(opportunity.reference_event_id.as_deref()?))
                .flatten()
            {
                if let Some(user) = users.get(&booking.requestee_id) {
                    push_unique(&mut other_performers, user.display_name());
                }
            }
            (
                venue_id,
                VenueOpportunities {
                    opportunities,
                    other_performers,
                },
            )
        })
        .collect();

    let sends: Vec<_> = venues
        .iter()
        .filter_map(|(venue_id, context)| {
            let venue = users.get(venue_id)?;
            Some(notify_venue(
                state, job, &performer, venue_id, venue, context,
            ))
        })
        .collect();
    let results: Vec<anyhow::Result<bool>> = futures::stream::iter(sends)
        .buffer_unordered(VENUE_CONCURRENCY)
        .collect()
        .await;

    let mut venues_notified = 0;
    let mut first_error = None;
    for result in results {
        match result {
            Ok(true) => venues_notified += 1,
            Ok(false) => {}
            Err(error) => {
                first_error.get_or_insert(error);
            }
        }
    }
    match first_error {
        Some(error) => Err(error),
        None => Ok(venues_notified),
    }
}

/// Returns whether an email to this venue is queued for the job.
async fn notify_venue(
    state: &AppStateDyn,
    job: &VenueNotificationJob,
    performer: &UserModel,
    venue_id: &str,
    venue: &UserModel,
    context: &VenueOpportunities<'_>,
) -> anyhow::Result<bool> {
    // Legacy email outreach was only sent to unclaimed venues.
    if !venue.is_unclaimed() {
        return Ok(false);
    }
    let Some(recipient) = venue.booking_email().map(str::to_owned) else {
        return Ok(false);
    };
    let event_id = format!("opportunity-notification:{}:{}", job.id, venue_id);
    let store = &state.mail.store;
    if store.outbound_exists(&event_id).await? {
        return Ok(true);
    }
    let existing = store.thread_for_stream(&job.performer_id, venue_id).await?;
    if existing.is_none()
        && let Some(auto_reply) = venue.auto_reply()
    {
        if let Err(error) = state
            .mail
            .stream
            .send_message(&StreamDelivery {
                event_id: format!("venue-auto-reply:{}:{}", job.performer_id, venue_id),
                thread_id: String::new(),
                sender_id: venue_id.to_owned(),
                receiver_id: job.performer_id.clone(),
                text: auto_reply.to_owned(),
                frozen: true,
            })
            .await
        {
            tracing::warn!(?error, "failed to send venue auto-reply");
        }
        return Ok(false);
    }
    let previous_messages = match existing.as_ref() {
        Some(thread) => store.messages_for_thread(&thread.id).await?,
        None => vec![],
    };
    let composed = state
        .mail
        .composer
        .compose(ComposeVenueEmail {
            performer_display_name: performer.display_name().to_owned(),
            performer_username: performer.username.clone(),
            performer_genres: performer.performer_genres().to_vec(),
            performer_press_kit_url: performer.press_kit_url().map(str::to_owned),
            performer_social_links: performer.social_links(),
            venue_name: venue.display_name().to_owned(),
            note: job.note.clone(),
            opportunities: context
                .opportunities
                .iter()
                .map(|opportunity| OpportunityContext {
                    title: opportunity.title.clone(),
                    date: opportunity.start_time.format("%Y-%m-%d").to_string(),
                    other_performers: context.other_performers.clone(),
                })
                .collect(),
            previous_messages,
        })
        .await
        .map_err(|error| error.context("email composer"))?;
    let message_id = format!("<{}@{}>", Uuid::new_v4(), state.mail.booking_domain);
    let from = format!("{}@{}", performer.username, state.mail.booking_domain);
    let generated_body = composed.generated_body.clone();
    let is_new_thread = existing.is_none();
    let queued = if let Some(thread) = existing {
        store
            .enqueue_outbound(QueuedEmail {
                event_id,
                thread_id: thread.id,
                from,
                to: thread.recipients,
                cc: vec![],
                subject: thread.subject,
                text_body: composed.text_body,
                html_body: Some(composed.html_body),
                message_id,
                in_reply_to: thread.latest_message_id.clone(),
                references: thread.latest_message_id,
                attachments: vec![],
                encoded_attachments: vec![],
            })
            .await?
    } else {
        let thread_id = Uuid::new_v4().to_string();
        store
            .create_thread_and_enqueue(
                EmailThread {
                    id: thread_id.clone(),
                    performer_id: job.performer_id.clone(),
                    performer_username: performer.username.clone(),
                    venue_id: venue_id.to_owned(),
                    recipients: vec![recipient.clone()],
                    subject: composed.subject.clone(),
                    latest_message_id: message_id.clone(),
                },
                QueuedEmail {
                    event_id,
                    thread_id,
                    from,
                    to: vec![recipient],
                    cc: state.mail.founder_cc.clone(),
                    subject: composed.subject,
                    text_body: composed.text_body,
                    html_body: Some(composed.html_body),
                    message_id,
                    in_reply_to: String::new(),
                    references: String::new(),
                    attachments: vec![],
                    encoded_attachments: vec![],
                },
            )
            .await?
    };
    if !queued {
        // Raced with another attempt of this job, which owns the side effects.
        return Ok(true);
    }
    if is_new_thread
        && let Err(error) = state
            .mail
            .stream
            .send_message(&StreamDelivery {
                event_id: format!("venue-contact:{}:{}", job.performer_id, venue_id),
                thread_id: String::new(),
                sender_id: job.performer_id.clone(),
                receiver_id: venue_id.to_owned(),
                text: generated_body,
                frozen: true,
            })
            .await
    {
        tracing::warn!(?error, "failed to mirror venue contact to Stream");
    }
    notify_slack(
        state.mail.slack_webhook_url.as_deref(),
        "new venue contact email",
        &format!("{} => {}", performer.display_name(), venue.display_name()),
    )
    .await;
    Ok(true)
}
