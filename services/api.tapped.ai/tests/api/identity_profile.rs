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
async fn identity_email_changes_update_the_profile_without_side_effects_or_baseline_replay() {
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
        sqlx::query_scalar::<_, String>("SELECT email FROM users WHERE id='user'")
            .fetch_one(&pool)
            .await
            .unwrap(),
        "updated@example.test"
    );
    assert_eq!(
        sqlx::query_scalar::<_, i64>(
            "SELECT count(*) FROM external_effect_outbox WHERE kind NOT IN ('auth_signup','auth_delete')"
        )
        .fetch_one(&pool)
        .await
        .unwrap(),
        0,
        "no profile sync or welcome messages for an email change"
    );
    cleanup(pool, admin, name).await;
}
#[tokio::test]
async fn failed_profile_update_rolls_back_identity_capture_and_skips_inactive_profiles() {
    let Some((pool, admin, name)) = database().await else {
        return;
    };
    sqlx::query("INSERT INTO users(id,username,email,unclaimed,deleted) VALUES('user','user','old@example.test',false,false),('unclaimed','unclaimed','old@example.test',true,false),('deleted','deleted','old@example.test',false,true)").execute(&pool).await.unwrap();
    sqlx::query("ALTER TABLE users ADD CONSTRAINT reject_email_for_test CHECK(email<>'new@example.test') NOT VALID").execute(&pool).await.unwrap();
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
    // Inactive profiles keep their email, so the rejecting constraint is never hit.
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
        sqlx::query_scalar::<_, i64>("SELECT count(*) FROM users WHERE email='old@example.test'")
            .fetch_one(&pool)
            .await
            .unwrap(),
        3
    );
    cleanup(pool, admin, name).await;
}
