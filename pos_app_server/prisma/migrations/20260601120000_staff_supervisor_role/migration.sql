-- Add supervisor; migrate legacy admin accounts to manager.
ALTER TYPE "StaffRole" ADD VALUE IF NOT EXISTS 'SUPERVISOR';

UPDATE "Staff" SET "role" = 'MANAGER' WHERE "role" = 'ADMIN';
