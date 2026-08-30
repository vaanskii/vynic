import type { ReactNode } from 'react';
import { Navigate, useParams } from 'react-router-dom';
import { useAuth } from '../contexts/AuthContext';

interface GuestRouteProps {
  children: ReactNode;
}

const GuestRoute: React.FC<GuestRouteProps> = ({ children }) => {
  const { isAuthenticated, loading } = useAuth();
  const params = useParams<{ lang: string }>();
  const currentLang = params.lang || 'en';

  // Show loading spinner while checking authentication
  if (loading) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-[#f4f1e8] to-[#e9ddd0] flex items-center justify-center">
        <div className="text-center">
          <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-[#a89763] mx-auto"></div>
          <p className="mt-4 text-[#333]">Loading...</p>
        </div>
      </div>
    );
  }

  if (isAuthenticated) {
    // Redirect to home page if already authenticated
    return <Navigate to={`/${currentLang}`} replace />;
  }

  return <>{children}</>;
};

export default GuestRoute;
