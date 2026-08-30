import { useEffect } from 'react';
import { useLocation } from 'react-router-dom';
import { useLanguage } from '../contexts/LanguageContext';

export const useDocumentTitle = () => {
  const location = useLocation();
  const { t } = useLanguage();

  useEffect(() => {
    // Get the current path without language prefix
    const path = location.pathname.replace(/^\/(en|ka)/, '') || '/';
    
    // Map paths to title keys
    const getTitleKey = (pathname: string): string => {
      switch (pathname) {
        case '/':
          return 'title.home';
        case '/about':
          return 'title.about';
        case '/menu':
          return 'title.menu';
        case '/reservations':
          return 'title.reservations';
        case '/contact':
          return 'title.contact';
        case '/login':
          return 'title.login';
        case '/register':
          return 'title.register';
        case '/reservation':
          return 'title.selecttable';
        default:
          return 'title.home';
      }
    };

    const titleKey = getTitleKey(path);
    const title = t(titleKey);
    
    // Update document title
    document.title = title;
  }, [location.pathname, t]);
};
