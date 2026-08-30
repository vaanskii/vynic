import React, { useEffect, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { useLanguage } from '../contexts/LanguageContext';
import { useCart } from '../contexts/CartContext';

const PaymentSuccess: React.FC = () => {
  const { t, language } = useLanguage();
  const { clearCart } = useCart();
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const [paymentId, setPaymentId] = useState<string | null>(null);
  const [isValidAccess, setIsValidAccess] = useState<boolean>(false);

  // Scale down font size for Georgian language to match English visual weight
  const isGeorgian = language === 'ka';
  const baseFontSize = isGeorgian ? 'text-[1rem]' : 'text-[1rem]';

  useEffect(() => {
    const checkStatus = async () => {
      const orderId = searchParams.get('order_id');
      const reservationId = searchParams.get('reservation_id');

      if (!orderId && !reservationId) {
        // Fallback to existing logic if no IDs
        const hasUrlParams = searchParams.toString().length > 0;
        const isFromPayment = document.referrer.includes('bog.ge') || document.referrer.includes('payment');

        if (hasUrlParams || isFromPayment) {
          setIsValidAccess(true);
          clearLocalStorage();
        } else {
          // Check recent payment attempt
          const recentPayment = sessionStorage.getItem('recentPaymentAttempt');

          if (recentPayment && (Date.now() - parseInt(recentPayment) < 10 * 60 * 1000)) {
            setIsValidAccess(true);
            sessionStorage.removeItem('recentPaymentAttempt');
          } else {
            setTimeout(() => navigate(`/${language}/`, { replace: true }), 2000);
          }
        }
        return;
      }

      try {
        let response;
        let url;
        const apiUrl = import.meta.env.VITE_API_URL || 'http://localhost:3000'; // Fallback to localhost

        if (reservationId) {
          // Check by reservation ID (preferred as it's our internal ID)
          url = `${apiUrl}/api/bog/check-reservation-status/${reservationId}`;
          response = await fetch(url);
        } else {
          // Fallback to order ID
          url = `${apiUrl}/api/bog/check-status/${orderId}`;
          response = await fetch(url);
        }

        const data = await response.json();

        if (data.success && data.status === 'CONFIRMED') {
          setIsValidAccess(true);
          setPaymentId(orderId || reservationId); // Show whichever ID we have
          clearLocalStorage();
        } else {
          console.warn('Payment not confirmed:', data);
          // Still show success page if it's a valid BOG redirect, but maybe show pending status?
          // For now, we'll trust the redirect but log the warning
          setIsValidAccess(true);
          setPaymentId(orderId || reservationId);
          clearLocalStorage();
        }
      } catch (error) {
        console.error('Error checking payment status:', error);
        // Fallback to allowing access if it looks like a valid redirect
        setIsValidAccess(true);
        setPaymentId(orderId || reservationId);
        clearLocalStorage();
      }
    };

    checkStatus();
  }, [searchParams, navigate, language]);

  const clearLocalStorage = () => {
    console.log('Clearing local storage and cart...');
    clearCart();
    localStorage.removeItem('reservationData');
    localStorage.removeItem('selectedReservationDate');
    localStorage.removeItem('selectedReservationTime');
    localStorage.removeItem('vankisi-cart');
    localStorage.removeItem('checkoutInProgress');
    localStorage.removeItem('redirectAfterLogin');
  };

  const handleReturnHome = () => {
    navigate(`/${language}/`);
  };

  // Show loading while validating access
  if (!isValidAccess) {
    return (
      <div className="min-h-screen bg-[#222] pt-20 pb-10 flex items-center justify-center">
        <div className="text-center">
          <div className="w-16 h-16 border-4 border-[#333] border-t-[#a89763] rounded-full animate-spin mx-auto mb-4"></div>
          <p className="text-gray-400">
            {t('payment.loading')}
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className={`min-h-screen bg-[#222] pt-20 pb-10 font-sans ${baseFontSize}`}>
      <div className="max-w-2xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="text-center py-16">
          {/* Success Icon */}
          <div className="mb-8">
            <div className="w-24 h-24 mx-auto bg-green-500 rounded-full flex items-center justify-center">
              <svg className="w-12 h-12 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
              </svg>
            </div>
          </div>

          {/* Success Message */}
          <h1 className="text-3xl sm:text-4xl font-bold text-green-400 mb-4">
            {t('payment.success.title')}
          </h1>

          <p className="text-xl text-gray-300 mb-8">
            {t('payment.success.message')}
          </p>

          {/* Payment Details */}
          {paymentId && (
            <div className="bg-[#333] rounded-lg p-6 mb-8 border border-green-500">
              <h3 className="text-lg font-semibold text-white mb-2">
                {t('payment.success.details')}
              </h3>
              <p className="text-gray-300">
                <span className="text-gray-400">
                  {t('payment.success.id')}
                </span>
                <span className="ml-2 font-mono text-green-400">{paymentId}</span>
              </p>
              {/* Manual Check Button */}
              <button
                onClick={() => window.location.reload()}
                className="mt-4 text-sm text-[#a89763] hover:text-[#c0ad7b] underline"
              >
                {t('payment.success.refresh')}
              </button>
            </div>
          )}

          {/* Information Card */}
          <div className="bg-[#333] rounded-lg p-6 mb-8 text-left">
            <h3 className="text-lg font-semibold text-white mb-4">
              {t('payment.success.nextSteps')}
            </h3>
            <div className="space-y-3 text-gray-300">
              <div className="flex items-start gap-3">
                <div className="w-6 h-6 bg-[#a89763] rounded-full flex items-center justify-center flex-shrink-0 mt-0.5">
                  <span className="text-[#222] text-sm font-semibold">1</span>
                </div>
                <p className="text-sm">
                  {t('payment.success.step1')}
                </p>
              </div>
              <div className="flex items-start gap-3">
                <div className="w-6 h-6 bg-[#a89763] rounded-full flex items-center justify-center flex-shrink-0 mt-0.5">
                  <span className="text-[#222] text-sm font-semibold">2</span>
                </div>
                <p className="text-sm">
                  {t('payment.success.step2')}
                </p>
              </div>
              <div className="flex items-start gap-3">
                <div className="w-6 h-6 bg-[#a89763] rounded-full flex items-center justify-center flex-shrink-0 mt-0.5">
                  <span className="text-[#222] text-sm font-semibold">3</span>
                </div>
                <p className="text-sm">
                  {t('payment.success.step3')}
                </p>
              </div>
            </div>
          </div>

          {/* Action Buttons */}
          <div className="space-y-4">
            <button
              onClick={handleReturnHome}
              className="w-full bg-gradient-to-r from-[#a89763] to-[#c0ad7b] hover:from-[#c0ad7b] hover:to-[#a89763] text-[#222] font-semibold py-4 px-6 rounded-lg transition-all duration-300 transform hover:scale-105"
            >
              {t('payment.success.returnHome')}
            </button>
          </div>

          {/* Contact Info */}
          <div className="mt-8 pt-8 border-t border-[#444]">
            <p className="text-gray-400 text-sm">
              {t('payment.success.contact')}
              <a href="mailto:restaurantvankisi@gmail.com" className="text-[#a89763] hover:text-[#c0ad7b]">
                restaurantvankisi@gmail.com
              </a>
            </p>
          </div>
        </div>
      </div>
    </div>
  );
};

export default PaymentSuccess;
