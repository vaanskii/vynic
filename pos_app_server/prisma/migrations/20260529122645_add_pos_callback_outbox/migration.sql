-- CreateTable
CREATE TABLE "PosCallbackOutbox" (
    "id" TEXT NOT NULL,
    "endpoint" TEXT NOT NULL,
    "payload" JSONB NOT NULL,
    "posOrderId" INTEGER,
    "dedupeKey" TEXT,
    "status" TEXT NOT NULL DEFAULT 'pending',
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "maxAttempts" INTEGER NOT NULL DEFAULT 20,
    "lastError" TEXT,
    "nextAttemptAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "PosCallbackOutbox_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "PosCallbackOutbox_status_nextAttemptAt_idx" ON "PosCallbackOutbox"("status", "nextAttemptAt");

-- CreateIndex
CREATE INDEX "PosCallbackOutbox_posOrderId_idx" ON "PosCallbackOutbox"("posOrderId");

-- CreateIndex
CREATE INDEX "PosCallbackOutbox_dedupeKey_idx" ON "PosCallbackOutbox"("dedupeKey");
