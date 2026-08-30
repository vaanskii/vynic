import { useState, useEffect } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { useLanguage } from '../contexts/LanguageContext';
import { useAuth } from '../contexts/AuthContext';
import { tableService, userService } from '../services/api';
import { useCart } from '../contexts/CartContext';

// Import Logo SVG
const LogoSVG = ({ className }: { className?: string }) => (
  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 800" className={className}>
    <path fill="#ae895e" d="M133 151L151 167Q167 177 187 184L226 195L231 195L236 197L241 197L246 199L264 202L268 204L272 204L302 214Q329 226 348 248L350 251L363 269L376 301L377 308L382 321L382 325L384 328L391 354L393 357L405 396L405 401L407 408L408 434L407 435L407 445L406 446L405 457L398 478L397 477L399 466L399 439L395 419L393 416L393 413L391 410L391 407L386 395L384 385L382 383L373 353L368 342L366 333L361 322L361 319L359 317L359 314Q347 286 327 268L324 266Q309 252 288 245L267 239L256 238L250 236L245 236L239 234L233 234L208 229L192 224L170 213L167 213Q168 210 165 211L147 196L135 174Q136 167 133 165L133 151Z" />
    <path fill="#ae895e" d="M149 228L151 229Q150 232 153 231L171 245L198 256L214 259L218 261L225 261L230 263L247 265L257 268L263 268L293 277L313 288L328 303Q341 317 347 339L336 328L314 314L296 307L265 300L257 300L245 297L228 295L201 288Q178 280 163 264Q150 250 149 228Z" />
    <path fill="#ae895e" d="M176 299L198 311L218 318L238 322L245 322L272 327L278 327L297 331L317 339L332 350L332 352Q335 351 334 354L345 368L356 390L361 403L361 406L384 463L384 466L402 510L402 513L409 528L412 539L416 546L416 549L425 570L425 573Q428 574 427 571L509 367L512 356L512 350L506 339L495 334L487 334L488 329L586 329L586 334L584 334Q567 337 558 349L548 366Q545 378 539 387L537 395L516 442L516 445L514 447L507 466L505 468L505 471L500 479L498 487Q489 501 484 520L482 522L471 551L457 581L432 642L430 644L428 644L417 644L415 643Q413 645 412 643L411 638L404 623L404 620L393 595L393 592L388 582L388 579L386 577L384 568L382 566L373 543L373 540L371 538L363 515L359 508L359 505L354 495L352 487L345 472L345 469L331 436L323 413L311 386L302 373Q299 374 300 372L295 368Q296 365 294 366L283 359L264 352L235 345L229 345L216 341L201 333L186 320L184 317L176 304L176 299Z" />
  </svg>
);

