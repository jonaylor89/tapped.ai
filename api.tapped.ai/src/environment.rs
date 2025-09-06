use color_eyre::eyre::{self, Result};

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Deserialize)]
pub enum Environment {
    Stage,
    Production,
}

impl Environment {
    #[must_use]
    pub fn as_str(&self) -> &'static str {
        match self {
            Environment::Stage => "stage",
            Environment::Production => "production",
        }
    }
}

impl TryFrom<String> for Environment {
    type Error = eyre::Error;

    fn try_from(s: String) -> Result<Self> {
        match s.to_lowercase().as_str() {
            "stage" => Ok(Self::Stage),
            "production" => Ok(Self::Production),
            other => Err(eyre::eyre!(
                "{} is not a supported environment. Use either `stage` or `production`",
                other
            )),
        }
    }
}
