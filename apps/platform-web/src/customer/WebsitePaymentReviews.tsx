import { useEffect, useState } from "react";
import { customerApi } from "./api";

type ReviewPage = {
  total: number;
  offset: number;
  limit: number;
  items: Array<{
    bookingId: string;
    date: string;
    timeSlot: string;
    bookingStatus: string;
    paymentState: string;
    expectedMinor: string | null;
    grossPaidMinor: string | null;
    refundedMinor: string | null;
    currency: string | null;
    reason: string;
    paymentId: string | null;
  }>;
};
const reasonLabels: Record<string, string> = {
  late_payment: "გადახდა ჯავშნის ვადის შემდეგ დაიწყო",
  payment_timing_unproven: "გადახდის დრო გადასამოწმებელია",
  on_time_payment_hold_reassigned:
    "დროული გადახდაა; მაგიდა სხვა ჯავშანზეა გამოყოფილი",
  expired_awaiting_receipt: "ჯავშნის ვადა გავიდა; ბანკის შედეგს ველოდებით",
  provider_receipt_unavailable: "ბანკის ქვითარი დროებით ვერ გადამოწმდა",
  historical_payment_snapshot_missing: "ისტორიული გადახდა გადასამოწმებელია",
  partial_payment: "გადასახდელი თანხა სრულად არ დადასტურდა",
  requested_amount_mismatch: "ბანკის მოთხოვნილი თანხა არ ემთხვევა ჯავშანს",
  settled_amount_mismatch: "გადახდილი თანხა გადასამოწმებელია",
  currency_mismatch: "გადახდის ვალუტა არ ემთხვევა ჯავშანს",
  unsupported_capture: "თანხის ჩამოჭრა ჯერ არ დადასტურდა",
  refund_pending: "თანხის დაბრუნების დასრულებას ველოდებით",
  hold_identity_missing: "ჯავშნის მაგიდის შესაბამისობა გადასამოწმებელია",
  receipt_incomplete: "ბანკის ქვითრის მონაცემები არასრულია",
  order_creation_outcome_unknown: "ბანკში გადახდის მოთხოვნის შედეგი უცნობია",
};
const money = (value: string | null, currency: string | null) => {
  if (!value || !/^\d+$/.test(value) || !currency) return "უცნობია";
  const digits = value.padStart(3, "0");
  return `${digits.slice(0, -2)}.${digits.slice(-2)} ${currency}`;
};

export function WebsitePaymentReviews({ venueId }: { venueId: string }) {
  const [offset, setOffset] = useState(0);
  const [revision, setRevision] = useState(0);
  const key = `${venueId}:${offset}:${revision}`;
  const [result, setResult] = useState<{
    key: string;
    page?: ReviewPage;
    error?: string;
  }>({ key: "" });
  const page = result.key === key ? result.page : undefined;
  const error = result.key === key ? result.error : undefined;
  useEffect(() => {
    let active = true;
    customerApi<ReviewPage>(
      `venues/${venueId}/website-payment-reviews?offset=${offset}`,
    )
      .then((data) => {
        if (!Array.isArray(data.items))
          throw new Error("გადახდების სიის წაკითხვა ვერ მოხერხდა");
        if (active) setResult({ key, page: data });
      })
      .catch((e: unknown) => {
        if (active)
          setResult({
            key,
            error:
              e instanceof Error ? e.message : "სიის წაკითხვა ვერ მოხერხდა",
          });
      });
    return () => {
      active = false;
    };
  }, [venueId, offset, key]);
  return (
    <section
      className="portal-card"
      aria-labelledby="website-payment-review-title"
    >
      <h2 id="website-payment-review-title">
        გადასამოწმებელი ჯავშნის გადახდები
      </h2>
      <p>
        ფინანსურ გამონაკლისს რესტორნის მფლობელი წყვეტს. ტექნიკური
        გადამოწმებისთვის დაუკავშირდი Vynic support-ს. ჯავშანი ავტომატურად არ
        აღდგება და თანხა ავტომატურად არ დაბრუნდება.
      </p>
      {error ? (
        <p role="alert">{error}</p>
      ) : !page ? (
        <p role="status">იტვირთება…</p>
      ) : page.items.length === 0 ? (
        <p>გადასამოწმებელი გადახდა არ არის.</p>
      ) : (
        <>
          <div
            className="overflow-x-auto"
            tabIndex={0}
            aria-label="ჯავშნის გადახდების ცხრილი"
          >
            <table className="min-w-[720px] w-full text-left [&_th]:p-3 [&_td]:p-3">
              <thead>
                <tr>
                  <th>ჯავშანი</th>
                  <th>მიზეზი</th>
                  <th>მოთხოვნილი / გადახდილი / დაბრუნებული</th>
                  <th>ბანკის reference</th>
                </tr>
              </thead>
              <tbody>
                {page.items.map((row) => (
                  <tr key={row.bookingId}>
                    <td>
                      <span className="break-all">{row.bookingId}</span>
                      <br />
                      {row.date.slice(0, 10)} · {row.timeSlot}
                      <br />
                      {row.bookingStatus} · {row.paymentState}
                    </td>
                    <td>
                      {reasonLabels[row.reason] ??
                        "გადახდის შედეგი გადასამოწმებელია"}
                    </td>
                    <td>
                      {money(row.expectedMinor, row.currency)} /{" "}
                      {money(row.grossPaidMinor, row.currency)} /{" "}
                      {money(row.refundedMinor, row.currency)}
                    </td>
                    <td className="break-all">{row.paymentId ?? "უცნობია"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <div className="flex flex-wrap gap-3">
            <button
              disabled={offset === 0}
              onClick={() => setOffset(Math.max(0, offset - page.limit))}
            >
              წინა
            </button>
            <button
              disabled={offset + page.limit >= page.total}
              onClick={() => setOffset(offset + page.limit)}
            >
              შემდეგი
            </button>
          </div>
        </>
      )}
      <button onClick={() => setRevision(revision + 1)}>განახლება</button>
    </section>
  );
}
