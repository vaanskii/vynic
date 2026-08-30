import React, { createContext, useContext, useReducer, useEffect, useState } from 'react';

interface CartContextType {
  state: CartState;
  addItem: (item: CartItem) => void;
  removeItem: (id: string) => void;
  updateQuantity: (id: string, quantity: number) => void;
  clearCart: () => void;
  toggleCart: () => void;
  reloadCart: () => void;
}

interface MenuItem {
  price: number;
  imageUrl: string;
  translations: {
    en: { name: string };
    ka: { name: string };
  };
}

interface CartItem extends MenuItem {
  id: string;
  quantity: number;
}

interface CartState {
  items: CartItem[];
  totalItems: number;
  subtotal: number;  // Price before service fee
  serviceFee: number;  // 10% service fee
  totalPrice: number;  // Final total including service fee
  isOpen: boolean;
}

type CartAction =
  | { type: 'ADD_ITEM'; payload: MenuItem & { id: string } }
  | { type: 'REMOVE_ITEM'; payload: string }
  | { type: 'UPDATE_QUANTITY'; payload: { id: string; quantity: number } }
  | { type: 'CLEAR_CART' }
  | { type: 'TOGGLE_CART' }
  | { type: 'LOAD_CART'; payload: CartItem[] };

const initialState: CartState = {
  items: [],
  totalItems: 0,
  subtotal: 0,
  serviceFee: 0,
  totalPrice: 0,
  isOpen: false,
};

const cartReducer = (state: CartState, action: CartAction): CartState => {
  console.log('Cart reducer called with action:', action.type, action);

  // Helper function to calculate totals with service fee
  const calculateTotals = (items: CartItem[]) => {
    const totalItems = items.reduce((sum, item) => sum + item.quantity, 0);
    const subtotal = items.reduce((sum, item) => sum + (item.price * item.quantity), 0);
    const serviceFee = subtotal > 0 ? subtotal * 0.10 : 0; // 10% service fee only if there are items
    const totalPrice = subtotal + serviceFee;

    return { totalItems, subtotal, serviceFee, totalPrice };
  };

  switch (action.type) {
    case 'ADD_ITEM': {
      console.log('Processing ADD_ITEM for:', action.payload);
      const existingItem = state.items.find(item => item.id === action.payload.id);

      let updatedItems: CartItem[];
      if (existingItem) {
        console.log('Item already exists, incrementing quantity');
        updatedItems = state.items.map(item =>
          item.id === action.payload.id
            ? { ...item, quantity: item.quantity + 1 }
            : item
        );
      } else {
        console.log('New item, adding to cart');
        updatedItems = [...state.items, { ...action.payload, quantity: 1 }];
      }

      const totals = calculateTotals(updatedItems);
      console.log('Updated cart state:', { items: updatedItems, ...totals });

      return {
        ...state,
        items: updatedItems,
        ...totals,
      };
    }

    case 'REMOVE_ITEM': {
      const updatedItems = state.items.filter(item => item.id !== action.payload);
      const totals = calculateTotals(updatedItems);

      return {
        ...state,
        items: updatedItems,
        ...totals,
      };
    }

    case 'UPDATE_QUANTITY': {
      const updatedItems = state.items.map(item =>
        item.id === action.payload.id
          ? { ...item, quantity: Math.max(0, action.payload.quantity) }
          : item
      ).filter(item => item.quantity > 0);

      const totals = calculateTotals(updatedItems);

      return {
        ...state,
        items: updatedItems,
        ...totals,
      };
    }

    case 'CLEAR_CART':
      return {
        ...state,
        items: [],
        totalItems: 0,
        subtotal: 0,
        serviceFee: 0,
        totalPrice: 0,
      };

    case 'TOGGLE_CART':
      return {
        ...state,
        isOpen: !state.isOpen,
      };

    case 'LOAD_CART': {
      const totals = calculateTotals(action.payload);

      return {
        ...state,
        items: action.payload,
        ...totals,
      };
    }

    default:
      return state;
  }
};

