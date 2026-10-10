-- Two source profiles contain non-finite ratings encoded as strings. Keep their raw JSONB
-- unchanged, but expose an unrated/null value that all client/model decoders can represent.
CREATE FUNCTION api_profile_rating(info jsonb) RETURNS jsonb LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT CASE WHEN jsonb_typeof(info->'rating')='string'
        THEN info || jsonb_build_object('rating',
            CASE WHEN info->>'rating' ~ '^[-+]?[0-9]+([.][0-9]+)?$'
                AND length(info->>'rating') < 20
            THEN (info->>'rating')::double precision ELSE NULL END)
        ELSE info END;
$$;
CREATE OR REPLACE VIEW api_users AS
SELECT id, profile
    || jsonb_build_object('performerInfo',api_profile_rating(profile->'performerInfo'),
                         'bookerInfo',api_profile_rating(profile->'bookerInfo'))
    || jsonb_build_object('id', id, 'username', username, 'email', email, 'artistName', artist_name,
       'bio', bio, 'occupations', occupations, 'profilePicture', profile_picture, 'placeId', place_id,
       'deleted', deleted, 'shadowBanned', shadow_banned, 'unclaimed', unclaimed,
       'location', CASE WHEN location IS NULL THEN NULL ELSE jsonb_build_object(
           'lat',ST_Y(location::geometry),'lng',ST_X(location::geometry),'placeId',coalesce(place_id,'')) END)
    AS doc FROM users;
