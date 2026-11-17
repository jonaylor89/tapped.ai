-- The API orders a 1:1 pair by byte order (Rust `str` ordering), but the database collation
-- (en_US.utf8) orders mixed-case Firebase UIDs differently ("Zebra" < "apple" only bytewise), so
-- `CHECK (direct_low < direct_high)` rejected such pairs. Compare the pair columns bytewise.
ALTER TABLE conversations
    ALTER COLUMN direct_low TYPE text COLLATE "C",
    ALTER COLUMN direct_high TYPE text COLLATE "C";
