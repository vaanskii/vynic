import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import Checkout from '../../../vankisi-custom-web/src/pages/Checkout';

const createBogPayment = vi.hoisted(() => vi.fn());
vi.mock('../../../vankisi-custom-web/src/services/api', () => ({
  tableService: { createBogPayment }, userService: { getProfile: vi.fn() },
}));
vi.mock('../../../vankisi-custom-web/src/contexts/LanguageContext', () => ({
  useLanguage: () => ({ language: 'en' }),
}));
vi.mock('../../../vankisi-custom-web/src/contexts/AuthContext', () => ({
  useAuth: () => ({ user: null }),
}));
vi.mock('../../../vankisi-custom-web/src/contexts/CartContext', () => ({
  useCart: () => ({ reloadCart: vi.fn() }),
}));

beforeEach(() => {
  createBogPayment.mockReset().mockRejectedValue(new Error('Synthetic stop before bank redirect'));
  vi.spyOn(window, 'alert').mockImplementation(() => {});
  vi.spyOn(console, 'error').mockImplementation(() => {});
});

describe('Vankisi checkout booking intent', () => {
  it.each(['3', undefined])('sends the selected guest count and preserves old missing-count fallback: %s', async (resGuests) => {
    localStorage.setItem('vankisi_reservation', JSON.stringify({
      selectedTables: ['table1'], resDate: '2035-01-01', resTime: '18:00',
      customerName: 'Synthetic guest', customerPhone: '555000000',
      ...(resGuests ? { resGuests } : {}),
    }));
    render(<MemoryRouter initialEntries={['/en/checkout']}><Checkout /></MemoryRouter>);
    await userEvent.click(await screen.findByRole('button', { name: 'Proceed to Payment' }));
    expect(createBogPayment).toHaveBeenCalledTimes(1);
    const intent = createBogPayment.mock.calls[0][0];
    expect(intent).toMatchObject({ selectedTables: ['table1'], selectedDate: '2035-01-01', selectedTime: '18:00' });
    if (resGuests) expect(intent.numberOfGuests).toBe(3);
    else expect(intent).not.toHaveProperty('numberOfGuests');
  });
});
