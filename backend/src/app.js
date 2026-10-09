import { InMemoryTripRepository } from './infrastructure/in-memory-trip-repository.js';
import { DevelopmentActorResolver } from './infrastructure/development-actor-resolver.js';
import { OidcActorResolver } from './infrastructure/oidc-actor-resolver.js';
import { LocalAuthActorResolver } from './infrastructure/local-auth-actor-resolver.js';
import { createPostgresPool } from './infrastructure/postgres.js';
import { PostgresTripRepository } from './infrastructure/postgres-trip-repository.js';
import { PostgresUserRepository } from './infrastructure/postgres-user-repository.js';
import { PostgresAdminRepository } from './infrastructure/postgres-admin-repository.js';
import { PostgresWebAuthnRepository } from './infrastructure/postgres-webauthn-repository.js';
import { ConsoleMailSender } from './infrastructure/mail/console-mail-sender.js';
import { SocialProviderRegistry } from './infrastructure/social/social-provider-registry.js';
import { AdminService } from './application/admin-service.js';
import { TripService } from './application/trip-service.js';
import { AuthService } from './application/auth-service.js';
import { WebAuthnService } from './application/webauthn-service.js';
import { createHttpServer } from './interfaces/http-server.js';

const seedTrips = (now = new Date()) => [
  {
    id: 'trip-kwame',
    driver: { id: 'driver-kwame', displayName: 'Kwame Mensah', rating: 4.8, completedTrips: 32, verificationStatus: 'demo' },
    vehicle: { description: 'Toyota Corolla', verificationStatus: 'demo' },
    from: 'East Legon Hills', to: 'Circle', pickupJunction: 'Madina Market junction',
    departureAt: new Date(now.getTime() + 18 * 60_000).toISOString(), seatsAvailable: 3,
    pricePerSeat: 15, isWomenOnly: false, status: 'open', createdAt: now.toISOString(),
  },
  {
    id: 'trip-ama',
    driver: { id: 'driver-ama', displayName: 'Ama Owusu', rating: 4.9, completedTrips: 18, verificationStatus: 'demo' },
    vehicle: { description: 'Hyundai Elantra', verificationStatus: 'demo' },
    from: 'Adenta', to: 'Ridge', pickupJunction: '37 Station',
    departureAt: new Date(now.getTime() + 33 * 60_000).toISOString(), seatsAvailable: 2,
    pricePerSeat: 18, isWomenOnly: true, status: 'open', createdAt: now.toISOString(),
  },
];

export function createApp({ environment = 'development', actorResolver, tripRepository, authService, adminService, webauthnService, corsOrigins = [] } = {}) {
  const repository = tripRepository ?? new InMemoryTripRepository(seedTrips());
  const resolver = actorResolver ?? new DevelopmentActorResolver();
  if (
    environment === 'production' &&
    (repository instanceof InMemoryTripRepository || resolver instanceof DevelopmentActorResolver)
  ) {
    throw new Error('Production requires PostgreSQL persistence and real authentication (local-pin or OIDC).');
  }
  return createHttpServer({
    tripService: new TripService({ tripRepository: repository }),
    actorResolver: resolver,
    authService,
    adminService,
    webauthnService,
    corsOrigins,
  });
}

export async function createRuntimeApp({
  environment = 'development',
  databaseUrl,
  authMode = environment === 'production' ? 'oidc' : 'local-pin',
  jwtSecret,
  signupApproval = 'none',
  oidcIssuer, oidcAudience, oidcRolesClaim,
  enableEmailMailer = false,
  webauthnRpID,
  webauthnOrigin,
  corsOrigins = [],
  env = process.env,
} = {}) {
  const usesPostgres = Boolean(databaseUrl);
  if (environment === 'production' && !usesPostgres) throw new Error('DATABASE_URL is required in production.');
  const pool = usesPostgres ? createPostgresPool({ connectionString: databaseUrl }) : null;
  const repository = pool ? new PostgresTripRepository({ pool }) : new InMemoryTripRepository(seedTrips());

  if (environment === 'production' && authMode === 'development-header') {
    await pool?.end();
    throw new Error('Production cannot use AUTH_MODE=development-header.');
  }

  let actorResolver;
  let authService;
  let adminService;
  let webauthnService;
  if (authMode === 'oidc') {
    actorResolver = new OidcActorResolver({ issuer: oidcIssuer, audience: oidcAudience, rolesClaim: oidcRolesClaim });
  } else if (authMode === 'local-pin') {
    if (!pool) {
      throw new Error('AUTH_MODE=local-pin requires DATABASE_URL (sessions and users need durable storage).');
    }
    if (!jwtSecret) throw new Error('AUTH_MODE=local-pin requires JWT_SECRET.');
    const userRepository = new PostgresUserRepository({ pool });
    authService = new AuthService({
      userRepository,
      jwtSecret,
      signupApproval: signupApproval || 'none',
      mailSender: enableEmailMailer ? new ConsoleMailSender() : null,
      socialProviders: SocialProviderRegistry.fromEnv(env),
    });
    actorResolver = new LocalAuthActorResolver({ authService });
    adminService = new AdminService({
      adminRepository: new PostgresAdminRepository({ pool }),
      userRepository,
      authService,
    });
    // WebAuthn (PWA passkeys) is only meaningful once there is a real user
    // repository and session issuer to verify against; dark until an
    // rpID/origin pair is configured (both required — see server.js).
    if (webauthnRpID && webauthnOrigin) {
      webauthnService = new WebAuthnService({
        webauthnRepository: new PostgresWebAuthnRepository({ pool }),
        userRepository,
        authService,
        rpName: 'YɛnKɔ',
        rpID: webauthnRpID,
        origin: webauthnOrigin,
      });
    }
  } else {
    actorResolver = new DevelopmentActorResolver();
  }

  return {
    server: createApp({ environment, actorResolver, tripRepository: repository, authService, adminService, webauthnService, corsOrigins }),
    async close() { await repository.close?.(); },
  };
}
