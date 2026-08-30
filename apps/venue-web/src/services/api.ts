import axios from 'axios';

// Base URL for the API - works with localhost and IP addresses
const getApiBaseUrl = () => {
  const hostname = window.location.hostname;
  const protocol = window.location.protocol;

  // For local development only (localhost and IP addresses), use port 3000
  if (hostname === 'localhost' || hostname.match(/^\d+\.\d+\.\d+\.\d+$/)) {
    return `${protocol}//${hostname}:3000/api`;
  }

  // Check if API URL is provided via environment variable (Standard for Vercel/Netlify)
  if (import.meta.env.VITE_API_URL) {
    return import.meta.env.VITE_API_URL;
  }

  // Fallback: If no env var, assume Nginx/Same-Domain proxy
  return '/api';
};

const API_BASE_URL = getApiBaseUrl();

// Create axios instance
const api = axios.create({
  baseURL: API_BASE_URL,
  withCredentials: true, // Important for HTTP-only cookies
  headers: {
    'Content-Type': 'application/json',
  },
});

// CSRF token management
let csrfToken: string | null = null;

// Add request interceptor to include CSRF token
api.interceptors.request.use((config) => {
  if (csrfToken && ['post', 'put', 'patch', 'delete'].includes(config.method?.toLowerCase() || '')) {
    config.headers['X-CSRF-Token'] = csrfToken;
  }
  return config;
});

// Auth interfaces
export type UserRole = 'USER' | 'SUPER_ADMIN';

export interface AuthData {
  identifier: string;
  password: string;
}

export interface RegisterData {
  phone: string;
  email: string;
  password: string;
  firstName?: string;
  lastName?: string;
}

export interface AuthResponse {
  message: string;
}

export interface VerifyResponse {
  isAuthenticated: boolean;
  user?: {
    id: string;
    phone: string;
    firstName?: string;
    lastName?: string;
    email?: string;
    role?: UserRole;
  };
}

export interface CsrfResponse {
  csrfToken: string;
}

// Auth service functions
export const authService = {
  // Get CSRF token
  getCsrfToken: async (): Promise<void> => {
    try {
      const response = await api.get<CsrfResponse>('/auth/csrf');
      csrfToken = response.data.csrfToken;
    } catch (error) {
      console.error('Failed to get CSRF token:', error);
    }
  },

  // User registration
  signup: async (data: RegisterData): Promise<AuthResponse> => {
    await authService.getCsrfToken(); // Get CSRF token before signup
    const response = await api.post('/auth/signup', data);
    return response.data;
  },

  // User login
  signin: async (data: AuthData): Promise<AuthResponse> => {
    await authService.getCsrfToken(); // Get CSRF token before signin
    const response = await api.post('/auth/signin', data);
    return response.data;
  },

  // User logout
  logout: async (): Promise<AuthResponse> => {
    const response = await api.post('/auth/logout');
    csrfToken = null; // Clear CSRF token on logout
    return response.data;
  },

  // Verify if user is authenticated
  verify: async (): Promise<VerifyResponse> => {
    const response = await api.get('/auth/verify');
    return response.data;
  },

  // Change password
  changePassword: async (data: { oldPassword: string; newPassword: string }): Promise<AuthResponse> => {
    await authService.getCsrfToken();
    const response = await api.post('/auth/change-password', data);
    return response.data;
  },
};

// Menu service functions
export const menuService = {
  // Get all menu categories
  getAllCategories: async () => {
    const response = await api.get('/menu');
    return response.data;
  },

  // Get category by slug
  getCategoryBySlug: async (slug: string) => {
    const response = await api.get(`/menu/${slug}`);
    return response.data;
  },
};

// Table service functions
export const tableService = {
  // Get all tables
  getAllTables: async () => {
    const response = await api.get('/tables');
    return response.data;
  },

  // Get table availability for a specific date
  getTableAvailability: async (date: string) => {
    const response = await api.get(`/tables/availability?date=${date}`);
    return response.data;
  },

  // Check if a specific table is available
  checkTableAvailability: async (tableNumber: string, date: string, timeSlot: string) => {
    const response = await api.get(`/tables/availability/${tableNumber}?date=${date}&timeSlot=${timeSlot}`);
    return response.data;
  },

  // Create a reservation with single or multiple tables and optional menu items
  createReservation: async (data: {
    selectedTables: string[]; // Always array, even for single table
    selectedDate: string;
    selectedTime: string;
    menuItems?: Array<{
      id: string;
      quantity: number;
      price: number;
    }>; // Optional menu items
    totalAmount?: number; // Optional total amount
    customerName?: string;
    customerEmail?: string;
    customerPhone?: string;
    userId?: string;
    notes?: string;
  }) => {
    const response = await api.post('/tables/reservations', data);
    return response.data;
  },

  // Get reservations for a specific date for admin view
  getReservationsForDate: async (date: string) => {
    const response = await api.get(`/tables/reservations?date=${date}`);
    return response.data;
  },

  // Create BOG payment order
  createBogPayment: async (data: {
    selectedTables: string[];
    selectedDate: string;
    selectedTime: string;
    menuItems?: Array<{
      id: string;
      quantity: number;
      price: number;
    }>;
    totalAmount: number;
    customerName?: string;
    customerEmail?: string;
    customerPhone?: string;
    userId?: string;
    notes?: string;
    language?: string; // Add language parameter
  }) => {
    await authService.getCsrfToken(); // Get CSRF token before payment
    const response = await api.post('/bog/create-order', data);
    return response.data;
  },
};

// User service functions
export const userService = {
  getProfile: async () => {
    const response = await api.get('/user/profile');
    return response.data;
  },

  // Get user reservations (only confirmed ones)
  getReservations: async () => {
    const response = await api.get('/user/reservations');
    return response.data;
  },

  updateProfile: async (data: { firstName: string; lastName: string }) => {
    const response = await api.patch('/user/profile', data);
    return response.data;
  },
};

export default api;
