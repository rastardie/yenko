-- Optional free-text home area/neighborhood, collected at signup so trip
-- discovery can eventually default to a rider's usual area. No structured
-- junction/stop reference data exists yet (unlike Onboard's seeded stops),
-- so this stays free text until that data model is built.
ALTER TABLE users
  ADD COLUMN home_area TEXT CHECK (home_area IS NULL OR char_length(home_area) BETWEEN 1 AND 120);
