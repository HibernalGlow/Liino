//! No-op `arboard` replacement installed through `[patch.crates-io]`.
//!
//! MicYou's core depends on `arboard` only for its plugin clipboard API, but
//! the real crate has no Android backend and fails to compile there. liino does
//! not expose plugin clipboard access, so every call reports "unavailable"
//! instead of pulling a desktop-only dependency into the Android build.
//!
//! Replacing this with the real crate would require upstream to make `arboard`
//! optional (see `docs/migration/upstream-reuse.md`).

#[derive(Debug)]
pub struct Error(String);

impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for Error {}

pub type Result<T> = std::result::Result<T, Error>;

pub struct Clipboard;

impl Clipboard {
    pub fn new() -> Result<Self> {
        Err(unsupported())
    }

    pub fn get_text(&mut self) -> Result<String> {
        Err(unsupported())
    }

    pub fn set_text(&mut self, _text: String) -> Result<()> {
        Err(unsupported())
    }
}

fn unsupported() -> Error {
    Error("clipboard is unavailable in liino builds".to_string())
}
