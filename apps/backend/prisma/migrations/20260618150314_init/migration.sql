-- CreateSchema
CREATE SCHEMA IF NOT EXISTS "pos";

-- CreateSchema
CREATE SCHEMA IF NOT EXISTS "website";

-- CreateEnum
CREATE TYPE "pos"."StaffRole" AS ENUM ('MANAGER', 'SUPERVISOR', 'WAITER', 'ADMIN');

-- CreateEnum
CREATE TYPE "website"."WebsiteUserRole" AS ENUM ('USER', 'SUPER_ADMIN');

-- CreateEnum
CREATE TYPE "website"."WebsiteReservationStatus" AS ENUM ('PENDING', 'CONFIRMED', 'FAILED', 'COMPLETED');

-- CreateTable
CREATE TABLE "pos"."Table" (
    "id" TEXT NOT NULL,
    "tableNumber" TEXT NOT NULL,
    "floor" TEXT NOT NULL,
    "isReserved" BOOLEAN NOT NULL DEFAULT false,
    "activeOrderId" INTEGER,
    "currentBill" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Table_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "pos"."Order" (
    "id" TEXT NOT NULL,
    "posOrderId" INTEGER NOT NULL,
    "status" TEXT NOT NULL,
    "totalAmount" DOUBLE PRECISION NOT NULL,
    "guestCount" INTEGER NOT NULL DEFAULT 0,
    "waiterName" TEXT NOT NULL,
    "floor" TEXT NOT NULL DEFAULT '',
    "businessDate" TEXT NOT NULL DEFAULT '',
    "customerName" TEXT NOT NULL DEFAULT '',
    "customerPhone" TEXT NOT NULL DEFAULT '',
    "pickupTime" TEXT NOT NULL DEFAULT '',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "paymentType" TEXT NOT NULL DEFAULT 'cash',
    "discountAmount" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "includeServiceFee" BOOLEAN NOT NULL DEFAULT false,
    "serviceFeePercent" DOUBLE PRECISION NOT NULL DEFAULT 10,

    CONSTRAINT "Order_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "pos"."OrderItem" (
    "id" TEXT NOT NULL,
    "orderId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "quantity" INTEGER NOT NULL,
    "price" DOUBLE PRECISION NOT NULL,

    CONSTRAINT "OrderItem_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "pos"."MenuCategory" (
    "id" TEXT NOT NULL,
    "slug" TEXT NOT NULL,
    "nameKa" TEXT NOT NULL,
    "nameEn" TEXT NOT NULL,
    "sendToKitchen" BOOLEAN NOT NULL DEFAULT true,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "MenuCategory_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "pos"."MenuSubcategory" (
    "id" TEXT NOT NULL,
    "slug" TEXT NOT NULL,
    "nameKa" TEXT NOT NULL,
    "nameEn" TEXT NOT NULL,
    "categoryId" TEXT NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "MenuSubcategory_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "pos"."MenuItem" (
    "id" TEXT NOT NULL,
    "categoryId" TEXT,
    "nameKa" TEXT NOT NULL,
    "nameEn" TEXT NOT NULL,
    "price" DOUBLE PRECISION NOT NULL,
    "sendToKitchen" BOOLEAN NOT NULL DEFAULT true,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "subcategoryId" TEXT,

    CONSTRAINT "MenuItem_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "pos"."MenuItemVariant" (
    "id" TEXT NOT NULL,
    "menuItemId" TEXT NOT NULL,
    "size" DOUBLE PRECISION NOT NULL,
    "price" DOUBLE PRECISION NOT NULL,

    CONSTRAINT "MenuItemVariant_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "pos"."Expense" (
    "id" TEXT NOT NULL,
    "description" TEXT NOT NULL,
    "amount" DOUBLE PRECISION NOT NULL,
    "category" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "paymentType" TEXT NOT NULL DEFAULT 'cash',

    CONSTRAINT "Expense_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "pos"."Staff" (
    "id" TEXT NOT NULL,
    "username" TEXT NOT NULL,
    "pinHash" TEXT NOT NULL,
    "role" "pos"."StaffRole" NOT NULL DEFAULT 'WAITER',
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Staff_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "pos"."AuditReport" (
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
CREATE TABLE "pos"."AuditEvent" (
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

-- CreateTable
CREATE TABLE "pos"."AuditEventLog" (
    "id" TEXT NOT NULL,
    "action" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "data" JSONB NOT NULL,
    "deviceType" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AuditEventLog_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "pos"."DailySnapshot" (
    "id" TEXT NOT NULL,
    "date" TEXT NOT NULL,
    "totalRevenue" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "orderCount" INTEGER NOT NULL DEFAULT 0,
    "avgOrderValue" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "cashRevenue" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "cardRevenue" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "totalExpenses" DOUBLE PRECISION NOT NULL DEFAULT 0,
    "topItemsJson" TEXT NOT NULL DEFAULT '[]',
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "DailySnapshot_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "pos"."QuickOrderDraft" (
    "id" TEXT NOT NULL,
    "draftId" TEXT NOT NULL,
    "displayName" TEXT,
    "subtotal" DOUBLE PRECISION NOT NULL,
    "serviceFeeAmount" DOUBLE PRECISION NOT NULL,
    "total" DOUBLE PRECISION NOT NULL,
    "includeServiceFee" BOOLEAN NOT NULL DEFAULT false,
    "serviceFeeRate" DOUBLE PRECISION NOT NULL DEFAULT 0.1,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdBy" TEXT NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "QuickOrderDraft_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "pos"."QuickOrderDraftItem" (
    "id" TEXT NOT NULL,
    "draftId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "quantity" INTEGER NOT NULL,
    "price" DOUBLE PRECISION NOT NULL,
    "comment" TEXT,

    CONSTRAINT "QuickOrderDraftItem_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "pos"."Setting" (
    "key" TEXT NOT NULL,
    "value" TEXT NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Setting_pkey" PRIMARY KEY ("key")
);

-- CreateTable
CREATE TABLE "pos"."ManagerNotification" (
    "id" TEXT NOT NULL,
    "wsType" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "body" TEXT NOT NULL,
    "envelope" JSONB NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ManagerNotification_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "pos"."ManagerNotificationDelivery" (
    "id" TEXT NOT NULL,
    "notificationId" TEXT NOT NULL,
    "staffUsername" TEXT NOT NULL,
    "channel" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ManagerNotificationDelivery_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "pos"."PushDevice" (
    "id" TEXT NOT NULL,
    "staffUsername" TEXT NOT NULL,
    "fcmToken" TEXT NOT NULL,
    "platform" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "PushDevice_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "pos"."PosCallbackOutbox" (
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

-- CreateTable
CREATE TABLE "website"."users" (
    "id" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "email" TEXT,
    "password" TEXT NOT NULL,
    "firstName" TEXT,
    "lastName" TEXT,
    "phone" TEXT NOT NULL,
    "role" "website"."WebsiteUserRole" NOT NULL DEFAULT 'USER',
    "hashedRefreshToken" TEXT,

    CONSTRAINT "users_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "website"."tables" (
    "id" SERIAL NOT NULL,
    "websiteTableNumber" TEXT NOT NULL,
    "posTableNumber" TEXT NOT NULL,
    "posFloor" TEXT NOT NULL,
    "capacity" INTEGER NOT NULL DEFAULT 4,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "tables_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "website"."reservations" (
    "id" TEXT NOT NULL,
    "userId" TEXT,
    "customerName" TEXT,
    "customerEmail" TEXT,
    "customerPhone" TEXT,
    "date" TIMESTAMP(3) NOT NULL,
    "timeSlot" TEXT NOT NULL,
    "status" "website"."WebsiteReservationStatus" NOT NULL DEFAULT 'PENDING',
    "totalAmount" DOUBLE PRECISION,
    "menuItems" TEXT,
    "paymentId" TEXT,
    "paymentStatus" TEXT,
    "notes" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "reservations_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "website"."reservation_tables" (
    "id" SERIAL NOT NULL,
    "reservationId" TEXT NOT NULL,
    "tableId" INTEGER NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "reservation_tables_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "Table_tableNumber_floor_key" ON "pos"."Table"("tableNumber", "floor");

-- CreateIndex
CREATE UNIQUE INDEX "Order_posOrderId_key" ON "pos"."Order"("posOrderId");

-- CreateIndex
CREATE INDEX "OrderItem_orderId_idx" ON "pos"."OrderItem"("orderId");

-- CreateIndex
CREATE UNIQUE INDEX "MenuCategory_slug_key" ON "pos"."MenuCategory"("slug");

-- CreateIndex
CREATE UNIQUE INDEX "MenuSubcategory_slug_categoryId_key" ON "pos"."MenuSubcategory"("slug", "categoryId");

-- CreateIndex
CREATE INDEX "MenuItem_categoryId_idx" ON "pos"."MenuItem"("categoryId");

-- CreateIndex
CREATE INDEX "MenuItem_subcategoryId_idx" ON "pos"."MenuItem"("subcategoryId");

-- CreateIndex
CREATE INDEX "MenuItemVariant_menuItemId_idx" ON "pos"."MenuItemVariant"("menuItemId");

-- CreateIndex
CREATE UNIQUE INDEX "Staff_username_key" ON "pos"."Staff"("username");

-- CreateIndex
CREATE UNIQUE INDEX "AuditReport_reportId_key" ON "pos"."AuditReport"("reportId");

-- CreateIndex
CREATE INDEX "AuditReport_posOrderId_idx" ON "pos"."AuditReport"("posOrderId");

-- CreateIndex
CREATE INDEX "AuditReport_status_idx" ON "pos"."AuditReport"("status");

-- CreateIndex
CREATE INDEX "AuditEvent_reportId_idx" ON "pos"."AuditEvent"("reportId");

-- CreateIndex
CREATE INDEX "AuditEventLog_createdAt_idx" ON "pos"."AuditEventLog"("createdAt");

-- CreateIndex
CREATE INDEX "AuditEventLog_action_idx" ON "pos"."AuditEventLog"("action");

-- CreateIndex
CREATE UNIQUE INDEX "DailySnapshot_date_key" ON "pos"."DailySnapshot"("date");

-- CreateIndex
CREATE UNIQUE INDEX "QuickOrderDraft_draftId_key" ON "pos"."QuickOrderDraft"("draftId");

-- CreateIndex
CREATE INDEX "QuickOrderDraftItem_draftId_idx" ON "pos"."QuickOrderDraftItem"("draftId");

-- CreateIndex
CREATE INDEX "ManagerNotificationDelivery_staffUsername_idx" ON "pos"."ManagerNotificationDelivery"("staffUsername");

-- CreateIndex
CREATE UNIQUE INDEX "ManagerNotificationDelivery_notificationId_staffUsername_key" ON "pos"."ManagerNotificationDelivery"("notificationId", "staffUsername");

-- CreateIndex
CREATE UNIQUE INDEX "PushDevice_fcmToken_key" ON "pos"."PushDevice"("fcmToken");

-- CreateIndex
CREATE INDEX "PushDevice_staffUsername_idx" ON "pos"."PushDevice"("staffUsername");

-- CreateIndex
CREATE INDEX "PosCallbackOutbox_status_nextAttemptAt_idx" ON "pos"."PosCallbackOutbox"("status", "nextAttemptAt");

-- CreateIndex
CREATE INDEX "PosCallbackOutbox_posOrderId_idx" ON "pos"."PosCallbackOutbox"("posOrderId");

-- CreateIndex
CREATE INDEX "PosCallbackOutbox_dedupeKey_idx" ON "pos"."PosCallbackOutbox"("dedupeKey");

-- CreateIndex
CREATE UNIQUE INDEX "users_email_key" ON "website"."users"("email");

-- CreateIndex
CREATE UNIQUE INDEX "users_phone_key" ON "website"."users"("phone");

-- CreateIndex
CREATE UNIQUE INDEX "tables_websiteTableNumber_key" ON "website"."tables"("websiteTableNumber");

-- CreateIndex
CREATE UNIQUE INDEX "reservation_tables_reservationId_tableId_key" ON "website"."reservation_tables"("reservationId", "tableId");

-- AddForeignKey
ALTER TABLE "pos"."OrderItem" ADD CONSTRAINT "OrderItem_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "pos"."Order"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."MenuSubcategory" ADD CONSTRAINT "MenuSubcategory_categoryId_fkey" FOREIGN KEY ("categoryId") REFERENCES "pos"."MenuCategory"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."MenuItem" ADD CONSTRAINT "MenuItem_categoryId_fkey" FOREIGN KEY ("categoryId") REFERENCES "pos"."MenuCategory"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."MenuItem" ADD CONSTRAINT "MenuItem_subcategoryId_fkey" FOREIGN KEY ("subcategoryId") REFERENCES "pos"."MenuSubcategory"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."MenuItemVariant" ADD CONSTRAINT "MenuItemVariant_menuItemId_fkey" FOREIGN KEY ("menuItemId") REFERENCES "pos"."MenuItem"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."AuditEvent" ADD CONSTRAINT "AuditEvent_reportId_fkey" FOREIGN KEY ("reportId") REFERENCES "pos"."AuditReport"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."QuickOrderDraftItem" ADD CONSTRAINT "QuickOrderDraftItem_draftId_fkey" FOREIGN KEY ("draftId") REFERENCES "pos"."QuickOrderDraft"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "pos"."ManagerNotificationDelivery" ADD CONSTRAINT "ManagerNotificationDelivery_notificationId_fkey" FOREIGN KEY ("notificationId") REFERENCES "pos"."ManagerNotification"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "website"."reservations" ADD CONSTRAINT "reservations_userId_fkey" FOREIGN KEY ("userId") REFERENCES "website"."users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "website"."reservation_tables" ADD CONSTRAINT "reservation_tables_reservationId_fkey" FOREIGN KEY ("reservationId") REFERENCES "website"."reservations"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "website"."reservation_tables" ADD CONSTRAINT "reservation_tables_tableId_fkey" FOREIGN KEY ("tableId") REFERENCES "website"."tables"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
