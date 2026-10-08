CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE users (
  id TEXT PRIMARY KEY CHECK (char_length(id) BETWEEN 3 AND 128),
  display_name TEXT NOT NULL CHECK (char_length(display_name) BETWEEN 1 AND 120),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE trips (
  id UUID PRIMARY KEY,
  driver_id TEXT NOT NULL REFERENCES users(id),
  driver_rating NUMERIC(2, 1) NOT NULL DEFAULT 0 CHECK (driver_rating BETWEEN 0 AND 5),
  driver_completed_trips INTEGER NOT NULL DEFAULT 0 CHECK (driver_completed_trips >= 0),
  driver_verification_status TEXT NOT NULL DEFAULT 'pending' CHECK (driver_verification_status IN ('pending', 'verified', 'rejected', 'demo')),
  vehicle_description TEXT NOT NULL CHECK (char_length(vehicle_description) BETWEEN 1 AND 120),
  vehicle_verification_status TEXT NOT NULL DEFAULT 'pending' CHECK (vehicle_verification_status IN ('pending', 'verified', 'rejected', 'demo')),
  origin_name TEXT NOT NULL CHECK (char_length(origin_name) BETWEEN 1 AND 120),
  destination_name TEXT NOT NULL CHECK (char_length(destination_name) BETWEEN 1 AND 120),
  pickup_junction TEXT NOT NULL CHECK (char_length(pickup_junction) BETWEEN 1 AND 120),
  departure_at TIMESTAMPTZ NOT NULL,
  seats_available SMALLINT NOT NULL CHECK (seats_available BETWEEN 0 AND 4),
  price_per_seat INTEGER NOT NULL CHECK (price_per_seat BETWEEN 1 AND 1000),
  is_women_only BOOLEAN NOT NULL DEFAULT false,
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'cancelled', 'completed')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX trips_open_departure_idx
  ON trips (departure_at)
  WHERE status = 'open' AND seats_available > 0;

CREATE TABLE reservations (
  id UUID PRIMARY KEY,
  trip_id UUID NOT NULL REFERENCES trips(id),
  passenger_id TEXT NOT NULL REFERENCES users(id),
  seats SMALLINT NOT NULL CHECK (seats BETWEEN 1 AND 4),
  status TEXT NOT NULL DEFAULT 'requested' CHECK (status IN ('requested', 'confirmed', 'cancelled', 'expired')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX reservations_trip_status_idx ON reservations (trip_id, status);
CREATE INDEX reservations_passenger_idx ON reservations (passenger_id, created_at DESC);

CREATE TABLE idempotency_keys (
  actor_id TEXT NOT NULL REFERENCES users(id),
  route TEXT NOT NULL CHECK (char_length(route) BETWEEN 1 AND 200),
  key TEXT NOT NULL CHECK (char_length(key) BETWEEN 8 AND 128),
  reservation_id UUID NOT NULL REFERENCES reservations(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (actor_id, route, key)
);

CREATE TABLE audit_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id TEXT REFERENCES users(id),
  action TEXT NOT NULL CHECK (char_length(action) BETWEEN 1 AND 120),
  aggregate_type TEXT NOT NULL CHECK (char_length(aggregate_type) BETWEEN 1 AND 80),
  aggregate_id TEXT NOT NULL CHECK (char_length(aggregate_id) BETWEEN 1 AND 128),
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE outbox_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_type TEXT NOT NULL CHECK (char_length(event_type) BETWEEN 1 AND 120),
  aggregate_type TEXT NOT NULL CHECK (char_length(aggregate_type) BETWEEN 1 AND 80),
  aggregate_id TEXT NOT NULL CHECK (char_length(aggregate_id) BETWEEN 1 AND 128),
  payload JSONB NOT NULL,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  published_at TIMESTAMPTZ,
  attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0)
);

CREATE INDEX outbox_unpublished_idx ON outbox_events (occurred_at) WHERE published_at IS NULL;
