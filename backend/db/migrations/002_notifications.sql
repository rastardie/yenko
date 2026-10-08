CREATE TABLE notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recipient_id TEXT NOT NULL REFERENCES users(id),
  type TEXT NOT NULL CHECK (char_length(type) BETWEEN 1 AND 120),
  title TEXT NOT NULL CHECK (char_length(title) BETWEEN 1 AND 160),
  body TEXT NOT NULL CHECK (char_length(body) BETWEEN 1 AND 600),
  trip_id UUID REFERENCES trips(id),
  reservation_id UUID REFERENCES reservations(id),
  read_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX notifications_recipient_created_idx
  ON notifications (recipient_id, created_at DESC);

CREATE INDEX notifications_unread_idx
  ON notifications (recipient_id, created_at DESC)
  WHERE read_at IS NULL;
