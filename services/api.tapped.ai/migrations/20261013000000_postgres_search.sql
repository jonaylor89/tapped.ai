CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX users_search_text_idx ON users USING gin (
    (lower(artist_name || ' ' || username || ' ' || bio || ' ' ||
        coalesce(profile#>>'{performerInfo,label}','') || ' ' ||
        coalesce(profile#>>'{venueInfo,type}',''))) gin_trgm_ops
) WHERE NOT deleted AND NOT shadow_banned;
CREATE INDEX bookings_search_name_idx ON bookings USING gin ((lower(name)) gin_trgm_ops);
CREATE INDEX opportunities_search_text_idx ON opportunities USING gin ((lower(title || ' ' || description)) gin_trgm_ops)
    WHERE NOT deleted;
CREATE INDEX bookings_updated_search_idx ON bookings (updated_at DESC,id);
CREATE INDEX opportunities_updated_search_idx ON opportunities (updated_at DESC,id);