const Checkout = () => {
  const { language } = useLanguage();
  const dataLang: 'en' | 'ka' = language === 'ka' ? 'ka' : 'en';
  const { user } = useAuth();
  const { reloadCart } = useCart();
  const navigate = useNavigate();
  const params = useParams<{ lang: string }>();
  const currentLang = params.lang || language;

  const [isProcessing, setIsProcessing] = useState(false);
  const [reservationData, setReservationData] = useState<any>(null);
  const [cartItems, setCartItems] = useState<any[]>([]);
  const [preOrderTotal, setPreOrderTotal] = useState(0);
  const [userProfile, setUserProfile] = useState<any>(null);

  // Formatting strings
  const textStrings = {
    ka: {
      title: "გადახდა & დადასტურება",
      secure: "უსაფრთხო ტრანზაქცია",
      summary: "ჯავშნის დეტალები",
      menuSummary: "შერჩეული მენიუ",
      redirectTitle: "უსაფრთხო გადახდა",
      redirectDesc: "თქვენი ჯავშნისა და შერჩეული მენიუს დასადასტურებლად გადახვალთ საქართველოს ბანკის (BOG) დაცულ გვერდზე.",
      payBtnBOG: "გაგრძელება გადახდაზე",
      depositAmount: 0,
      total: "სულ გადასახდელი",
      date: "თარიღი & დრო",
      table: "მაგიდა",
      guest: "სტუმარი",
      menuTotal: "მენიუს ჯამი",
      depositStr: "დეპოზიტი (ჯავშანი)"
    },
    en: {
      title: "Payment & Confirmation",
      secure: "Secure Transaction",
      summary: "Reservation Summary",
      menuSummary: "Selected Menu",
      redirectTitle: "Secure Payment",
      redirectDesc: "To confirm your reservation and selected menu, you will be redirected to the secure Bank of Georgia (BOG) payment gateway.",
      payBtnBOG: "Proceed to Payment",
      depositAmount: 0,
      total: "Grand Total",
      date: "Date & Time",
      table: "Table",
      guest: "Guests",
      menuTotal: "Menu Total",
      depositStr: "Deposit (Booking)"
    }
  };

  const t = textStrings[language as 'ka' | 'en'];

  useEffect(() => {
    // Load reservation data
    const savedReservationData = localStorage.getItem('vankisi_reservation');
    if (savedReservationData) {
      setReservationData(JSON.parse(savedReservationData));
    } else {
      // Fallback
      const res = localStorage.getItem('reservationData');
      if (res) setReservationData(JSON.parse(res));
    }

    // Prioritize reservation-specific pre-order, fallback to general cart
    const preorderRaw = localStorage.getItem('vankisi_preorder');
    const cartRaw = localStorage.getItem('vankisi-cart');
    
    let items = [];
    try {
      const pItems = preorderRaw ? JSON.parse(preorderRaw) : [];
      const cItems = cartRaw ? JSON.parse(cartRaw) : [];
      
      // Use the one that has items, prioritizing preorder
      items = (Array.isArray(pItems) && pItems.length > 0) ? pItems : (Array.isArray(cItems) ? cItems : []);
      
      if (items.length > 0) {
        setCartItems(items);
        const subtotal = items.reduce((sum: number, i: any) => sum + ((i.price || 0) * (i.quantity || 1)), 0);
        const fee = subtotal > 0 ? subtotal * 0.10 : 0;
        setPreOrderTotal(subtotal + fee);
      }
    } catch (err) {
      console.error("Cart parse error:", err);
    }
  }, []);

  useEffect(() => {
    if (user) {
      userService.getProfile().then(profile => {
        setUserProfile(profile);
      }).catch(err => console.error("Could not fetch profile", err));
    }
  }, [user]);

  const handleBogPayment = async () => {
    // Removed mandatory authentication check. If guest info is provided, we proceed.

    if (!reservationData) {
      alert(language === 'ka' ? 'ჯავშნის ინფორმაცია ვერ მოიძებნა.' : 'Reservation info not found.');
      return;
    }

    try {
      setIsProcessing(true);

      const customerName = user 
        ? (userProfile?.firstName && userProfile?.lastName ? `${userProfile.firstName} ${userProfile.lastName}` : user.phone || reservationData.customerName || 'Vankisi Guest')
        : (reservationData.customerName || 'Vankisi Guest');

      const email = user?.email || userProfile?.email || 'guest@vankisi.com';

      const paymentPayload = {
        selectedTables: Array.isArray(reservationData.selectedTables) ? reservationData.selectedTables : [],
        selectedDate: String(reservationData.resDate || reservationData.selectedDate || ''),
        selectedTime: String(reservationData.resTime || reservationData.selectedTime || ''),
        menuItems: cartItems.map(item => ({
          id: String(item.id),
          quantity: Number(item.quantity),
          price: Number(item.price)
        })),
        totalAmount: Number(grandTotal),
        customerEmail: String(email),
        customerName: String(customerName),
        customerPhone: String(user?.phone || userProfile?.phone || reservationData.customerPhone || ''),
        userId: user?.id ? String(user.id) : undefined,
        notes: `BOG Payment - Tables: ${(reservationData.selectedTables || []).join(', ')}`,
        language: String(language),
      };

      const result = await tableService.createBogPayment(paymentPayload);

      if (result.validation && Math.abs(result.validation.serverCalculatedTotal - paymentPayload.totalAmount) > 0.01) {
        if (result.validation.correctedCartItems) {
           localStorage.setItem('vankisi-cart', JSON.stringify(result.validation.correctedCartItems));
           reloadCart?.();
        }
        alert(language === 'ka' ? 'მოხდა ფასის კორექტირება სერვერთან შეუსაბამობის გამო.' : 'A price mismatch was corrected by the server.');
      }

      if (result.redirect_url) {
        window.location.href = result.redirect_url;
      } else {
        throw new Error('No redirect URL from BOG');
      }

    } catch (error) {
      console.error(error);
      alert(language === 'ka' ? 'BOG გადახდის შექმნისას მოხდა შეცდომა.' : 'Error creating BOG payment.');
    } finally {
      setIsProcessing(false);
    }
  };

  const grandTotal = preOrderTotal + t.depositAmount;

  return (
    <div className="animate-fade-up-init pt-32 pb-32 min-h-screen bg-[#050505] relative text-white">
      <div className="max-w-7xl mx-auto px-6 md:px-8">
        
        <div className="flex items-center gap-4 mb-12 border-b border-white/5 pb-8">
          <button 
            onClick={() => navigate(`/${currentLang}`)}
            className="w-10 h-10 rounded-full border border-white/10 flex items-center justify-center hover:bg-white/5 cursor-pointer transition-colors"
          >
            <svg className="w-5 h-5 text-white/60" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" /></svg>
          </button>
          <div>
            <h1 className="text-3xl font-light text-white/95">{t.title}</h1>
            <p className="text-[#ae895e] text-xs tracking-[0.3em] uppercase mt-2 flex items-center gap-2">
              <svg className="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" /></svg> {t.secure}
            </p>
          </div>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-12 gap-12 lg:gap-20">
          
          {/* Left Side: Order Summary */}
          <div className="lg:col-span-5 order-2 lg:order-1">
            <div className="bg-[#0a0a0a] border border-white/5 p-8 relative overflow-hidden shadow-2xl">
              <div className="absolute top-0 right-0 p-4 opacity-5 pointer-events-none">
                <LogoSVG className="w-40 h-40" />
              </div>
              
              <h4 className="text-xs uppercase tracking-[0.3em] text-[#ae895e] mb-8 font-medium">{t.summary}</h4>
              
              {/* Reservation Basics */}
              <div className="space-y-4 mb-8 border-b border-white/5 pb-8">
                <div className="flex justify-between items-center text-sm">
                  <span className="text-white/40 font-light">{t.date}</span>
                  <span className="text-white/90">{reservationData?.resDate || reservationData?.selectedDate || (language === 'ka' ? 'დღეს' : 'Today')}, {reservationData?.resTime || reservationData?.selectedTime || ''}</span>
                </div>
                <div className="flex justify-between items-center text-sm">
                  <span className="text-white/40 font-light">{t.table}</span>
                  <span className="text-white/90">{(reservationData?.selectedTables || []).join(', ') || 'Auto'}</span>
                </div>
                <div className="flex justify-between items-center text-sm">
                  <span className="text-white/40 font-light">{t.guest}</span>
                  <span className="text-white/90">{reservationData?.resGuests || '2'}</span>
                </div>
              </div>

              {/* Pre-Order Details */}
              {cartItems.length > 0 && (
                <div className="mb-8 border-b border-white/5 pb-8">
                  <span className="text-[10px] uppercase tracking-[0.2em] text-[#ae895e] mb-6 block font-medium">
                    {t.menuSummary}
                  </span>
                  <div className="space-y-4 max-h-64 overflow-y-auto custom-scrollbar">
                    {cartItems.map((item, idx) => (
                      <div key={idx} className="flex justify-between text-sm font-light group">
                        <div className="flex gap-4 items-baseline">
                          <span className="text-[#ae895e] font-medium text-xs bg-[#ae895e]/10 px-2 py-0.5 rounded">{item.quantity}x</span>
                          <span className="text-white/80 leading-snug">{item.name || item.translations?.[dataLang]?.name}</span>
                        </div>
                        <span className="text-white/60 whitespace-nowrap ml-4">{item.price * item.quantity}₾</span>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {/* Totals */}
              <div className="space-y-4 relative z-10">
                {cartItems.length > 0 && (
                  <>
                    <div className="flex justify-between items-center text-sm">
                      <span className="text-white/40 font-light">{t.menuTotal}</span>
                      <span className="text-white/80">{(preOrderTotal / 1.1).toFixed(2)} ₾</span>
                    </div>
                    <div className="flex justify-between items-center text-sm">
                      <span className="text-white/40 font-light">{language === 'ka' ? 'მომსახურების საკომისიო (10%)' : 'Service Fee (10%)'}</span>
                      <span className="text-white/80">{(preOrderTotal - (preOrderTotal / 1.1)).toFixed(2)} ₾</span>
                    </div>
                  </>
                )}
                <div className="flex justify-between items-center pt-6 mt-4 border-t border-[#ae895e]/30">
                  <span className="text-lg font-light uppercase tracking-widest text-white/90">{t.total}</span>
                  <span className="text-3xl font-light text-[#ae895e]">{grandTotal.toFixed(2)} ₾</span>
                </div>
              </div>
            </div>
          </div>

          {/* Right Side: Payment Gateway Redirect Area */}
          <div className="lg:col-span-7 order-1 lg:order-2">
            <div className="bg-gradient-to-br from-[#0a0a0a] to-[#050505] border border-white/10 p-8 md:p-16 shadow-2xl relative flex flex-col items-center justify-center text-center min-h-full">
              
              {/* Glowing Lock Icon */}
              <div className="w-24 h-24 rounded-full border border-[#ae895e]/30 flex items-center justify-center mb-10 relative">
                 <div className="absolute inset-0 rounded-full border border-[#ae895e] animate-ping opacity-20"></div>
                 <svg className="w-8 h-8 text-[#ae895e]" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" /></svg>
              </div>

              <h3 className="text-3xl font-light text-white/95 mb-6 tracking-wide">
                {t.redirectTitle}
              </h3>
              
              <p className="text-white/50 leading-loose font-light max-w-md mb-12 text-sm md:text-base">
                {t.redirectDesc}
              </p>

              <button 
                onClick={handleBogPayment}
                disabled={isProcessing}
                className="w-full max-w-md py-5 bg-gradient-to-r from-[#ae895e] to-[#cba97f] text-black uppercase tracking-[0.2em] text-xs font-bold hover:shadow-[0_0_40px_rgba(174,137,94,0.4)] hover:scale-105 transition-all duration-500 flex items-center justify-center gap-4 rounded-sm disabled:opacity-50 disabled:cursor-not-allowed cursor-pointer"
              >
                {isProcessing ? (
                  <svg className="animate-spin w-5 h-5 text-black" fill="none" viewBox="0 0 24 24">
                    <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                    <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                  </svg>
                ) : (
                  <>{t.payBtnBOG} <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17 8l4 4m0 0l-4 4m4-4H3" /></svg></>
                )}
              </button>
              
              {/* BOG Branding Hint */}
              <div className="mt-12 flex items-center justify-center gap-4 opacity-40">
                <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 10h18M7 15h1m4 0h1m-7 4h12a3 3 0 003-3V8a3 3 0 00-3-3H6a3 3 0 00-3 3v8a3 3 0 003 3z" /></svg>
                <span className="text-xs tracking-[0.2em] uppercase font-bold border-l border-white/20 pl-4">
                  Bank of Georgia Gateway
                </span>
              </div>

            </div>
          </div>

        </div>
      </div>
    </div>
  );
};

export default Checkout;
