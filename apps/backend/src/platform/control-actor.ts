export type ControlActor =
  | { platformUserId: string; customerAccountId?: never }
  | { customerAccountId: string; platformUserId?: never };
