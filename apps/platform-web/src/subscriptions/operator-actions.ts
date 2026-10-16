export function commercialActions(
  status: string,
  managed: boolean,
  suspension?: { from?: string | null; trialExpired?: boolean },
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
      if (managed)
        return [
          ["RESUME", "Resume"],
          ["CANCEL_NOW", "Cancel"],
        ];
      // An expired Trial cannot be resumed as-is: reactivate it with a new end
      // date, replace it with a new Trial, or assign a paid plan.
      return suspension?.from === "TRIAL" && suspension.trialExpired
        ? [
            ["EXTEND_TRIAL", "Extend Trial and reactivate"],
            ["TRIAL", "Start new Trial"],
            ["GRANT_ACTIVE", "Assign paid plan"],
            ["CANCEL_NOW", "Cancel"],
          ]
        : [
            ["RESUME", "Resume"],
            ["TRIAL", "Start new Trial"],
            ["GRANT_ACTIVE", "Assign paid plan"],
            ["CANCEL_NOW", "Cancel"],
          ];
    case "CANCELLED":
      return [
        ["TRIAL", "Start Trial"],
        ["GRANT_ACTIVE", "Assign new plan"],
      ];
    default:
      return [];
  }
}
