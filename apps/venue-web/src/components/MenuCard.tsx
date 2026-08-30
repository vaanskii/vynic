import React from 'react';
import { useLanguage } from '../contexts/LanguageContext';
import styles from '../css/MenuCard.module.css';

interface MenuItem {
  id: string; // 👈 Add ID field
  price: number;
  imageUrl: string;
  translations: {
    en: { name: string };
    ka: { name: string };
  };
}

interface MenuCardProps {
  item: MenuItem;
  onAddToCart?: (item: MenuItem) => void;
}

const MenuCard: React.FC<MenuCardProps> = ({ item, onAddToCart }) => {
  const { language } = useLanguage();
  const dataLang: 'en' | 'ka' = language === 'ka' ? 'ka' : 'en';

  const handleAddToCart = () => {
    if (onAddToCart) {
      onAddToCart(item);
    }
  };

  return (
    <div className={`bg-gradient-to-r from-[#a89763] to-[#c0ad7b] rounded-lg shadow-md overflow-hidden hover:shadow-lg transition-shadow duration-300 flex flex-col h-full ${styles.menuCard}`}>
      {/* Image Container */}
      <div className="relative h-48 w-full overflow-hidden">
        <img
          src={item.imageUrl}
          alt={item.translations[dataLang].name}
          className={`w-full h-full object-cover ${styles.cardImage}`}
          loading="lazy"
        />
        {/* Price Badge */}
        <div className={`absolute top-3 right-3 bg-[#c0ad7b] text-[#222] px-2 py-1 rounded-full text-sm font-bold shadow-lg ${styles.priceTag}`}>
          ₾{item.price}
        </div>
      </div>

      {/* Content Container */}
      <div className="p-4 flex flex-col justify-between flex-grow">
        {/* Title */}
        <h3 className="text-lg font-semibold text-gray-800 mb-3 line-clamp-2 leading-tight">
          {item.translations[dataLang].name}
        </h3>

        {/* Add to Cart Button - Only show if onAddToCart is provided */}
        {onAddToCart && (
          <button
            onClick={handleAddToCart}
            className={`w-full bg-[#222] hover:bg-[#333] cursor-pointer text-white font-medium py-2 px-4 rounded-lg transition-colors duration-200 ${styles.addButton}`}
          >
            {language === 'ka' ? 'კალათაში დამატება' : 'Add to Cart'}
          </button>
        )}
      </div>
    </div>
  );
};

export default MenuCard;
