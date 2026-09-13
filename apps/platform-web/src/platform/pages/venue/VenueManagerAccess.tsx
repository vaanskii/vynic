import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { platformApi } from "../../api";
import { Button } from "../../components/Button";
import { Panel } from "../../components/Page";
import { ErrorState, LoadingState } from "../../components/State";
import { errorMessage } from "../../format";
import type { Venue } from "../../types";
import { VenueCommercialTab } from "./VenueCommercialTab";

/** A Venue identifier, shared by its Managers; never a second credential. */
export function VenueManagerAccess({
  venue,
}: {
  venue: Pick<Venue, "id" | "name" | "loginCode">;
}) {
  const [feedback, setFeedback] = useState("");
  const product = useQuery({
    queryKey: ["product", venue.id],
    queryFn: () => platformApi.product(venue.id),
  });
  const enabled =
    product.data?.effectiveFeatures.includes("MANAGER_APP") === true;
  async function copy() {
    try {
      await navigator.clipboard.writeText(venue.loginCode);
      setFeedback("კოდი დაკოპირებულია");
    } catch {
      setFeedback("კოპირება ვერ მოხერხდა. მონიშნეთ და დააკოპირეთ კოდი.");
    }
  }
  return (
    <>
      <Panel title="მენეჯერის აპლიკაცია" description={venue.name}>
        <p>
          რესტორნის კოდი:{" "}
          <strong style={{ overflowWrap: "anywhere" }}>
            {venue.loginCode}
          </strong>
        </p>
        <Button onClick={() => void copy()}>კოპირება</Button>
        {feedback && <p role="status">{feedback}</p>}
        {product.isPending ? (
          <LoadingState label="წვდომის შემოწმება" />
        ) : product.error ? (
          <ErrorState
            error={errorMessage(product.error)}
            retry={() => void product.refetch()}
          />
        ) : !enabled ? (
          <p>მენეჯერის აპლიკაცია გამორთულია</p>
        ) : (
          <p>
            კოდი შეიყვანეთ ერთხელ თითოეულ მოწყობილობაზე. შემდეგ შესასვლელად
            გამოიყენეთ პირადი PIN.
          </p>
        )}
      </Panel>
      {enabled && <VenueCommercialTab venueId={venue.id} accessOnly />}
    </>
  );
}
