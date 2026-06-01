-- CreateTable
CREATE TABLE "ManagerNotification" (
    "id" TEXT NOT NULL,
    "wsType" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "body" TEXT NOT NULL,
    "envelope" JSONB NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ManagerNotification_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ManagerNotificationDelivery" (
    "id" TEXT NOT NULL,
    "notificationId" TEXT NOT NULL,
    "staffUsername" TEXT NOT NULL,
    "channel" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ManagerNotificationDelivery_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "PushDevice" (
    "id" TEXT NOT NULL,
    "staffUsername" TEXT NOT NULL,
    "fcmToken" TEXT NOT NULL,
    "platform" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "PushDevice_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "ManagerNotificationDelivery_staffUsername_idx" ON "ManagerNotificationDelivery"("staffUsername");

-- CreateIndex
CREATE UNIQUE INDEX "ManagerNotificationDelivery_notificationId_staffUsername_key" ON "ManagerNotificationDelivery"("notificationId", "staffUsername");

-- CreateIndex
CREATE UNIQUE INDEX "PushDevice_fcmToken_key" ON "PushDevice"("fcmToken");

-- CreateIndex
CREATE INDEX "PushDevice_staffUsername_idx" ON "PushDevice"("staffUsername");

-- AddForeignKey
ALTER TABLE "ManagerNotificationDelivery" ADD CONSTRAINT "ManagerNotificationDelivery_notificationId_fkey" FOREIGN KEY ("notificationId") REFERENCES "ManagerNotification"("id") ON DELETE CASCADE ON UPDATE CASCADE;
