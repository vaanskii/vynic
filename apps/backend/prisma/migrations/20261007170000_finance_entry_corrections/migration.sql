-- Additive signed corrections. Original financial rows remain untouched.
ALTER TABLE pos."PayrollPayment" ADD COLUMN "reversalOfId" TEXT, ADD COLUMN "correctionBusinessDate" TEXT;
CREATE UNIQUE INDEX "PayrollPayment_reversalOfId_key" ON pos."PayrollPayment"("reversalOfId");
CREATE UNIQUE INDEX "PayrollPayment_venueId_payrollPeriodId_id_key" ON pos."PayrollPayment"("venueId", "payrollPeriodId", "id");
ALTER TABLE pos."PayrollPayment" ADD CONSTRAINT "PayrollPayment_reversalOf_fkey" FOREIGN KEY ("venueId", "payrollPeriodId", "reversalOfId") REFERENCES pos."PayrollPayment"("venueId", "payrollPeriodId", "id") ON DELETE RESTRICT ON UPDATE NO ACTION;
ALTER TABLE pos."PayrollPayment" ADD CONSTRAINT "PayrollPayment_correction_shape" CHECK (
  ("reversalOfId" IS NULL AND "correctionBusinessDate" IS NULL) OR
  ("reversalOfId" IS NOT NULL AND "reversalOfId" <> "id" AND "amount" < 0 AND
   "correctionBusinessDate" IS NOT NULL AND "notes" IS NOT NULL AND length(btrim("notes")) BETWEEN 1 AND 1000)
);
ALTER TABLE pos."ObligationReserveEntry" ADD COLUMN "reversalOfId" TEXT, ADD COLUMN "correctionBusinessDate" TEXT;
CREATE UNIQUE INDEX "ObligationReserveEntry_reversalOfId_key" ON pos."ObligationReserveEntry"("reversalOfId");
CREATE UNIQUE INDEX "ObligationReserveEntry_venueId_obligationCycleId_id_key" ON pos."ObligationReserveEntry"("venueId", "obligationCycleId", "id");
ALTER TABLE pos."ObligationReserveEntry" ADD CONSTRAINT "ObligationReserveEntry_reversalOf_fkey" FOREIGN KEY ("venueId", "obligationCycleId", "reversalOfId") REFERENCES pos."ObligationReserveEntry"("venueId", "obligationCycleId", "id") ON DELETE RESTRICT ON UPDATE NO ACTION;
ALTER TABLE pos."ObligationReserveEntry" ADD CONSTRAINT "ObligationReserveEntry_correction_shape" CHECK (
  ("reversalOfId" IS NULL AND "correctionBusinessDate" IS NULL) OR
  ("reversalOfId" IS NOT NULL AND "reversalOfId" <> "id" AND "amount" < 0 AND
   "correctionBusinessDate" IS NOT NULL AND "notes" IS NOT NULL AND length(btrim("notes")) BETWEEN 1 AND 1000)
);
ALTER TABLE pos."ObligationPayment" ADD COLUMN "reversalOfId" TEXT, ADD COLUMN "correctionBusinessDate" TEXT;
CREATE UNIQUE INDEX "ObligationPayment_reversalOfId_key" ON pos."ObligationPayment"("reversalOfId");
CREATE UNIQUE INDEX "ObligationPayment_venueId_obligationCycleId_id_key" ON pos."ObligationPayment"("venueId", "obligationCycleId", "id");
ALTER TABLE pos."ObligationPayment" ADD CONSTRAINT "ObligationPayment_reversalOf_fkey" FOREIGN KEY ("venueId", "obligationCycleId", "reversalOfId") REFERENCES pos."ObligationPayment"("venueId", "obligationCycleId", "id") ON DELETE RESTRICT ON UPDATE NO ACTION;
ALTER TABLE pos."ObligationPayment" ADD CONSTRAINT "ObligationPayment_correction_shape" CHECK (
  ("reversalOfId" IS NULL AND "correctionBusinessDate" IS NULL) OR
  ("reversalOfId" IS NOT NULL AND "reversalOfId" <> "id" AND "amount" < 0 AND
   "correctionBusinessDate" IS NOT NULL AND "notes" IS NOT NULL AND length(btrim("notes")) BETWEEN 1 AND 1000)
);
CREATE FUNCTION pos.validate_finance_reversal() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE original jsonb;
BEGIN
  IF NEW."reversalOfId" IS NULL THEN RETURN NEW; END IF;
  EXECUTE format('SELECT to_jsonb(t) FROM pos.%I t WHERE t.id = $1', TG_TABLE_NAME)
    INTO original USING NEW."reversalOfId";
  IF original IS NULL OR original->>'reversalOfId' IS NOT NULL OR
     (original->>'amount')::numeric <= 0 OR NEW.amount <> -(original->>'amount')::numeric OR
     NEW."businessDate" <> original->>'businessDate' THEN
    RAISE EXCEPTION 'Invalid original or signed finance correction' USING ERRCODE = '23514';
  END IF;
  IF TG_TABLE_NAME <> 'ObligationReserveEntry' AND
     to_jsonb(NEW)->>'paymentDate' IS DISTINCT FROM original->>'paymentDate' THEN
    RAISE EXCEPTION 'Correction must retain original payment date' USING ERRCODE = '23514';
  END IF;
  IF TG_TABLE_NAME = 'ObligationPayment' AND
     (to_jsonb(NEW)->>'reserveConsumed')::numeric <> -(original->>'reserveConsumed')::numeric THEN
    RAISE EXCEPTION 'Correction must restore original reserve consumption' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER "PayrollPayment_validate_correction" BEFORE INSERT ON pos."PayrollPayment" FOR EACH ROW EXECUTE FUNCTION pos.validate_finance_reversal();
CREATE TRIGGER "ObligationReserveEntry_validate_correction" BEFORE INSERT ON pos."ObligationReserveEntry" FOR EACH ROW EXECUTE FUNCTION pos.validate_finance_reversal();
CREATE TRIGGER "ObligationPayment_validate_correction" BEFORE INSERT ON pos."ObligationPayment" FOR EACH ROW EXECUTE FUNCTION pos.validate_finance_reversal();
