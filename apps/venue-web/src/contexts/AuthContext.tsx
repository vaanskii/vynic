import React, { createContext, useContext, useState, useEffect } from 'react';
import { authService } from '../services/api';

interface User {
  id: string;
  phone: string;
  firstName?: string;
  lastName?: string;
  email?: string;
  role?: 'USER' | 'SUPER_ADMIN';
}

interface AuthContextType {
  user: User | null;
  loading: boolean;
  login: (identifier: string, password: string) => Promise<boolean>;
  register: (data: {
    phone: string;
    password: string;
    email: string;
    firstName?: string;
    lastName?: string;
  }) => Promise<boolean>;
  logout: () => Promise<void>;
  refreshUser: () => Promise<void>;
  isAuthenticated: boolean;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);

  const refreshUser = async () => {
    try {
      const result = await authService.verify();
      if (result.isAuthenticated && result.user) {
        setUser({
          id: result.user.id,
          phone: result.user.phone,
          firstName: result.user.firstName,
          lastName: result.user.lastName,
          email: result.user.email,
          role: result.user.role,
        });
      }
    } catch (error) {
      console.error('Failed to refresh user:', error);
    }
  };

  useEffect(() => {
    // Check if user is already logged in by verifying the token
    const checkAuthStatus = async () => {
      try {
        // Get CSRF token first
        await authService.getCsrfToken();
        await refreshUser();
      } catch (error) {
        console.error('Auth check failed:', error);
        // User is not authenticated, which is fine
      } finally {
        setLoading(false);
      }
    };

    checkAuthStatus();
  }, []);

  const login = async (identifier: string, password: string): Promise<boolean> => {
    try {
      const response = await authService.signin({ identifier, password });
      if (response.message === 'Signin successful') {
        await refreshUser();
        return true;
      }
      return false;
    } catch (error) {
      console.error('Login failed:', error);
      return false;
    }
  };

  const register = async (data: {
    phone: string;
    password: string;
    email: string;
    firstName?: string;
    lastName?: string;
  }): Promise<boolean> => {
    try {
      const response = await authService.signup(data);
      if (response.message === 'Signup successful') {
        await refreshUser();
        return true;
      }
      return false;
    } catch (error) {
      console.error('Registration failed:', error);
      return false;
    }
  };

  const logout = async (): Promise<void> => {
    try {
      await authService.logout();
      setUser(null);
    } catch (error) {
      console.error('Logout error:', error);
      // Still clear user state even if request fails
      setUser(null);
    }
  };

  const value: AuthContextType = {
    user,
    loading,
    login,
    register,
    logout,
    refreshUser,
    isAuthenticated: !!user,
  };

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
};

export const useAuth = () => {
  const context = useContext(AuthContext);
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
};
