import type { MenuCategory, MenuItem, MenuSection } from '../types/menu';

interface LegacyTranslation { language: string; name: string; }
interface LegacyItem {
  id: string;
  price: number;
  imageUrl?: string;
  translations?: LegacyTranslation[];
  nameEn?: string;
  nameKa?: string;
  subcategorySlug?: string;
  subcategoryNameEn?: string;
  subcategoryNameKa?: string;
  hasVariants?: boolean;
  variants?: { id: string; size: number; price: number }[];
}
interface LegacyCategory {
  id?: number | string;
  slug: string;
  translations?: LegacyTranslation[];
  nameEn?: string;
  nameKa?: string;
  items?: LegacyItem[];
  sections?: MenuSection[];
  hasSubcategories?: boolean;
  displayMode?: 'grouped' | 'flat';
  itemCount?: number;
  subcategories?: unknown[];
}

function mapLegacyItem(item: LegacyItem): MenuItem {
  const nameEn = item.nameEn ?? item.translations?.find(t => t.language === 'en')?.name ?? '';
  const nameKa = item.nameKa ?? item.translations?.find(t => t.language === 'ka')?.name ?? '';
  return {
    id: item.id,
    price: item.price,
    imageUrl: item.imageUrl ?? '',
    nameEn,
    nameKa,
    subcategorySlug: item.subcategorySlug,
    subcategoryNameEn: item.subcategoryNameEn,
    subcategoryNameKa: item.subcategoryNameKa,
    hasVariants: item.hasVariants,
    variants: item.variants,
  };
}

function mapLegacySection(section: MenuSection): MenuSection {
  return {
    ...section,
    slug: section.slug ?? '',
    nameEn: section.nameEn ?? '',
    nameKa: section.nameKa ?? '',
    items: (section.items ?? []).map(i => mapLegacyItem(i as LegacyItem)),
  };
}

export function hasFullCategoryDetail(data: LegacyCategory): boolean {
  return Array.isArray(data.sections) && data.sections.length > 0;
}

export function normalizeCategory(data: LegacyCategory): MenuCategory {
  const nameEn = data.nameEn ?? data.translations?.find(t => t.language === 'en')?.name ?? '';
  const nameKa = data.nameKa ?? data.translations?.find(t => t.language === 'ka')?.name ?? '';

  if (hasFullCategoryDetail(data)) {
    const sections = data.sections!.map(mapLegacySection);
    const directItems = (data.items ?? []).map(mapLegacyItem);
    const sectionItemCount = sections.reduce((sum, s) => sum + s.items.length, 0);
    return {
      id: data.id != null ? String(data.id) : undefined,
      slug: data.slug,
      nameEn,
      nameKa,
      hasSubcategories: data.hasSubcategories ?? (data.displayMode === 'grouped'),
      displayMode: data.displayMode ?? (data.hasSubcategories ? 'grouped' : 'flat'),
      items: directItems,
      sections,
      itemCount: data.itemCount ?? (sectionItemCount || directItems.length),
    };
  }

  const items = (data.items ?? []).map(mapLegacyItem);
  return {
    id: data.id != null ? String(data.id) : undefined,
    slug: data.slug,
    nameEn,
    nameKa,
    hasSubcategories: false,
    displayMode: 'flat',
    items,
    itemCount: items.length,
    sections: [{
      type: 'subcategory',
      slug: data.slug,
      nameEn,
      nameKa,
      items,
    }],
  };
}

export function getCategoryName(category: MenuCategory, lang: 'en' | 'ka'): string {
  return lang === 'ka' ? category.nameKa : category.nameEn;
}

export function getItemName(item: MenuItem, lang: 'en' | 'ka'): string {
  return lang === 'ka' ? item.nameKa : item.nameEn;
}

export function getSectionName(section: MenuSection, lang: 'en' | 'ka'): string {
  return lang === 'ka' ? section.nameKa : section.nameEn;
}

export function getFirstItemImage(category: MenuCategory): string {
  for (const section of category.sections) {
    const url = section.items[0]?.imageUrl;
    if (url) return url;
  }
  return category.items[0]?.imageUrl ?? '';
}
