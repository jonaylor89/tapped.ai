use super::external_effects::{cleanup, database};
use tapped_api_rs::{
    data::google_identity::Account,
    domain::{
        auth_lifecycle::{self, LifecycleEvent, LifecycleKind},
        identity_worker::capture_account,
    },
};
fn account(uid: &str, email: &str) -> Account {
    Account {
        local_id: uid.into(),
        email: email.into(),
        display_name: "Name".into(),
        created_at: "1234".into(),
    }
}
#[tokio::test]
async fn identity_email_changes_enqueue_profile_updates_atomically_without_introductions_or_baseline_replay()
 {
    let Some((pool, admin, name)) = database().await else {
        return;
    };
    sqlx::query("INSERT INTO users(id,username,email) VALUES('user','user','old@example.test')")
        .execute(&pool)
        .await
        .unwrap();
    let a = account("user", "new@example.test");
    capture_account(&pool, &a, uuid::Uuid::new_v4(), false)
        .await
        .unwrap();
    capture_account(&pool, &a, uuid::Uuid::new_v4(), false)
        .await
        .unwrap();
    let jobs: Vec<(String, serde_json::Value)> =
        sqlx::query_as("SELECT kind,payload FROM external_effect_outbox")
            .fetch_all(&pool)
            .await
            .unwrap();
    assert_eq!(jobs.len(), 1);
    assert_eq!(jobs[0].0, "stream_profile");
    assert_eq!(jobs[0].1, serde_json::json!({"uid":"user","created":false}));
    assert_eq!(
        sqlx::query_scalar::<_, String>("SELECT email FROM users WHERE id='user'")
            .fetch_one(&pool)
            .await
            .unwrap(),
        "new@example.test"
    );
    // A repeat signup hook and scanner share the same normalized-email synchronization path.
    let updated = account("user", "updated@example.test");
    auth_lifecycle::receive(
        &pool,
        &LifecycleEvent {
            kind: LifecycleKind::Signup,
            account: updated.clone(),
        },
    )
    .await
    .unwrap();
    auth_lifecycle::receive(
        &pool,
        &LifecycleEvent {
            kind: LifecycleKind::Signup,
            account: updated,
        },
    )
    .await
    .unwrap();
    assert_eq!(
        sqlx::query_scalar::<_, i64>(
            "SELECT count(*) FROM external_effect_outbox WHERE kind='stream_profile'"
        )
        .fetch_one(&pool)
        .await
        .unwrap(),
        2
    );
    cleanup(pool, admin, name).await;
}
#[tokio::test]
async fn failed_profile_queue_capture_rolls_back_identity_and_email_and_skips_inactive_profiles() {
    let Some((pool, admin, name)) = database().await else {
        return;
    };
    sqlx::query("INSERT INTO users(id,username,email,unclaimed,deleted) VALUES('user','user','old@example.test',false,false),('unclaimed','unclaimed','old@example.test',true,false),('deleted','deleted','old@example.test',false,true)").execute(&pool).await.unwrap();
    sqlx::query("ALTER TABLE external_effect_outbox ADD CONSTRAINT reject_profile_for_test CHECK(kind<>'stream_profile')").execute(&pool).await.unwrap();
    assert!(
        capture_account(
            &pool,
            &account("user", "new@example.test"),
            uuid::Uuid::new_v4(),
            false
        )
        .await
        .is_err()
    );
    assert_eq!(
        sqlx::query_scalar::<_, String>("SELECT email FROM users WHERE id='user'")
            .fetch_one(&pool)
            .await
            .unwrap(),
        "old@example.test"
    );
    assert_eq!(
        sqlx::query_scalar::<_, i64>("SELECT count(*) FROM firebase_identities WHERE uid='user'")
            .fetch_one(&pool)
            .await
            .unwrap(),
        0
    );
    for uid in ["unclaimed", "deleted"] {
        capture_account(
            &pool,
            &account(uid, "new@example.test"),
            uuid::Uuid::new_v4(),
            false,
        )
        .await
        .unwrap();
    }
    assert_eq!(
        sqlx::query_scalar::<_, i64>("SELECT count(*) FROM external_effect_outbox")
            .fetch_one(&pool)
            .await
            .unwrap(),
        0
    );
    cleanup(pool, admin, name).await;
}
