import React, { useEffect, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { useLanguage } from '../contexts/LanguageContext';

const PaymentFail: React.FC = () => {
  const { t, language } = useLanguage();
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const [errorMessage, setErrorMessage] = useState<string>('');
  const [isValidAccess, setIsValidAccess] = useState<boolean>(false);

  // Scale down font size for Georgian language to match English visual weight
  const isGeorgian = language === 'ka';
  const baseFontSize = isGeorgian ? 'text-[1rem]' : 'text-[1rem]';

  useEffect(() => {
    console.log('PaymentFail page loaded with search params:', searchParams.toString());
    console.log('All URL parameters:', Object.fromEntries(searchParams.entries()));

    // FOR DEVELOPMENT: Always allow access
    setIsValidAccess(true);

    // Still try to get error message if available
    const error = searchParams.get('error') || searchParams.get('error_description');
    if (error) {
      setErrorMessage(error);
    }
  }, [searchParams]);

  const handleRetryPayment = () => {
    navigate(`/${language}/cart`);
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
          {/* Error Icon */}
          <div className="mb-8">
            <div className="w-24 h-24 mx-auto bg-red-500 rounded-full flex items-center justify-center">
              <svg className="w-12 h-12 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
              </svg>
            </div>
          </div>

          {/* Error Message */}
          <h1 className="text-3xl sm:text-4xl font-bold text-red-400 mb-4">
            {t('payment.fail.title')}
          </h1>

          <p className="text-xl text-gray-300 mb-8">
            {t('payment.fail.message')}
          </p>

          {/* Error Details */}
          {errorMessage && (
            <div className="bg-[#333] rounded-lg p-6 mb-8 border border-red-500">
              <h3 className="text-lg font-semibold text-white mb-2">
                {t('payment.fail.details')}
              </h3>
              <p className="text-red-300 text-sm font-mono bg-[#222] p-3 rounded">
                {errorMessage}
              </p>
            </div>
          )}

          {/* Common Issues */}
          <div className="bg-[#333] rounded-lg p-6 mb-8 text-left">
            <h3 className="text-lg font-semibold text-white mb-4">
              {t('payment.fail.commonIssues')}
            </h3>
            <div className="space-y-3 text-gray-300 text-sm">
              <div className="flex items-start gap-3">
                <div className="w-2 h-2 bg-red-400 rounded-full flex-shrink-0 mt-2"></div>
                <p>
                  {t('payment.fail.issue1')}
                </p>
              </div>
              <div className="flex items-start gap-3">
                <div className="w-2 h-2 bg-red-400 rounded-full flex-shrink-0 mt-2"></div>
                <p>
                  {t('payment.fail.issue2')}
                </p>
              </div>
              <div className="flex items-start gap-3">
                <div className="w-2 h-2 bg-red-400 rounded-full flex-shrink-0 mt-2"></div>
                <p>
                  {t('payment.fail.issue3')}
                </p>
              </div>
              <div className="flex items-start gap-3">
                <div className="w-2 h-2 bg-red-400 rounded-full flex-shrink-0 mt-2"></div>
                <p>
                  {t('payment.fail.issue4')}
                </p>
              </div>
              <div className="flex items-start gap-3">
                <div className="w-2 h-2 bg-red-400 rounded-full flex-shrink-0 mt-2"></div>
                <p>
                  {t('payment.fail.issue5')}
                </p>
              </div>
            </div>
          </div>

          {/* Information Card */}
          <div className="bg-[#333] rounded-lg p-6 mb-8 text-left">
            <h3 className="text-lg font-semibold text-white mb-4">
              {t('payment.fail.whatToDo')}
            </h3>
            <div className="space-y-3 text-gray-300">
              <div className="flex items-start gap-3">
                <div className="w-6 h-6 bg-[#a89763] rounded-full flex items-center justify-center flex-shrink-0 mt-0.5">
                  <span className="text-[#222] text-sm font-semibold">1</span>
                </div>
                <p className="text-sm">
                  {t('payment.fail.step1')}
                </p>
              </div>
              <div className="flex items-start gap-3">
                <div className="w-6 h-6 bg-[#a89763] rounded-full flex items-center justify-center flex-shrink-0 mt-0.5">
                  <span className="text-[#222] text-sm font-semibold">2</span>
                </div>
                <p className="text-sm">
                  {t('payment.fail.step2')}
                </p>
              </div>
              <div className="flex items-start gap-3">
                <div className="w-6 h-6 bg-[#a89763] rounded-full flex items-center justify-center flex-shrink-0 mt-0.5">
                  <span className="text-[#222] text-sm font-semibold">3</span>
                </div>
                <p className="text-sm">
                  {t('payment.fail.step3')}
                </p>
              </div>
            </div>
          </div>

          {/* Action Buttons */}
          <div className="space-y-4">
            <button
              onClick={handleRetryPayment}
              className="w-full bg-gradient-to-r from-[#a89763] to-[#c0ad7b] hover:from-[#c0ad7b] hover:to-[#a89763] text-[#222] font-semibold py-4 px-6 rounded-lg transition-all duration-300 transform hover:scale-105"
            >
              {t('payment.fail.tryAgain')}
            </button>

            <button
              onClick={handleReturnHome}
              className="w-full bg-[#444] hover:bg-[#555] text-white font-medium py-4 px-6 rounded-lg transition-colors"
            >
              {t('payment.success.returnHome')}
            </button>
          </div>

          {/* Contact Info */}
          <div className="mt-8 pt-8 border-t border-[#444]">
            <p className="text-gray-400 text-sm mb-4">
              {t('payment.fail.contact')}
            </p>
            <div className="flex flex-col sm:flex-row gap-4 justify-center items-center">
              <a
                href="mailto:restaurantvankisi@gmail.com"
                className="text-[#a89763] hover:text-[#c0ad7b] flex items-center gap-2"
              >
                <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 8l7.89 4.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
                </svg>
                restaurantvankisi@gmail.com
              </a>
              <span className="text-gray-600 hidden sm:block">|</span>
              <a
                href="tel:+995555123456"
                className="text-[#a89763] hover:text-[#c0ad7b] flex items-center gap-2"
              >
                <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 5a2 2 0 012-2h3.28a1 1 0 01.948.684l1.498 4.493a1 1 0 01-.502 1.21l-2.257 1.13a11.042 11.042 0 005.516 5.516l1.13-2.257a1 1 0 011.21-.502l4.493 1.498a1 1 0 01.684.949V19a2 2 0 01-2 2h-1C9.716 21 3 14.284 3 6V5z" />
                </svg>
                +995 555 123 456
              </a>
            </div>
          </div>

          {/* Don't lose your reservation note */}
          <div className="mt-8 p-4 bg-yellow-500/10 border border-yellow-500/30 rounded-lg">
            <p className="text-yellow-400 text-sm">
              <strong>
                {t('payment.fail.note')}
              </strong>{' '}
              {t('payment.fail.noteMessage')}
            </p>
          </div>
        </div>
      </div>
    </div>
  );
};

export default PaymentFail;
