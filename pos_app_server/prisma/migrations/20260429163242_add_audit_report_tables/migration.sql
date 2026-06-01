-- CreateTable
CREATE TABLE "AuditReport" (
    "id" TEXT NOT NULL,
    "reportId" TEXT NOT NULL,
    "posOrderId" INTEGER NOT NULL,
    "tableNumbers" TEXT[],
    "floor" TEXT NOT NULL DEFAULT 'first',
    "openedById" TEXT NOT NULL,
    "openedByName" TEXT NOT NULL,
    "openedAt" TIMESTAMP(3) NOT NULL,
    "status" TEXT NOT NULL,
    "closedAt" TIMESTAMP(3),
    "closedById" TEXT,
    "closedByName" TEXT,
    "locked" BOOLEAN NOT NULL DEFAULT false,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "AuditReport_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AuditEvent" (
    "id" TEXT NOT NULL,
    "reportId" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "itemName" TEXT NOT NULL,
    "previousQty" INTEGER NOT NULL,
    "newQty" INTEGER NOT NULL,
    "waiterId" TEXT NOT NULL,
    "waiterName" TEXT NOT NULL,
    "eventTime" TIMESTAMP(3) NOT NULL,
    "note" TEXT,
    "seq" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "AuditEvent_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "AuditReport_reportId_key" ON "AuditReport"("reportId");

-- CreateIndex
CREATE INDEX "AuditReport_posOrderId_idx" ON "AuditReport"("posOrderId");

-- CreateIndex
CREATE INDEX "AuditReport_status_idx" ON "AuditReport"("status");

-- CreateIndex
CREATE INDEX "AuditEvent_reportId_idx" ON "AuditEvent"("reportId");

-- AddForeignKey
ALTER TABLE "AuditEvent" ADD CONSTRAINT "AuditEvent_reportId_fkey" FOREIGN KEY ("reportId") REFERENCES "AuditReport"("id") ON DELETE CASCADE ON UPDATE CASCADE;
