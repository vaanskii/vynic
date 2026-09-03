import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { useState } from "react";
import { BrowserRouter, Navigate, Route, Routes } from "react-router-dom";
import { LocaleProvider, localeHref, preferredLocale } from "./lib/i18n";
import { HomePage } from "./pages/HomePage";
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
        <AuthProvider>
          <AppRoutes />
        </AuthProvider>
      </BrowserRouter>
    </QueryClientProvider>
  );
}

export function AppRoutes() {
  return (
    <Routes>
      <Route path="/" element={<PublicHomeRedirect />} />
      <Route path="/product" element={<LocaleProvider><HomePage /></LocaleProvider>} />
      <Route path="/en" element={<LocaleProvider><HomePage /></LocaleProvider>} />
      <Route path="/ka" element={<LocaleProvider><HomePage /></LocaleProvider>} />
      <Route path="/login" element={<Navigate to="/admin/login" replace />} />
      <Route path="/admin/login" element={<LoginPage />} />
      <Route path="/admin" element={<ProtectedRoute><Shell /></ProtectedRoute>}>
        <Route index element={<OverviewPage />} />
        <Route path="organizations" element={<OrganizationsPage />} />
        <Route path="organizations/:organizationId" element={<OrganizationDetailPage />} />
        <Route path="venues" element={<VenuesPage />} />
        <Route path="venues/:venueId/:tab?" element={<VenueDetailPage />} />
        <Route path="plans" element={<PlansPage />} />
        <Route path="features" element={<FeaturesPage />} />
        <Route path="devices" element={<DevicesPage />} />
        <Route path="domains" element={<DomainsPage />} />
        <Route path="audit" element={<AuditPage />} />
        <Route path="*" element={<NotFoundPage />} />
      </Route>
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}

function PublicHomeRedirect() {
  const destination = localeHref(preferredLocale());

  return <Navigate to={destination} replace />;
}
