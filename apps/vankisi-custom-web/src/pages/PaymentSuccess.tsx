import React, { useEffect, useRef, useState } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { useLanguage } from "../contexts/LanguageContext";
import { useCart } from "../contexts/CartContext";
import api from "../services/api";
import { WebsiteContactEmail } from "../components/WebsiteInfo";

const PaymentSuccess: React.FC = () => {
  const { t, language } = useLanguage();
  const { clearCart } = useCart();
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const [paymentId, setPaymentId] = useState<string | null>(null);
  const [verification, setVerification] = useState<
    "checking" | "confirmed" | "pending" | "review" | "failed" | "unknown"
  >("checking");
  const clearCartRef = useRef(clearCart);
  const [checkRevision, setCheckRevision] = useState(0);

  // Scale down font size for Georgian language to match English visual weight
  const isGeorgian = language === "ka";
  const baseFontSize = isGeorgian ? "text-[1rem]" : "text-[1rem]";

  useEffect(() => {
    let active = true;
    const checkStatus = async () => {
      const orderId = searchParams.get("order_id");
      const reservationId = searchParams.get("reservation_id");
      setVerification("checking");
      if (!orderId && !reservationId) {
        setVerification("unknown");
        return;
      }
      setPaymentId(orderId || reservationId);
      try {
        const { data } = await api.get<{ success?: boolean; status?: string }>(
          reservationId
            ? `/bog/check-reservation-status/${encodeURIComponent(reservationId)}`
            : `/bog/check-status/${encodeURIComponent(orderId!)}`,
        );
        if (!active) return;
        if (data.success && data.status === "CONFIRMED") {
          setVerification("confirmed");
          clearCartRef.current();
          for (const key of [
            "reservationData",
            "vankisi_reservation",
            "vankisi_preorder",
            "selectedReservationDate",
            "selectedReservationTime",
            "vankisi-cart",
            "checkoutInProgress",
            "redirectAfterLogin",
          ])
            localStorage.removeItem(key);
        } else
          setVerification(
            data.status === "REVIEW"
              ? "review"
              : data.status === "FAILED"
                ? "failed"
                : data.status === "PENDING"
                  ? "pending"
                  : "unknown",
          );
      } catch {
        if (active) setVerification("unknown");
      }
    };
    void checkStatus();
    return () => {
      active = false;
    };
  }, [searchParams, checkRevision]);

  const handleReturnHome = () => {
    navigate(`/${language}/`);
  };

  // Show loading while validating access
  if (verification === "checking") {
    return (
      <div className="min-h-screen bg-[#222] pt-20 pb-10 flex items-center justify-center">
        <div className="text-center">
          <div className="w-16 h-16 border-4 border-[#333] border-t-[#a89763] rounded-full animate-spin mx-auto mb-4"></div>
          <p className="text-gray-400">{t("payment.loading")}</p>
        </div>
      </div>
    );
  }

  if (verification !== "confirmed") {
    const title = isGeorgian
      ? verification === "review"
        ? "ჯავშანი გადასამოწმებელია"
        : verification === "pending"
          ? "გადახდის შედეგს ველოდებით"
          : "ჯავშანი ჯერ არ დადასტურებულა"
      : verification === "review"
        ? "Your reservation needs review"
        : verification === "pending"
          ? "Waiting for the payment result"
          : "Your reservation is not confirmed yet";
    return (
      <div
        className={`min-h-screen bg-[#222] pt-20 pb-10 font-sans ${baseFontSize}`}
      >
        <div className="mx-auto max-w-2xl px-4 py-16 text-center">
          <h1 className="mb-4 text-3xl font-bold text-[#a89763]">{title}</h1>
          <p className="mb-8 text-lg text-gray-300">
            {isGeorgian
              ? "თუ თანხა ჩამოგეჭრა, ახალი გადახდა არ დაიწყო და რესტორანს დაუკავშირდი. შედეგის გადამოწმება შეგიძლია ხელახლა."
              : "If you were charged, do not start another payment. Contact the restaurant, or check the result again."}
          </p>
          {paymentId ? (
            <p className="mb-8 break-all font-mono text-sm text-gray-400">
              {paymentId}
            </p>
          ) : null}
          <div className="flex flex-wrap justify-center gap-4">
            {paymentId ? (
              <button
                onClick={() => setCheckRevision((value) => value + 1)}
                className="rounded-lg bg-[#a89763] px-6 py-3 font-semibold text-[#222]"
              >
                {isGeorgian ? "ხელახლა გადამოწმება" : "Check again"}
              </button>
            ) : null}
            <button
              onClick={handleReturnHome}
              className="rounded-lg border border-[#a89763] px-6 py-3 text-[#a89763]"
            >
              {isGeorgian ? "მთავარ გვერდზე დაბრუნება" : "Return home"}
            </button>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div
      className={`min-h-screen bg-[#222] pt-20 pb-10 font-sans ${baseFontSize}`}
    >
      <div className="max-w-2xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="text-center py-16">
          {/* Success Icon */}
          <div className="mb-8">
            <div className="w-24 h-24 mx-auto bg-green-500 rounded-full flex items-center justify-center">
              <svg
                className="w-12 h-12 text-white"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth={2}
                  d="M5 13l4 4L19 7"
                />
              </svg>
            </div>
          </div>

          {/* Success Message */}
          <h1 className="text-3xl sm:text-4xl font-bold text-green-400 mb-4">
            {t("payment.success.title")}
          </h1>

          <p className="text-xl text-gray-300 mb-8">
            {isGeorgian
              ? "გადახდა და ჯავშანი დადასტურდა. შეინახე ჯავშნის ნომერი; დეტალების შესაცვლელად რესტორანს დაუკავშირდი."
              : "Your payment and reservation are confirmed. Save your reference; contact the restaurant to change booking details."}
          </p>

          {/* Payment Details */}
          {paymentId && (
            <div className="bg-[#333] rounded-lg p-6 mb-8 border border-green-500">
              <h3 className="text-lg font-semibold text-white mb-2">
                {t("payment.success.details")}
              </h3>
              <p className="text-gray-300">
                <span className="text-gray-400">{t("payment.success.id")}</span>
                <span className="ml-2 font-mono text-green-400">
                  {paymentId}
                </span>
              </p>
              {/* Manual Check Button */}
              <button
                onClick={() => setCheckRevision((value) => value + 1)}
                className="mt-4 text-sm text-[#a89763] hover:text-[#c0ad7b] underline"
              >
                {t("payment.success.refresh")}
              </button>
            </div>
          )}

          {/* Action Buttons */}
          <div className="space-y-4">
            <button
              onClick={handleReturnHome}
              className="w-full bg-gradient-to-r from-[#a89763] to-[#c0ad7b] hover:from-[#c0ad7b] hover:to-[#a89763] text-[#222] font-semibold py-4 px-6 rounded-lg transition-all duration-300 transform hover:scale-105"
            >
              {t("payment.success.returnHome")}
            </button>
          </div>

          {/* Contact Info */}
          <div className="mt-8 pt-8 border-t border-[#444]">
            <WebsiteContactEmail label={t("payment.success.contact")} />
          </div>
        </div>
      </div>
    </div>
  );
};

export default PaymentSuccess;
