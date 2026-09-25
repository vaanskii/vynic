import { Routes, Route, Navigate, useLocation, useParams } from 'react-router-dom'
import { useLanguage } from './contexts/LanguageContext';
import { useAuth } from './contexts/AuthContext';
// import { useState } from 'react'
import './App.css'
import Header from './components/Header'
import Navigation from './components/Navigation'
import Menu from './pages/Menu'
import Contact from './pages/Contact'
import Atmosphere from './pages/Atmosphere'
import CartPage from './pages/Cart'
import PaymentSuccess from './pages/PaymentSuccess'
import PaymentFail from './pages/PaymentFail'
import Profile from './pages/Profile'
import Checkout from './pages/Checkout'
import ProtectedRoute from './components/ProtectedRoute'
import Footer from './components/Footer'
import ComingSoonModal from './components/ComingSoonModal'
import { useEffect } from 'react'
import { useReservationSession } from './hooks/useReservationSession';
import Map3DPage from './pages/Map3DPage'
import { reservationTablesPath } from './routes/reservation'
import { clearStaleTableStepOnHome, loadRes, todayIso } from './utils/reservationStorage'
import { isComingSoonMode } from './config/siteMode'
import { isHomePath, languageFromPath } from './utils/isHomePath'

function LegacyMapRedirect({ floor2 = false }: { floor2?: boolean }) {
  const { lang } = useParams()
  const date = loadRes().resDate || loadRes().selectedDate || todayIso()
  return (
    <Navigate
      to={reservationTablesPath(lang === 'ka' ? 'ka' : 'en', { date, floor: floor2 ? 'floor2' : undefined })}
      replace
    />
  )
}

const ScrollToTop = () => {
  const { pathname, state } = useLocation();

  useEffect(() => {
    // If the transition state specifically says to preserve scroll, skip scrolling to top
    if (state && (state as any).preserveScroll) {
      return;
    }
    window.scrollTo(0, 0);
  }, [pathname, state]);

  return null;
};

function App() {
  const { language } = useLanguage();
  const { user, loading } = useAuth();
  const location = useLocation();

  // Track reservation session activity and expiration
  useReservationSession();

  useEffect(() => {
    clearStaleTableStepOnHome(location.pathname);
  }, [location.pathname]);

  if (isComingSoonMode && !isHomePath(location.pathname)) {
    const lang = languageFromPath(location.pathname) || language;
    return <Navigate to={`/${lang}`} replace />;
  }

  // Redirect to complete profile if user is logged in but has no name
  if (
    !isComingSoonMode &&
    !loading &&
    user &&
    (!user.firstName || !user.lastName) &&
    !location.pathname.includes('complete-profile')
  ) {
    return <Navigate to={`/${language}/complete-profile`} replace />;
  }

  return (
    <>
      <ScrollToTop />
      <Navigation />
      <Routes>
        {/* Root redirects to default language */}
        <Route path="/" element={<Navigate to="/en" replace />} />

        {/* Language-specific routes */}
        <Route path="/:lang" element={
          <>
            <Header />
            <Footer />
          </>
        } />
        <Route path="/:lang/menu" element={<Menu />} />
        <Route path="/:lang/atmosphere" element={<Atmosphere />} />
        <Route path="/:lang/cart" element={<CartPage />} />
        <Route path="/:lang/contact" element={<Contact />} />
        <Route path="/:lang/profile" element={
          <ProtectedRoute>
            <Profile />
          </ProtectedRoute>
        } />
        <Route path="/:lang/checkout" element={<Checkout />} />
        <Route path="/:lang/payment-success" element={<PaymentSuccess />} />
        <Route path="/:lang/payment-fail" element={<PaymentFail />} />
        <Route path="/:lang/reservation/tables/:date/floor-2" element={<Map3DPage initialFloor="floor2" />} />
        <Route path="/:lang/reservation/tables/floor-2" element={<Map3DPage initialFloor="floor2" />} />
        <Route path="/:lang/reservation/tables/:date" element={<Map3DPage />} />
        <Route path="/:lang/reservation/tables" element={<Map3DPage />} />
        <Route path="/:lang/map-3d" element={<LegacyMapRedirect />} />
        <Route path="/:lang/map-3d-floor2" element={<LegacyMapRedirect floor2 />} />

        {/* Fallback routes without language prefix */}
        <Route path="/menu" element={<Menu />} />
        <Route path="/atmosphere" element={<Atmosphere />} />
        <Route path="/cart" element={<CartPage />} />
        <Route path="/contact" element={<Contact />} />
        <Route path="/checkout" element={<Checkout />} />
        <Route path="/profile" element={
          <ProtectedRoute>
            <Profile />
          </ProtectedRoute>
        } />
        <Route path="/payment-success" element={<PaymentSuccess />} />
        <Route path="/payment-fail" element={<PaymentFail />} />
        <Route path="/reservation/tables" element={<Navigate to="/en/reservation/tables" replace />} />
        <Route path="/reservation/tables/floor-2" element={<Navigate to="/en/reservation/tables/floor-2" replace />} />
        <Route path="/map-3d" element={<Navigate to="/en/reservation/tables" replace />} />
        <Route path="/map-3d-floor2" element={<Navigate to="/en/reservation/tables/floor-2" replace />} />

        {/* Redirect any unmatched routes to home */}
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>

      {isComingSoonMode && isHomePath(location.pathname) && <ComingSoonModal />}
    </>
  )
}

export default App
