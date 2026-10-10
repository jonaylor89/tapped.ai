-- Review IDs were reused when legacy accounts were transferred. The reviewee's collection path
-- is part of document identity, so preserve it as well as type. Source import supplies it explicitly.
ALTER TABLE reviews ADD COLUMN reviewee_id text;
UPDATE reviews SET reviewee_id = CASE WHEN review_type='performer' THEN performer_id ELSE booker_id END;
ALTER TABLE reviews ALTER COLUMN reviewee_id SET NOT NULL;
ALTER TABLE reviews DROP CONSTRAINT reviews_pkey;
ALTER TABLE reviews ADD PRIMARY KEY (id,review_type,reviewee_id);
CREATE OR REPLACE VIEW api_reviews AS SELECT id, review_type,
    profile || jsonb_build_object('id',id,'bookerId',booker_id,'performerId',performer_id,
    'bookingId',booking_id,'timestamp',occurred_at,'overallRating',overall_rating,
    'overallReview',overall_review,'type',review_type) AS doc, reviewee_id FROM reviews;
