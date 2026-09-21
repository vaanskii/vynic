import { screen } from '@testing-library/react';
import { expect, it } from 'vitest';
import { ids, installApi, renderPlatform } from './platform-test-utils';

it('shows the immutable Manager restaurant code in the Venue record', async () => {
  installApi();
  renderPlatform(`/admin/venues/${ids.venue}`);
  expect(await screen.findByText('მენეჯერის აპლიკაცია')).toBeVisible();
  expect(await screen.findByText('vankisi', { exact: true })).toBeVisible();
});
