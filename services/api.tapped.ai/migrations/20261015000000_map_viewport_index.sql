-- Match the geometry bounding-box predicate used by the bundled public map endpoint.
-- The existing geography index remains for ST_DWithin/radius search.
CREATE INDEX users_map_location_idx ON users USING gist ((location::geometry))
    WHERE NOT deleted AND NOT shadow_banned AND location IS NOT NULL;
