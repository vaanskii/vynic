export type WsEventType =
  | 'data_updated'
  | 'orders_bulk_touch'
  | 'tables_bulk_touch'
  | 'order_created'
  | 'order_updated'
  | 'order_cancelled'
  | 'order_closed'
  | 'takeaway_created'
  | 'takeaway_deleted'
  | 'table_updated'
  | 'staff_sync'
  | 'audit_updated'
  | 'day_closed'
  | 'heartbeat';

export interface WsEvent<T = unknown> {
  type: WsEventType;
  payload: T;
  timestamp: string;
  notificationId?: string;
}

export interface BroadcastOptions {
  excludeSocketIds?: string[];
}
