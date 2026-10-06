//! Outbound HTTP. Every upstream call goes through a client with connect and total timeouts so a
//! slow provider can't hold a request (or the mail worker) open indefinitely.

use std::{sync::OnceLock, time::Duration};

use reqwest::Client;

pub const CONNECT_TIMEOUT: Duration = Duration::from_secs(5);
pub const DEFAULT_TIMEOUT: Duration = Duration::from_secs(20);

/// The shared client for ordinary API calls (Google, Spotify, Stream, Slack, Typesense).
pub fn client() -> Client {
    static CLIENT: OnceLock<Client> = OnceLock::new();
    CLIENT
        .get_or_init(|| client_with_timeout(DEFAULT_TIMEOUT))
        .clone()
}

/// A client for calls that are expected to take longer, e.g. LLM completions or downloads.
pub fn client_with_timeout(timeout: Duration) -> Client {
    Client::builder()
        .connect_timeout(CONNECT_TIMEOUT)
        .timeout(timeout)
        .user_agent(concat!("tapped-api/", env!("CARGO_PKG_VERSION")))
        .build()
        .expect("reqwest client configuration is static")
}
