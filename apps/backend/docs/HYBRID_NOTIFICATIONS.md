# Hybrid notifications (Socket.IO)

## Database

After pulling schema changes, run:

```bash
cd apps/backend
npx prisma migrate dev --name manager_hybrid_notifications
```

## Server environment

No Firebase configuration is required.

## Behaviour

- Events are delivered over Socket.IO when the client is connected.

## Flutter

No Firebase configuration is required.

## API

No push registration endpoints are required.
