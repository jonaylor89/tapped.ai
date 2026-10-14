-- Durable replacement for the paused scheduled-writes extension. Private worker state.
CREATE TABLE booking_reminders (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 booking_id text NOT NULL,
 user_id text NOT NULL,
 start_time timestamptz NOT NULL,
 offset_seconds integer NOT NULL CHECK (offset_seconds IN (3600,86400,604800)),
 due_at timestamptz NOT NULL,
 delivered_at timestamptz,
 canceled_at timestamptz,
 UNIQUE (booking_id,user_id,start_time,offset_seconds)
);
CREATE INDEX booking_reminders_due ON booking_reminders(due_at,id)
 WHERE delivered_at IS NULL AND canceled_at IS NULL;

-- Only future delivery times are baselined; never replay historical reminders. The legacy
-- scheduler must remain paused until retirement, so both transports cannot deliver these.
INSERT INTO booking_reminders(booking_id,user_id,start_time,offset_seconds,due_at)
SELECT DISTINCT b.id,u.id,b.start_time,o.seconds,b.start_time-make_interval(secs=>o.seconds)
FROM bookings b
JOIN users u ON u.id IN (b.requester_id,b.requestee_id)
CROSS JOIN (VALUES (3600),(86400),(604800)) o(seconds)
WHERE b.status='confirmed' AND b.requester_id IS NOT NULL AND b.requester_id<>''
 AND NOT u.deleted AND NOT u.unclaimed
 AND b.start_time-make_interval(secs=>o.seconds)>now()
ON CONFLICT DO NOTHING;
