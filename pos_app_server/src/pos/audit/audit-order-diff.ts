export type AuditEventInput = {
  type: 'ADD_ITEM' | 'REDUCE_QTY' | 'DELETE_ITEM';
  itemName: string;
  previousQty: number;
  newQty: number;
  waiterId: string;
  waiterName: string;
  note?: string | null;
};

type LineItem = {
  itemKey: string;
  itemName: string;
  quantity: number;
};

function lineKey(name: string, unitPrice: number): string {
  return `${name}|${unitPrice.toFixed(4)}`;
}

function toLineItems(
  items: Array<{ name?: string; itemName?: string; quantity?: number; unitPrice?: number; price?: number }>,
): LineItem[] {
  return items.map((it) => {
    const name = (it.itemName ?? it.name ?? '').toString();
    const unitPrice = Number(it.unitPrice ?? it.price ?? 0);
    const quantity = Number(it.quantity ?? 0);
    return {
      itemKey: (it as { itemKey?: string }).itemKey?.toString() || lineKey(name, unitPrice),
      itemName: name,
      quantity,
    };
  });
}

export function buildAuditEventsForOrderDiff(params: {
  previousItems: Array<{ name?: string; itemName?: string; quantity?: number; unitPrice?: number; price?: number; itemKey?: string }>;
  updatedItems: Array<{ name?: string; itemName?: string; quantity?: number; unitPrice?: number; price?: number; itemKey?: string }>;
  performerId: string;
  performerName: string;
}): AuditEventInput[] {
  const previous = new Map<string, LineItem>();
  for (const item of toLineItems(params.previousItems)) {
    previous.set(item.itemKey, item);
  }
  const next = new Map<string, LineItem>();
  for (const item of toLineItems(params.updatedItems)) {
    next.set(item.itemKey, item);
  }

  const keys = new Set([...previous.keys(), ...next.keys()]);
  const events: AuditEventInput[] = [];
  const performerId = params.performerId.trim() || 'mobile';
  const performerName = params.performerName.trim() || performerId;

  for (const key of keys) {
    const prevItem = previous.get(key);
    const nextItem = next.get(key);
    const prevQty = prevItem?.quantity ?? 0;
    const newQty = nextItem?.quantity ?? 0;
    if (prevQty === newQty) continue;

    const itemName = nextItem?.itemName ?? prevItem?.itemName ?? 'Item';
    let type: AuditEventInput['type'];
    if (newQty <= 0) {
      type = 'DELETE_ITEM';
    } else if (prevQty === 0 || newQty > prevQty) {
      type = 'ADD_ITEM';
    } else {
      type = 'REDUCE_QTY';
    }

    events.push({
      type,
      itemName,
      previousQty: prevQty,
      newQty,
      waiterId: performerId,
      waiterName: performerName,
    });
  }

  return events;
}
