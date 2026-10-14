-- Native clients decode booking activities with a required fromUserId. Reminders delivered
-- before this fix (and imported legacy reminders) had none; name the other booking party.
UPDATE activities a
SET from_user_id = CASE WHEN b.requester_id = a.to_user_id THEN b.requestee_id ELSE b.requester_id END
FROM bookings b
WHERE a.activity_type = 'bookingReminder'
  AND a.from_user_id IS NULL
  AND b.id = a.booking_id
  AND nullif(CASE WHEN b.requester_id = a.to_user_id THEN b.requestee_id ELSE b.requester_id END, '') IS NOT NULL;
