export function commercialActions(
  status: string,
  managed: boolean,
): string[][] {
  switch (status) {
    case "NO_PLAN":
      return [
        ["TRIAL", "Start Trial"],
        ["GRANT_ACTIVE", "Assign paid plan"],
      ];
    case "TRIAL":
      return [
        ["EXTEND_TRIAL", "Extend Trial"],
        ["END_TRIAL", "End Trial now"],
        ["GRANT_ACTIVE", "Convert to paid"],
        ["SUSPEND", "Suspend"],
      ];
    case "ACTIVE":
      return managed
        ? [
            ["QUOTE", "Upgrade / change plan"],
            ["SCHEDULE_CHANGE", "Schedule downgrade"],
            ["SCHEDULE_CANCEL", "Cancel at renewal"],
            ["SUSPEND", "Suspend"],
          ]
        : [
            ["GRANT_ACTIVE", "Confirm paid agreement"],
            ["SUSPEND", "Suspend"],
          ];
    case "PAST_DUE":
      return [
        ["QUOTE", "Confirm renewal"],
        ["SUSPEND", "Suspend"],
      ];
    case "SUSPENDED":
      return [
        ["RESUME", "Resume"],
        ["CANCEL_NOW", "Cancel"],
      ];
    case "CANCELLED":
      return [["GRANT_ACTIVE", "Assign new plan"]];
    default:
      return [];
  }
}
