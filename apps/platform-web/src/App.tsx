import { isAdminHost } from "./site-origins";
import { AccessRequest } from "./customer/AccessRequest";
import { AcceptInvitation } from "./customer/AcceptInvitation";
import { InstallerDownloadPage } from "./customer/InstallerDownloadPage";
import { CustomerAuthPage } from "./customer/CustomerAuthPage";
import { CustomerDashboard } from "./customer/CustomerDashboard";
import { PortalRedirect } from "./customer/dashboard-routes";
import { OnboardingPage } from "./platform/pages/OnboardingPage";
import { PlatformUsersPage } from "./platform/pages/PlatformUsersPage";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { useEffect, useState } from "react";
import { BrowserRouter, Navigate, Route, Routes } from "react-router-dom";
import { LocaleProvider, localeHref, preferredLocale } from "./lib/i18n";
import { MarketingSite } from "./pages/MarketingSite";
import { AuthProvider } from "./platform/auth";
import { LoginPage } from "./platform/LoginPage";
import { NotFoundPage } from "./platform/NotFoundPage";
import { ProtectedRoute } from "./platform/ProtectedRoute";
import { Shell } from "./platform/Shell";
import { AuditPage } from "./platform/pages/AuditPage";
import { FeaturesPage } from "./platform/pages/FeaturesPage";
import { DevicesPage, DomainsPage } from "./platform/pages/InfrastructurePages";
import { OrganizationDetailPage } from "./platform/pages/OrganizationDetailPage";
import { OrganizationsPage } from "./platform/pages/OrganizationsPage";
import { OverviewPage } from "./platform/pages/OverviewPage";
import { PlansPage } from "./platform/pages/PlansPage";
import { VenuesPage } from "./platform/pages/VenuesPage";
import { VenueDetailPage } from "./platform/pages/venue/VenueDetailPage";

export function App() {
  const [queryClient] = useState(
    () =>
      new QueryClient({
        defaultOptions: {
          queries: { staleTime: 15_000, retry: 1 },
          mutations: { retry: false },
        },
      }),
  );

  return (
    <QueryClientProvider client={queryClient}>
      <BrowserRouter>
        <AppRoutes />
      </BrowserRouter>
    </QueryClientProvider>
  );
}

export function AppRoutes({
  hostname = window.location.hostname,
}: { hostname?: string } = {}) {
  if (isAdminHost(hostname))
    return (
      <AuthProvider>
        <AdminRoutes />
      </AuthProvider>
    );
  return (
    <Routes>
      <Route path="/" element={<PublicHomeRedirect />} />
      {/* Product site: home plus /pos, /manager, /floor-plan, /reservations. */}
      <Route
        path="/product"
        element={
          <LocaleProvider>
            <MarketingSite />
          </LocaleProvider>
        }
      />
      <Route
        path="/en/*"
        element={
          <LocaleProvider>
            <MarketingSite />
          </LocaleProvider>
        }
      />
      <Route
        path="/ka/*"
        element={
          <LocaleProvider>
            <MarketingSite />
          </LocaleProvider>
        }
      />
      <Route path="/features" element={<PublicSection id="product" />} />
      <Route path="/pricing" element={<PublicSection id="contact" />} />
      {/* Restaurant owners: CustomerAccount sessions only. */}
      <Route
        path="/login"
        element={<CustomerAuthPage key="login" mode="login" />}
      />
      <Route path="/request-access" element={<AccessRequest />} />
      <Route
        path="/signup"
        element={<Navigate to="/request-access" replace />}
      />
      <Route path="/invite/*" element={<AcceptInvitation />} />
      <Route path="/download" element={<InstallerDownloadPage />} />
      <Route path="/dashboard/:section?" element={<CustomerDashboard />} />
      <Route
        path="/start"
        element={<Navigate to="/request-access" replace />}
      />
      <Route path="/portal/*" element={<PortalRedirect />} />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}

/** Product pages are sections of the home page in the visitor's language. */
function PublicSection({ id }: { id: string }) {
  return (
    <Navigate
      to={{ pathname: localeHref(preferredLocale()), hash: `#${id}` }}
      replace
    />
  );
}

function PublicHomeRedirect() {
  const destination = localeHref(preferredLocale());

  return <Navigate to={destination} replace />;
}

function AdminRoutes() {
  useEffect(() => {
    const oldTitle = document.title;
    const oldLang = document.documentElement.lang;
    document.title = "Vynic Platform Admin";
    document.documentElement.lang = "en";
    const robots = document.createElement("meta");
    robots.name = "robots";
    robots.content = "noindex, nofollow";
    document.head.appendChild(robots);
    return () => {
      document.title = oldTitle;
      document.documentElement.lang = oldLang;
      robots.remove();
    };
  }, []);
  return (
    <Routes>
      <Route path="/admin/*" element={<Navigate to="/" replace />} />
      {/* Vynic staff: PlatformUser sessions only. */}
      <Route path="/login" element={<LoginPage />} />
      <Route
        path="/"
        element={
          <ProtectedRoute>
            <Shell />
          </ProtectedRoute>
        }
      >
        <Route index element={<OverviewPage />} />
        <Route path="organizations" element={<OrganizationsPage />} />
        <Route
          path="organizations/:organizationId"
          element={<OrganizationDetailPage />}
        />
        <Route path="venues" element={<VenuesPage />} />
        <Route path="venues/:venueId/:tab?" element={<VenueDetailPage />} />
        <Route path="onboarding/:venueId?" element={<OnboardingPage />} />
        <Route path="users" element={<PlatformUsersPage />} />
        <Route path="plans" element={<PlansPage />} />
        <Route path="features" element={<FeaturesPage />} />
        <Route path="devices" element={<DevicesPage />} />
        <Route path="domains" element={<DomainsPage />} />
        <Route path="audit" element={<AuditPage />} />
        <Route path="*" element={<NotFoundPage />} />
      </Route>
    </Routes>
  );
}
