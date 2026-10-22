export interface MenuItemVariant {
  id: string;
  size: number;
  price: number;
}

export interface MenuItem {
  id: string;
  price: number;
  imageUrl: string;
  nameEn: string;
  nameKa: string;
  subcategorySlug?: string;
  subcategoryNameEn?: string;
  subcategoryNameKa?: string;
  hasVariants?: boolean;
  variants?: MenuItemVariant[];
}

export interface MenuSection {
  type: string;
  id?: string;
  slug: string;
  nameEn: string;
  nameKa: string;
  items: MenuItem[];
}

export interface MenuCategory {
  id?: string;
  slug: string;
  nameEn: string;
  nameKa: string;
  hasSubcategories: boolean;
  displayMode: 'grouped' | 'flat';
  items: MenuItem[];
  sections: MenuSection[];
  itemCount: number;
}

export interface PreOrderItem {
  id: string;
  name: string;
  price: number;
  quantity: number;
}
