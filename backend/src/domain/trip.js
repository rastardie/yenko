import { badRequest } from './errors.js';

const maxTextLength = 120;
const normalizeText = (value, field) => {
  if (typeof value !== 'string') throw badRequest(`${field} must be text.`);
  const normalized = value.trim().replace(/\s+/g, ' ');
  if (!normalized) throw badRequest(`${field} is required.`);
  if (normalized.length > maxTextLength) {
    throw badRequest(`${field} must be at most ${maxTextLength} characters.`);
  }
  return normalized;
};

const boundedInteger = (value, field, minimum, maximum) => {
  if (!Number.isInteger(value) || value < minimum || value > maximum) {
    throw badRequest(`${field} must be a whole number from ${minimum} to ${maximum}.`);
  }
  return value;
};

export function validateTripDraft(input) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) {
    throw badRequest('A JSON trip payload is required.');
  }

  const departureAt = new Date(input.departureAt);
  if (Number.isNaN(departureAt.getTime()) || departureAt <= new Date()) {
    throw badRequest('departureAt must be a future ISO-8601 timestamp.');
  }

  return {
    from: normalizeText(input.from, 'from'),
    to: normalizeText(input.to, 'to'),
    pickupJunction: normalizeText(input.pickupJunction, 'pickupJunction'),
    departureAt: departureAt.toISOString(),
    seatsAvailable: boundedInteger(input.seatsAvailable, 'seatsAvailable', 1, 4),
    pricePerSeat: boundedInteger(input.pricePerSeat, 'pricePerSeat', 1, 1000),
    isWomenOnly: input.isWomenOnly === true,
  };
}

export function validateSeatRequest(input) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) {
    throw badRequest('A JSON reservation payload is required.');
  }
  return { seats: boundedInteger(input.seats, 'seats', 1, 4) };
}

const boundedNumber = (value, field, minimum, maximum, { optional = false } = {}) => {
  if (optional && (value === undefined || value === null)) return null;
  if (typeof value !== 'number' || !Number.isFinite(value) || value < minimum || value > maximum) {
    throw badRequest(`${field} must be a number from ${minimum} to ${maximum}.`);
  }
  return value;
};

/** A single GPS fix reported by the driver's device while a trip is under way. */
export function validateLiveLocation(input) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) {
    throw badRequest('A JSON location payload is required.');
  }
  return {
    latitude: boundedNumber(input.latitude, 'latitude', -90, 90),
    longitude: boundedNumber(input.longitude, 'longitude', -180, 180),
    speedKmh: boundedNumber(input.speedKmh, 'speedKmh', 0, 300, { optional: true }),
    heading: boundedNumber(input.heading, 'heading', 0, 360, { optional: true }),
  };
}

export function toPublicTrip(trip) {
  return {
    id: trip.id,
    driver: {
      displayName: trip.driver.displayName,
      rating: trip.driver.rating,
      completedTrips: trip.driver.completedTrips,
      verificationStatus: trip.driver.verificationStatus,
    },
    vehicle: {
      description: trip.vehicle.description,
      verificationStatus: trip.vehicle.verificationStatus,
    },
    from: trip.from,
    to: trip.to,
    pickupJunction: trip.pickupJunction,
    departureAt: trip.departureAt,
    seatsAvailable: trip.seatsAvailable,
    pricePerSeat: trip.pricePerSeat,
    isWomenOnly: trip.isWomenOnly,
    status: trip.status,
  };
}