const CartContext = createContext<CartContextType | undefined>(undefined);

export const CartProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [state, dispatch] = useReducer(cartReducer, initialState);
  const [isInitialized, setIsInitialized] = useState(false);

  // Load cart from localStorage on mount
  useEffect(() => {
    const savedCart = localStorage.getItem('vankisi-cart');
    const EXPIRATION_TIME = 2 * 60 * 60 * 1000; // 2 hours

    console.log('Loading cart from localStorage:', savedCart);
    if (savedCart) {
      try {
        const parsedCart = JSON.parse(savedCart);
        const now = Date.now();

        // Check if it's the new format with timestamp
        if (parsedCart.timestamp && parsedCart.items) {
          if (now - parsedCart.timestamp > EXPIRATION_TIME) {
            console.log('Cart expired, clearing...');
            localStorage.removeItem('vankisi-cart');
            // State is already initial (empty), so just set initialized
          } else {
            console.log('Parsed cart items:', parsedCart.items);
            if (Array.isArray(parsedCart.items) && parsedCart.items.length > 0) {
              dispatch({ type: 'LOAD_CART', payload: parsedCart.items });
            }
          }
        } else if (Array.isArray(parsedCart)) {
          // Legacy format (just array), treat as valid for now or expire?
          // Let's treat as valid to avoid clearing existing carts immediately, 
          // but next save will add timestamp.
          console.log('Legacy cart format found:', parsedCart);
          if (parsedCart.length > 0) {
            dispatch({ type: 'LOAD_CART', payload: parsedCart });
          }
        }
      } catch (error) {
        console.error('Error loading cart from localStorage:', error);
      }
    }
    setIsInitialized(true);
  }, []);

  // Save cart to localStorage whenever it changes (but only after initialization)
  useEffect(() => {
    if (isInitialized) {
      const cartData = {
        items: state.items,
        timestamp: Date.now()
      };
      console.log('Saving cart to localStorage:', cartData);
      localStorage.setItem('vankisi-cart', JSON.stringify(cartData));
    }
  }, [state.items, isInitialized]);

  const addItem = (item: MenuItem & { id: string }) => {
    console.log('Adding item to cart:', item);
    dispatch({ type: 'ADD_ITEM', payload: item });
  };

  const removeItem = (id: string) => {
    dispatch({ type: 'REMOVE_ITEM', payload: id });
  };

  const updateQuantity = (id: string, quantity: number) => {
    dispatch({ type: 'UPDATE_QUANTITY', payload: { id, quantity } });
  };

  const clearCart = () => {
    dispatch({ type: 'CLEAR_CART' });
  };

  const toggleCart = () => {
    dispatch({ type: 'TOGGLE_CART' });
  };

  const reloadCart = () => {
    console.log('Manually reloading cart from localStorage...');
    const savedCart = localStorage.getItem('vankisi-cart');
    if (savedCart) {
      try {
        const cartItems = JSON.parse(savedCart);
        console.log('Reloaded cart items:', cartItems);
        if (Array.isArray(cartItems)) {
          dispatch({ type: 'LOAD_CART', payload: cartItems });
        }
      } catch (error) {
        console.error('Error reloading cart from localStorage:', error);
      }
    } else {
      // If no cart in localStorage, clear the current cart
      dispatch({ type: 'CLEAR_CART' });
    }
  };

  return (
    <CartContext.Provider value={{
      state,
      addItem,
      removeItem,
      updateQuantity,
      clearCart,
      toggleCart,
      reloadCart, // 👈 Add reload function
    }}>
      {children}
    </CartContext.Provider>
  );
};

export const useCart = () => {
  const context = useContext(CartContext);
  if (context === undefined) {
    throw new Error('useCart must be used within a CartProvider');
  }
  return context;
};
