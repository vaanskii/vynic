# Backend Codex Adapter

This directory is the modular NestJS/Prisma/PostgreSQL backend. Follow the
root `AGENTS.md` first. For backend-local work, read the current project state
and only the backend section of `docs/agent-state/VYNIC_CODE_MAP.md`, then open
the identified implementation and nearby tests. Do not broaden discovery when
the code map identifies the authoritative files.

## Local Boundaries

- Application wiring starts at `src/app.module.ts`; persistence starts at
  `prisma/schema.prisma` and `prisma/migrations/`.
- Resolve tenant context from a server-owned relationship: Device for POS,
  Staff for Manager, Host/VenueDomain for website, or booking identity for
  payment callbacks. Client-supplied tenant IDs are never authority.
- `PlatformUser` uses the separate `/platform/*` authentication and audit
  boundary.
- POS -> Cloud snapshots and Cloud -> Edge commands are different flows. The
  legacy callback client/outbox is a frozen fallback for unenrolled Venues.
- Controllers validate/authenticate and delegate; domain and tenant rules belong
  in the existing authoritative service.
- Keep errors explicit. Do not turn failures into `null`, false success, or
  empty catches.

Consult only the relevant sections of
`docs/agent-skills/VYNIC_FULLSTACK_ENGINEERING.md` when schema, security,
compatibility, or migration rules govern the requested work. Read the full
document only for a genuinely cross-stack architecture or audit task.

Validate only the backend surfaces changed. Schema work additionally requires
Prisma validation and migration evidence against a disposable database when
existing data or constraints matter.
