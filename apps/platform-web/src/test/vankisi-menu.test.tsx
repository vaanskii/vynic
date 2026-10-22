import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { describe, expect, it, vi } from 'vitest';
import Menu from '../../../vankisi-custom-web/src/pages/Menu';

vi.mock('../../../vankisi-custom-web/src/contexts/LanguageContext', () => ({
  useLanguage: () => ({ language: 'en' }),
}));
vi.mock('../../../vankisi-custom-web/src/services/api', () => ({
  menuService: {
    getAllCategories: () => Promise.resolve([{
      slug: 'food', nameEn: 'Food', nameKa: 'Food ka', hasSubcategories: true,
      displayMode: 'grouped', itemCount: 2,
      sections: [
        { type: 'items', slug: null, nameEn: null, nameKa: null, items: [{ id: 'direct', nameEn: 'Direct meal', price: 8 }] },
        { type: 'subcategory', slug: 'specials', nameEn: 'Specials', nameKa: 'Specials ka', items: [{ id: 'nested', nameEn: 'Nested meal', price: 12 }] },
      ],
    }]),
    getCategoryBySlug: vi.fn(),
  },
}));

describe('Vankisi mixed menu sections', () => {
  it('renders direct and nested items from one category without losing either group', async () => {
    render(<MemoryRouter initialEntries={['/en/menu']}><Menu /></MemoryRouter>);
    expect(await screen.findByText('Direct meal')).toBeVisible();
    expect(screen.getByText('Nested meal')).toBeVisible();
  });
});
