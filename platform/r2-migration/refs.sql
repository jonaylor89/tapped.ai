-- Every Firebase Storage URL in Postgres as table, column, row id, url (read-only). See platform/R2_MIGRATION.md.
BEGIN READ ONLY;
COPY (
  SELECT 'opportunities','flier_url',id::text,flier_url FROM opportunities WHERE flier_url ~ 'appspot|firebasestorage'
  UNION ALL SELECT 'bookings','flier_url',id::text,flier_url FROM bookings WHERE flier_url ~ 'appspot|firebasestorage'
  UNION ALL SELECT 'users','profile_picture',id::text,profile_picture FROM users WHERE profile_picture ~ 'appspot|firebasestorage'
  UNION ALL SELECT 'users','profile',id::text,m[1] FROM users, regexp_matches(profile::text, '(https://[^"]*(?:appspot\.com|firebasestorage)[^"]*)', 'g') m
  UNION ALL SELECT 'legacy_profile_archive','profile',ctid::text,m[1] FROM legacy_profile_archive, regexp_matches(profile::text, '(https://[^"]*(?:appspot\.com|firebasestorage)[^"]*)', 'g') m
  UNION ALL SELECT 'legacy_invalid_records','original_record',ctid::text,m[1] FROM legacy_invalid_records, regexp_matches(original_record::text, '(https://[^"]*(?:appspot\.com|firebasestorage)[^"]*)', 'g') m
) TO STDOUT WITH (FORMAT csv, DELIMITER E'\t');
ROLLBACK;
