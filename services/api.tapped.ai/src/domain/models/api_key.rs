use ::serde::{Deserialize, Serialize};
use chrono::{DateTime, Utc};
use sha2::{Digest, Sha256};

/// A document in `apiKeys`, keyed by [`hash_api_key`] of the raw key. The raw key is never stored.
#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ApiKey {
    /// SHA-256 of the key (hex). Legacy documents hold the raw key and are rehashed on first use.
    pub key: String,
    pub user_id: String,

    #[serde(with = "firestore::serialize_as_timestamp")]
    pub timestamp: DateTime<Utc>,
}

const MAX_API_KEY_LEN: usize = 256;

pub fn hash_api_key(raw: &str) -> String {
    hex::encode(Sha256::digest(raw.as_bytes()))
}

/// Keys are only ever looked up as Firestore document IDs, so reject anything that isn't a
/// plain token before it reaches a document path.
pub fn is_well_formed_api_key(raw: &str) -> bool {
    !raw.is_empty()
        && raw.len() <= MAX_API_KEY_LEN
        && raw
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_'))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hashes_are_stable_hex() {
        assert_eq!(
            hash_api_key("test-key"),
            "62af8704764faf8ea82fc61ce9c4c3908b6cb97d463a634e9e587d7c885db0ef"
        );
    }

    #[test]
    fn rejects_keys_that_could_escape_the_document_path() {
        assert!(is_well_formed_api_key("tk_live_AbC-123"));
        assert!(!is_well_formed_api_key(""));
        assert!(!is_well_formed_api_key("abc/../users/x"));
        assert!(!is_well_formed_api_key("has space"));
        assert!(!is_well_formed_api_key(&"a".repeat(257)));
    }
}
