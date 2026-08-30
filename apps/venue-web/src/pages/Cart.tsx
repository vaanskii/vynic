import React, { useState, useEffect } from 'react';
import { useCart } from '../contexts/CartContext';
import { useLanguage } from '../contexts/LanguageContext';
import { useAuth } from '../contexts/AuthContext';
import { tableService, userService } from '../services/api';
import { Link, useNavigate } from 'react-router-dom';

const CartPage: React.FC = () => {
  const { state, removeItem, updateQuantity, clearCart, reloadCart } = useCart();
  const { language } = useLanguage();
  // Cart item data only has en/ka; fall back to English for other languages (e.g. ru)
  const dataLang: 'en' | 'ka' = language === 'ka' ? 'ka' : 'en';
  const { user } = useAuth();
  const navigate = useNavigate();
  const [reservationData, setReservationData] = useState<any>(null);
  const [isCreatingReservation, setIsCreatingReservation] = useState(false);
  const [userProfile, setUserProfile] = useState<any>(null);
  const [customerEmail, setCustomerEmail] = useState('');
  const [showLoginModal, setShowLoginModal] = useState(false);
  const [alertModal, setAlertModal] = useState<{
    show: boolean;
    title: string;
    message: string;
    onConfirm?: () => void;
    confirmText?: string;
    type: 'error' | 'info' | 'warning';
  } | null>(null);

  // Update email when user profile loads
  useEffect(() => {
    if (user?.email) {
      setCustomerEmail(user.email);
    } else if (userProfile?.email) {
      setCustomerEmail(userProfile.email);
    }
  }, [user, userProfile]);
  const [priceValidationModal, setPriceValidationModal] = useState<{
    show: boolean;
    frontendTotal: number;
    serverTotal: number;
    onConfirm: () => void;
    onCancel: () => void;
  } | null>(null);

  const handleQuantityChange = (id: string, newQuantity: number) => {
    if (newQuantity <= 0) {
      removeItem(id);
    } else {
      updateQuantity(id, newQuantity);
    }
  };

  // Load reservation data from localStorage
  useEffect(() => {
    const savedReservationData = localStorage.getItem('reservationData');
    if (savedReservationData) {
      try {
        const parsedData = JSON.parse(savedReservationData);
        setReservationData(parsedData);
        console.log('Loaded reservation data in cart:', parsedData);
      } catch (error) {
        console.error('Error parsing reservation data:', error);
      }
    }

    // Clean up any leftover checkout flags if user reached cart page directly
    // (not through the checkout process)
    const checkoutInProgress = localStorage.getItem('checkoutInProgress');
    if (checkoutInProgress && user) {
      // User is authenticated and on cart page, so checkout process is complete
      localStorage.removeItem('checkoutInProgress');
      localStorage.removeItem('redirectAfterLogin');
    }
  }, [user]);

  // Fetch user profile when user is available
  useEffect(() => {
    const fetchUserProfile = async () => {
      if (user) {
        try {
          const profile = await userService.getProfile();
          setUserProfile(profile);
        } catch (error) {
          console.error('Error fetching user profile:', error);
        }
      }
    };

    fetchUserProfile();
  }, [user]);

  const handleBogPayment = async () => {
    // Check if user is authenticated
    if (!user) {
      setShowLoginModal(true);
      return;
    }

    // Check if there's reservation data
    // Check if there's reservation data
    if (!reservationData) {
      setAlertModal({
        show: true,
        title: language === 'ka' ? 'ჯავშანი ვერ მოიძებნა' : 'Reservation Not Found',
        message: language === 'ka'
          ? 'ჯავშნის ინფორმაცია ვერ მოიძებნა. გთხოვთ აირჩიოთ მაგიდები.'
          : 'Reservation information not found. Please select tables first.',
        type: 'warning',
        onConfirm: () => navigate(`/${language}/reservation`),
        confirmText: language === 'ka' ? 'ჯავშნის გვერდზე გადასვლა' : 'Go to Reservation'
      });
      return;
    }

    // Check if cart has items
    // Check if cart has items
    if (state.items.length === 0) {
      setAlertModal({
        show: true,
        title: language === 'ka' ? 'კალათა ცარიელია' : 'Cart is Empty',
        message: language === 'ka'
          ? 'კალათა ცარიელია. გთხოვთ აირჩიოთ კერძები.'
          : 'Cart is empty. Please add some items first.',
        type: 'info'
      });
      return;
    }

    // Validate Email
    if (!customerEmail || !customerEmail.includes('@')) {
      setAlertModal({
        show: true,
        title: language === 'ka' ? 'ელ-ფოსტა სავალდებულოა' : 'Email Required',
        message: language === 'ka'
          ? 'გთხოვთ შეიყვანოთ ელ-ფოსტის მისამართი'
          : 'Please enter a valid email address',
        type: 'warning'
      });
      return;
    }

    try {
      setIsCreatingReservation(true);

      // Prepare reservation data for BOG payment
      const customerName = userProfile?.firstName && userProfile?.lastName
        ? `${userProfile.firstName} ${userProfile.lastName}`
        : user.phone;

      const paymentPayload = {
        selectedTables: reservationData.selectedTables,
        selectedDate: reservationData.selectedDate,
        selectedTime: reservationData.selectedTime,
        menuItems: state.items.map(item => ({
          id: item.id,
          quantity: item.quantity,
          price: item.price
        })),
        totalAmount: state.totalPrice, // Frontend calculated total (includes service fee)
        customerEmail: customerEmail,
        customerName: customerName,
        customerPhone: userProfile?.phone || undefined,
        userId: user.id, // Add user ID for linking reservations
        notes: `BOG Payment - Tables: ${reservationData.selectedTables.join(', ')}`,
        language: language, // Add current language
      };

      console.log('Creating BOG payment with data:', paymentPayload);
      console.log('Customer email:', customerEmail);

      // Set session storage flag to allow access to payment result pages
      const timestamp = Date.now().toString();
      sessionStorage.setItem('recentPaymentAttempt', timestamp);
      console.log('Set recentPaymentAttempt in sessionStorage:', timestamp);

      // Create BOG payment order
      const result = await tableService.createBogPayment(paymentPayload);

      console.log('BOG payment order created:', result);

      // 🛡️ SECURITY: Check if server validation differs from frontend calculation
      if (result.validation) {
        const serverTotal = result.validation.serverCalculatedTotal;
        const frontendTotal = state.totalPrice; // Frontend total includes service fee

        // Update localStorage with corrected prices immediately
        if (result.validation.correctedCartItems) {
          console.log('🔧 Updating localStorage with server-corrected prices:', result.validation.correctedCartItems);

          // Merge server corrections with original cart data to preserve imageUrls
          const correctedItems = result.validation.correctedCartItems.map((correctedItem: any) => {
            const originalItem = state.items.find(original => original.id === correctedItem.id);
            return {
              ...correctedItem,
              imageUrl: correctedItem.imageUrl || originalItem?.imageUrl || '', // Preserve original imageUrl if server doesn't provide it
            };
          });

          // Use the same key that CartContext uses
          localStorage.setItem('vankisi-cart', JSON.stringify(correctedItems));

          console.log('✅ Cart prices have been corrected to match database prices');
          console.log('🔄 Please refresh the page to see updated prices in your cart');
        }

        if (Math.abs(serverTotal - frontendTotal) > 0.01) { // Allow for small rounding differences
          console.warn('🚨 Price validation mismatch:', {
            frontendTotal,
            serverTotal,
            difference: serverTotal - frontendTotal,
            frontendSubtotal: state.subtotal,
            frontendServiceFee: state.serviceFee,
            serverSubtotal: result.validation.subtotal,
            serverServiceFee: result.validation.serviceFee
          });

          // Show price validation modal instead of alert
          setPriceValidationModal({
            show: true,
            frontendTotal,
            serverTotal,
            onConfirm: () => {
              setPriceValidationModal(null);
              // Continue with payment
              if (result.redirect_url) {
                window.location.href = result.redirect_url;
              } else {
                throw new Error('No redirect URL received from BOG');
              }
            },
            onCancel: () => {
              setPriceValidationModal(null);
              setIsCreatingReservation(false);
              // Reload cart from localStorage with corrected prices
              console.log('🔄 Reloading cart with corrected prices...');
              reloadCart();
            }
          });
          return; // Stop execution here until user decides
        }

        // Show validated items if they differ
        console.log('Server-validated order:', result.validation.validatedItems);
      }

      if (result.redirect_url) {
        // Redirect to BOG payment page
        window.location.href = result.redirect_url;
      } else {
        throw new Error('No redirect URL received from BOG');
      }

    } catch (error) {
      console.error('Error creating BOG payment:', error);
      setAlertModal({
        show: true,
        title: language === 'ka' ? 'შეცდომა' : 'Error',
        message: language === 'ka'
          ? 'BOG გადახდის შექმნისას მოხდა შეცდომა. გთხოვთ სცადოთ ხელახლა.'
          : 'Error creating BOG payment. Please try again.',
        type: 'error'
      });
    } finally {
      setIsCreatingReservation(false);
    }
  };

  const formatTableName = (tableId: string): string => {
    const match = tableId.match(/^table(\d{1,2})$/i);
    if (match) {
      return `Table ${match[1]}`;
    }

    return tableId.charAt(0).toUpperCase() + tableId.slice(1);
  }

  return (
    <div id="cart-page" className="min-h-screen bg-[#222] pt-20 pb-10">
      <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8">
        {/* Header */}
        <div className="mb-8">
          <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
            <h1 className="text-2xl sm:text-3xl font-bold gradient-text">
              {language === 'ka' ? 'შეკვეთის კალათა' : 'Shopping Cart'}
            </h1>
            <Link
              to={`/${language}/menu`}
              className="text-[#a89763] hover:text-[#c0ad7b] flex items-center gap-2 transition-colors self-start sm:self-auto"
            >
              <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 19l-7-7m0 0l7-7m-7 7h18" />
              </svg>
              <span className="text-sm sm:text-base">{language === 'ka' ? 'მენიუზე დაბრუნება' : 'Continue Shopping'}</span>
            </Link>
          </div>
          {state.totalItems > 0 && (
            <p className="text-gray-400 mt-2 text-sm sm:text-base">
              {language === 'ka'
                ? `${state.totalItems} ერთეული კალათაში`
                : `${state.totalItems} item${state.totalItems > 1 ? 's' : ''} in your cart`
              }
            </p>
          )}
        </div>

        {/* Reservation Info */}
        {reservationData && (
          <div className="mb-8 bg-[#333] rounded-lg p-4 sm:p-6 border border-[#a89763]">
            <div className="flex items-center gap-3 mb-4">
              <svg className="w-5 h-5 sm:w-6 sm:h-6 text-[#a89763]" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
              </svg>
              <h3 className="text-lg sm:text-xl font-semibold text-white">
                {language === 'ka' ? 'ჯავშნის დეტალები' : 'Reservation Details'}
              </h3>
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-3 sm:gap-4 text-sm">
              <div>
                <span className="text-gray-400">{language === 'ka' ? 'თარიღი:' : 'Date:'}</span>
                <p className="text-white font-semibold">{reservationData.selectedDate}</p>
              </div>
              <div>
                <span className="text-gray-400">{language === 'ka' ? 'დრო:' : 'Time:'}</span>
                <p className="text-white font-semibold">{reservationData.selectedTime}</p>
              </div>
              <div className="sm:col-span-2 md:col-span-1">
                <span className="text-gray-400">{language === 'ka' ? 'მაგიდები:' : 'Tables:'}</span>
                <p className="text-white font-semibold">
                  {reservationData.selectedTables?.map(formatTableName).join(', ') || 'None'}
                </p>
              </div>
            </div>
          </div>
        )}

        {/* Cart Content */}
        {state.items.length === 0 ? (
          // Empty Cart
          <div className="text-center py-16">
            <div className="mb-6">
              <svg className="w-24 h-24 mx-auto text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1} d="M3 3h2l.4 2M7 13h10l4-8H5.4m0 0L7 13m0 0l-2.5 2.5M7 13l2.5 2.5M17 21a2 2 0 100-4 2 2 0 000 4zM9 21a2 2 0 100-4 2 2 0 000 4z" />
              </svg>
            </div>
            <h2 className="text-xl font-semibold text-white mb-4">
              {language === 'ka' ? 'თქვენი კალათა ცარიელია' : 'Your cart is empty'}
            </h2>
            <p className="text-gray-400 mb-8">
              {language === 'ka'
                ? 'მენიუდან აირჩიეთ გემრიელი კერძები თქვენი შეკვეთისთვის'
                : 'Add some delicious items from our menu to get started'}
            </p>
            <Link
              to={`/${language}/menu`}
              className="inline-flex items-center px-6 py-3 bg-gradient-to-r from-[#a89763] to-[#c0ad7b] text-[#222] font-semibold rounded-lg hover:from-[#c0ad7b] hover:to-[#a89763] transition-all duration-300"
            >
              {language === 'ka' ? 'მენიუს ნახვა' : 'Browse Menu'}
            </Link>
          </div>
        ) : (
          // Cart with Items
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-6 lg:gap-8">
            {/* Cart Items */}
            <div className="lg:col-span-2">
              <div className="bg-[#333] rounded-lg p-4 sm:p-6">
                <div className="space-y-4 sm:space-y-6">
                  {state.items.map((item) => (
                    <div key={item.id} className="flex gap-3 sm:gap-4 pb-4 sm:pb-6 border-b border-[#555] last:border-b-0 last:pb-0">
                      {/* Item Image */}
                      <img
                        src={item.imageUrl}
                        alt={item.translations[dataLang].name}
                        className="w-16 h-16 sm:w-20 sm:h-20 object-cover rounded-lg flex-shrink-0"
                      />

                      {/* Item Details and Controls */}
                      <div className="flex-1 min-w-0">
                        {/* Item Details */}
                        <div className="mb-2 sm:mb-3">
                          <h3 className="text-white font-semibold text-base sm:text-lg mb-1 truncate">
                            {item.translations[dataLang].name}
                          </h3>
                        </div>

                        {/* Controls Row */}
                        <div className="flex items-center justify-between gap-2">
                          {/* Quantity Controls */}
                          <div className="flex items-center space-x-2 sm:space-x-3">
                            <button
                              onClick={() => handleQuantityChange(item.id, item.quantity - 1)}
                              className="w-8 h-8 sm:w-10 sm:h-10 bg-[#555] hover:bg-[#666] text-white rounded-full flex items-center justify-center transition-colors cursor-pointer text-sm sm:text-base"
                            >
                              -
                            </button>
                            <span className="text-white text-sm sm:text-lg w-8 sm:w-12 text-center font-semibold">
                              {item.quantity}
                            </span>
                            <button
                              onClick={() => handleQuantityChange(item.id, item.quantity + 1)}
                              className="w-8 h-8 sm:w-10 sm:h-10 bg-[#555] hover:bg-[#666] text-white rounded-full flex items-center justify-center transition-colors cursor-pointer text-sm sm:text-base"
                            >
                              +
                            </button>
                          </div>

                          {/* Item Total and Remove */}
                          <div className="flex items-center gap-2 sm:gap-3">
                            <p className="text-[#a89763] font-semibold text-sm sm:text-lg">
                              ₾{item.price.toFixed(2)}
                            </p>
                            <button
                              onClick={() => removeItem(item.id)}
                              className="text-red-400 hover:text-red-300 p-1 sm:p-2 rounded-full cursor-pointer hover:bg-red-400/10 transition-all"
                              title={language === 'ka' ? 'წაშლა' : 'Remove'}
                            >
                              <svg className="w-4 h-4 sm:w-5 sm:h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                              </svg>
                            </button>
                          </div>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            </div>

            {/* Order Summary */}
            <div className="lg:col-span-1">
              <div className="bg-[#333] rounded-lg p-4 sm:p-6 lg:sticky lg:top-24">
                <h2 className="text-lg sm:text-xl font-semibold text-white mb-4 sm:mb-6">
                  {language === 'ka' ? 'შეკვეთის შეჯამება' : 'Order Summary'}
                </h2>

                {/* Summary Details */}
                <div className="space-y-3 sm:space-y-4 mb-4 sm:mb-6">
                  <div className="flex justify-between text-gray-300 text-sm sm:text-base">
                    <span>{language === 'ka' ? 'ერთეულები:' : 'Items:'}</span>
                    <span>{state.totalItems}</span>
                  </div>
                  <div className="flex justify-between text-gray-300 text-sm sm:text-base">
                    <span>{language === 'ka' ? 'ქვეჯამი:' : 'Subtotal:'}</span>
                    <span>₾{state.subtotal.toFixed(2)}</span>
                  </div>
                  {state.subtotal > 0 && (
                    <div className="flex justify-between text-gray-300 text-sm sm:text-base">
                      <span>{language === 'ka' ? 'სერვისის საფასური (10%):' : 'Service Fee (10%):'}</span>
                      <span>₾{state.serviceFee.toFixed(2)}</span>
                    </div>
                  )}
                  <hr className="border-[#555]" />
                  <div className="flex justify-between text-lg sm:text-xl font-semibold text-white">
                    <span>{language === 'ka' ? 'სულ:' : 'Total:'}</span>
                    <span className="text-[#a89763]">₾{state.totalPrice.toFixed(2)}</span>
                  </div>
                </div>

                {/* Action Buttons */}
                <div className="space-y-3">

                  {/* Bog Button */}
                  <button
                    onClick={handleBogPayment}
                    disabled={isCreatingReservation}
                    className="w-full bg-gradient-to-r cursor-pointer bg-[#ff600a] text-white font-semibold py-3 sm:py-4 px-4 sm:px-6 rounded-lg transition-all duration-300 transform hover:scale-105 disabled:opacity-50 disabled:cursor-not-allowed disabled:transform-none text-sm sm:text-base flex items-center justify-center gap-2"
                  >
                    {isCreatingReservation ? (
                      <>
                        <svg className="animate-spin w-4 h-4" fill="none" viewBox="0 0 24 24">
                          <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                          <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                        </svg>
                        {language === 'ka' ? 'გადახდა მუშავდება...' : 'Processing Payment...'}
                      </>
                    ) : (
                      <>
                        <img src="/bog.svg" alt='bog button' className='w-10' />
                        <span className='text-xs'>{language === 'ka' ? 'გადახდა BOG-ით' : 'Pay with BOG'}</span>
                      </>
                    )}
                  </button>

                  <button
                    onClick={clearCart}
                    className="w-full bg-red-600 cursor-pointer hover:bg-red-700 text-white font-medium py-3 px-4 sm:px-6 rounded-lg transition-colors text-sm sm:text-base"
                  >
                    {language === 'ka' ? 'კალათის გასუფთავება' : 'Clear Cart'}
                  </button>
                </div>

                {/* Security Badge */}
                <div className="mt-4 sm:mt-6 p-3 sm:p-4 bg-[#222] rounded-lg">
                  <div className="flex items-center gap-2 text-green-400 text-xs sm:text-sm">
                    <svg className="w-4 h-4 sm:w-5 sm:h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
                    </svg>
                    <span>{language === 'ka' ? 'უსაფრთხო ჯავშნა' : 'Secure Reservation'}</span>
                  </div>
                  {!user && (
                    <p className="text-yellow-400 text-xs mt-2">
                      {language === 'ka'
                        ? 'ჯავშნის გასაფორმებლად საჭიროა ავთენტიფიკაცია'
                        : 'Authentication required to complete reservation'}
                    </p>
                  )}
                </div>
              </div>
            </div>
          </div>
        )}
      </div>

      {/* 🛡️ Price Validation Security Modal */}
      {priceValidationModal?.show && (
        <div className="fixed inset-0 bg-black bg-opacity-75 flex items-center justify-center z-50 p-4">
          <div className="bg-[#333] rounded-lg max-w-md w-full p-6 border border-yellow-500">
            {/* Security Alert Header */}
            <div className="flex items-center gap-3 mb-4">
              <div className="w-10 h-10 bg-yellow-500 rounded-full flex items-center justify-center">
                <svg className="w-6 h-6 text-black" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16.5c-.77.833.192 2.5 1.732 2.5z" />
                </svg>
              </div>
              <div>
                <h3 className="text-xl font-bold text-yellow-400">
                  {language === 'ka' ? '🛡️ ფასის კორექცია' : '🛡️ Price Correction'}
                </h3>
                <p className="text-sm text-gray-400">
                  {language === 'ka' ? 'უსაფრთხოების შემოწმება' : 'Security Validation'}
                </p>
              </div>
            </div>

            {/* Price Comparison */}
            <div className="bg-[#222] rounded-lg p-4 mb-6">
              <div className="text-center mb-4">
                <p className="text-gray-300 text-sm mb-3">
                  {language === 'ka'
                    ? 'სერვერმა აღმოაჩინა ფასის განსხვავება და გააკეთა კორექცია:'
                    : 'Our server detected a price discrepancy and made a correction:'
                  }
                </p>
              </div>

              <div className="space-y-3">
                {/* Original Price (Crossed Out) */}
                <div className="flex justify-between items-center p-3 bg-red-900/20 rounded border border-red-500/30">
                  <span className="text-red-400 line-through text-lg">
                    {language === 'ka' ? 'თქვენი ფასი:' : 'Your Price:'}
                  </span>
                  <span className="text-red-400 line-through text-xl font-bold">
                    ₾{priceValidationModal.frontendTotal.toFixed(2)}
                  </span>
                </div>

                {/* Correct Price */}
                <div className="flex justify-between items-center p-3 bg-green-900/20 rounded border border-green-500/30">
                  <span className="text-green-400 text-lg">
                    {language === 'ka' ? 'სწორი ფასი:' : 'Correct Price:'}
                  </span>
                  <span className="text-green-400 text-xl font-bold">
                    ₾{priceValidationModal.serverTotal.toFixed(2)}
                  </span>
                </div>

                {/* Difference */}
                <div className="text-center pt-2 border-t border-gray-600">
                  <p className="text-yellow-400 text-sm">
                    {language === 'ka' ? 'განსხვავება:' : 'Difference:'}
                    <span className="font-bold ml-1">
                      +₾{(priceValidationModal.serverTotal - priceValidationModal.frontendTotal).toFixed(2)}
                    </span>
                  </p>
                </div>
              </div>
            </div>

            {/* Security Explanation */}
            <div className="mb-6 text-sm text-gray-300 text-center">
              <p className="mb-2">
                {language === 'ka'
                  ? 'ეს არის უსაფრთხოების ზომა, რომელიც უზრუნველყოფს სწორ ფასებს.'
                  : 'This is a security measure to ensure correct pricing.'
                }
              </p>
              <p className="text-xs text-gray-400 mb-2">
                {language === 'ka'
                  ? 'ყველა ფასი ვერიფიცირებულია მონაცემთა ბაზიდან.'
                  : 'All prices are verified from our secure database.'
                }
              </p>
              <div className="bg-blue-900/20 border border-blue-500/30 rounded p-2 mt-3">
                <p className="text-blue-400 text-xs">
                  {language === 'ka'
                    ? 'თქვენი კალათა ავტომატურად განახლდა სწორი ფასებით'
                    : 'Your cart has been automatically updated with correct prices'
                  }
                </p>
              </div>
            </div>

            {/* Action Buttons */}
            <div className="flex gap-3">
              <button
                onClick={priceValidationModal.onCancel}
                className="flex-1 px-4 py-3 bg-gray-600 hover:bg-gray-700 text-white rounded-lg transition-colors font-medium"
              >
                {language === 'ka' ? 'გაუქმება & განახლება' : 'Cancel & Refresh'}
              </button>
              <button
                onClick={priceValidationModal.onConfirm}
                className="flex-1 px-4 py-3 bg-gradient-to-r from-green-600 to-green-700 hover:from-green-700 hover:to-green-600 text-white rounded-lg transition-all font-medium"
              >
                {language === 'ka' ? 'სწორი ფასით გადახდა' : 'Pay Correct Amount'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* 🔐 Login Requirement Modal */}
      {showLoginModal && (
        <div className="fixed inset-0 bg-black bg-opacity-75 flex items-center justify-center z-50 p-4">
          <div className="bg-[#333] rounded-lg max-w-md w-full p-6 border border-[#a89763] shadow-2xl">
            {/* Header */}
            <div className="flex items-center justify-center mb-6">
              <div className="w-16 h-16 bg-[#a89763]/20 rounded-full flex items-center justify-center mb-2">
                <svg className="w-8 h-8 text-[#a89763]" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
                </svg>
              </div>
            </div>

            <div className="text-center mb-8">
              <h3 className="text-xl font-bold text-white mb-2">
                {language === 'ka' ? 'ავტორიზაცია სავალდებულოა' : 'Authentication Required'}
              </h3>
              <p className="text-gray-300">
                {language === 'ka'
                  ? 'ჯავშნის დასასრულებლად გთხოვთ გაიაროთ ავტორიზაცია.'
                  : 'Please log in to complete your reservation.'
                }
              </p>
            </div>

            <div className="flex gap-3">
              <button
                onClick={() => setShowLoginModal(false)}
                className="flex-1 px-4 py-3 bg-[#444] hover:bg-[#555] text-white rounded-lg transition-colors font-medium border border-[#555]"
              >
                {language === 'ka' ? 'გაუქმება' : 'Cancel'}
              </button>
              <button
                onClick={() => {
                  // Store redirect flags
                  localStorage.setItem('redirectAfterLogin', `/${language}/cart`);
                  localStorage.setItem('checkoutInProgress', 'true');
                  navigate(`/${language}/login`);
                }}
                className="flex-1 px-4 py-3 bg-gradient-to-r from-[#a89763] to-[#c0ad7b] hover:from-[#c0ad7b] hover:to-[#a89763] text-[#222] rounded-lg transition-all font-bold shadow-lg transform hover:scale-105"
              >
                {language === 'ka' ? 'შესვლა' : 'Log In'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ⚠️ Generic Alert Modal */}
      {alertModal && alertModal.show && (
        <div className="fixed inset-0 bg-black bg-opacity-75 flex items-center justify-center z-50 p-4">
          <div className="bg-[#333] rounded-lg max-w-md w-full p-6 border border-gray-600 shadow-2xl">
            {/* Header Icon based on type */}
            <div className="flex items-center justify-center mb-6">
              <div className={`w-16 h-16 rounded-full flex items-center justify-center mb-2 ${alertModal.type === 'error' ? 'bg-red-900/30' :
                  alertModal.type === 'warning' ? 'bg-yellow-900/30' : 'bg-blue-900/30'
                }`}>
                {alertModal.type === 'error' && (
                  <svg className="w-8 h-8 text-red-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                  </svg>
                )}
                {alertModal.type === 'warning' && (
                  <svg className="w-8 h-8 text-yellow-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16.5c-.77.833.192 2.5 1.732 2.5z" />
                  </svg>
                )}
                {alertModal.type === 'info' && (
                  <svg className="w-8 h-8 text-blue-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                  </svg>
                )}
              </div>
            </div>

            <div className="text-center mb-8">
              <h3 className="text-xl font-bold text-white mb-2">
                {alertModal.title}
              </h3>
              <p className="text-gray-300">
                {alertModal.message}
              </p>
            </div>

            <div className="flex gap-3">
              <button
                onClick={() => {
                  if (alertModal.onConfirm) {
                    alertModal.onConfirm();
                  }
                  setAlertModal(null);
                }}
                className="flex-1 px-4 py-3 bg-[#444] hover:bg-[#555] text-white rounded-lg transition-colors font-medium border border-[#555]"
              >
                {alertModal.confirmText || (language === 'ka' ? 'დახურვა' : 'Close')}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default CartPage;
