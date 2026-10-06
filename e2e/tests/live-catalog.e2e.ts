import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { tapVisibleCenter } from './native-actions.js';

// Opt in explicitly: this test reads public LibriVox/Archive services and writes
// only the dedicated simulator's isolated library. It performs no purchase.
test('live LibriVox search resolves real tracks and adds a streaming book', {
  timeout: 300_000,
  skip: process.env.E2E_LIVE_CATALOG === '1' ? false : 'Set E2E_LIVE_CATALOG=1 for public-network catalog coverage',
}, async ({ device, screen }) => {
  const arguments_ = ['-e2e-fixture', '-e2e-online', '-onboardingComplete', 'YES', '-startOnFreeBooks', 'NO', '-shelvesSource', 'librivox'];
  await device.openApp('andreibaludev.Pageless', {
    relaunch: true,
    launchArguments: [...arguments_, '-e2e-reset-fixture'],
  });
  await device.setOrientation('portrait');
  await screen.getByTestId('shelvesTab').tap();
  await screen.getByRole('textbox').fill('Pride and Prejudice');
  await screen.getByRole('textbox').press('Enter');
  await expect(screen.getByText(/^Found · [1-9]\d* Recordings?$/).first()).toBeVisible({ timeout: 60_000 });
  await expect(screen.getByText('Searching LibriVox…').first()).toBeHidden({ timeout: 60_000 });
  await expect(screen.getByText('Pride and Prejudice', { exact: true }).first()).toBeVisible({ timeout: 60_000 });
  // The search textbox has the same text as the title. Select the actual result row.
  await tapVisibleCenter(screen.getByRole('button', /^\d{2}, Pride and Prejudice, /).first());
  await screen.scrollUntilVisible(screen.getByRole('button', 'Add to Library'));
  await expect(screen.getByRole('button', 'Add to Library')).toBeVisible();
  await screen.getByRole('button', 'Play 20s Sample').tap();
  await expect(screen.getByLabel('Stop Sample').first()).toBeVisible();
  await expect(screen.getByRole('progressbar')).toBeHidden({ timeout: 30_000 });
  await expect(screen.getByLabel('Stop Sample').first()).toBeVisible();
  await tapVisibleCenter(screen.getByLabel('Stop Sample').first());
  await expect(screen.getByRole('button', 'Play 20s Sample')).toBeVisible();
  await screen.getByRole('button', 'Add to Library').tap();
  // The button also disappears during loading; wait for the persisted success
  // surface before restarting the process.
  await expect(screen.getByText('Added to Your Library').first()).toBeVisible({ timeout: 30_000 });
  await device.openApp('andreibaludev.Pageless', { relaunch: true, launchArguments: arguments_ });
  await screen.getByTestId('libraryTab').tap();
  await expect(screen.getByText('Pride and Prejudice', { exact: true }).first()).toBeVisible();
  await screen.getByText('Pride and Prejudice', { exact: true }).first().tap();
  await expect(screen.getByTestId('book.play')).toBeVisible();
  await screen.getByTestId('book.play').tap();
  await expect(screen.getByTestId('player.playPause')).toHaveAccessibleName('Pause playback', { timeout: 30_000 });
  await expect(screen.getByText('Connecting to stream…')).toBeHidden({ timeout: 30_000 });
  await screen.getByTestId('player.playPause').tap();
  await screen.getByRole('button', 'Close player').tap();
  await device.back();
  await tapVisibleCenter(screen.getByTestId('shelvesTab'));
  await expect(screen.getByText('Pride and Prejudice', { exact: true }).first()).toBeVisible();
  await tapVisibleCenter(screen.getByRole('button', /^\d{2}, Pride and Prejudice, /).first());
  await screen.scrollUntilVisible(screen.getByRole('button', 'Download Free Book'));
  await tapVisibleCenter(screen.getByRole('button', 'Download Free Book'));
  await expect(screen.getByRole('button', 'Cancel')).toBeVisible();
  // Leave detail while the session-wide download continues; observe and cancel
  // the same task in Library immediately, bounding transferred audio.
  await device.back();
  await tapVisibleCenter(screen.getByTestId('libraryTab'));
  await expect(screen.getByRole('button', 'Cancel download')).toBeVisible();
  await tapVisibleCenter(screen.getByRole('button', 'Cancel download'));
  await expect(screen.getByRole('button', 'Cancel download')).toBeHidden({ timeout: 30_000 });
  await tapVisibleCenter(screen.getByTestId('shelvesTab'));
  await expect(screen.getByText('Pride and Prejudice', { exact: true }).first()).toBeVisible();
  await tapVisibleCenter(screen.getByRole('button', /^\d{2}, Pride and Prejudice, /).first());
  await screen.scrollUntilVisible(screen.getByRole('button', 'Download Free Book'));
  await tapVisibleCenter(screen.getByRole('button', 'Download Free Book'));
  await expect(screen.getByRole('button', 'Cancel')).toBeVisible();
  await tapVisibleCenter(screen.getByRole('button', 'Cancel'));
  await expect(screen.getByRole('button', 'Download Free Book')).toBeVisible({ timeout: 30_000 });
});
