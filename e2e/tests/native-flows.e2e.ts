import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { expandEqualizerSheet, tapVisibleCenter } from './native-actions.js';

const bundle = 'andreibaludev.Pageless';
const fixture = ['-e2e-fixture', '-onboardingComplete', 'YES', '-startOnFreeBooks', 'NO', '-shelvesSource', 'librivox'];

// Every test starts with an isolated, deterministic native SwiftData fixture.
// Restart without reset is intentional: the persistence assertions read the saved database.
test('library favorite mutation survives a native process relaunch', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: [...fixture, '-e2e-reset-fixture'] });
  await expect(screen.getByTestId('book.card.E2E-Listening-Book')).toBeVisible();
  await screen.getByTestId('book.favorite.E2E-Listening-Book').tap();
  await expect(screen.getByTestId('book.card.E2E-Listening-Book')).toBeHidden();
  await device.openApp(bundle, { relaunch: true, launchArguments: fixture });
  await expect(screen.getByTestId('book.card.E2E-Listening-Book')).toBeHidden();
  await screen.getByTestId('libraryTab').tap();
  await expect(screen.getByTestId('book.card.E2E-Listening-Book')).toBeVisible();
  await expect(screen.getByTestId('book.favorite.E2E-Listening-Book')).toHaveAccessibleName('Add favorite');
  await screen.getByTestId('book.favorite.E2E-Listening-Book').tap();
  await expect(screen.getByTestId('book.favorite.E2E-Listening-Book')).toHaveAccessibleName('Remove favorite');
  await device.openApp(bundle, { relaunch: true, launchArguments: fixture });
  await expect(screen.getByTestId('book.card.E2E-Listening-Book')).toBeVisible();
  await expect(screen.getByTestId('book.favorite.E2E-Listening-Book')).toHaveAccessibleName('Remove favorite');
});

test('library rename survives relaunch and keeps chapter titles', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: [...fixture, '-e2e-reset-fixture'] });
  await screen.getByTestId('book.card.E2E-Listening-Book').longPress();
  await screen.getByRole('button', 'Rename').tap();
  await screen.getByPlaceholder('Book title').fill('E2E Renamed Book');
  await screen.getByRole('button', 'Save').tap();
  await expect(screen.getByText('E2E Renamed Book').first()).toBeVisible();
  await device.openApp(bundle, { relaunch: true, launchArguments: fixture });
  await expect(screen.getByText('E2E Renamed Book').first()).toBeVisible();
  await screen.getByTestId('book.card.E2E-Listening-Book').tap();
  await screen.getByText(/^\d+ tracks?$/).first().tap();
  await expect(screen.getByText('E2E Chapter 1').first()).toBeVisible();
});

test('local playback advances chapters and creates a persisted manual moment', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: [...fixture, '-e2e-reset-fixture'] });
  await screen.getByTestId('book.card.E2E-Listening-Book').tap();
  await screen.getByTestId('book.play').tap();
  await expect(screen.getByTestId('player.playPause')).toHaveAccessibleName('Pause playback');
  await screen.getByTestId('player.playPause').tap();
  await expect(screen.getByTestId('player.playPause')).toHaveAccessibleName('Play playback');
  await screen.getByTestId('player.next').tap();
  await expect(screen.getByText('E2E Chapter 2').first()).toBeVisible();
  await screen.getByTestId('player.previous').tap();
  await expect(screen.getByText('E2E Chapter 1').first()).toBeVisible();
  await screen.getByTestId('player.saveMoment').tap();
  await screen.getByTestId('moment.name').fill('E2E Persisted Moment');
  await tapVisibleCenter(screen.getByTestId('moment.done').last());
  await expect(screen.getByTestId('moment.done')).toBeHidden();
  await device.openApp(bundle, { relaunch: true, launchArguments: fixture });
  await screen.getByTestId('book.card.E2E-Listening-Book').tap();
  await screen.getByText(/^\d+ moments?$/).first().tap();
  await screen.scrollUntilVisible(screen.getByText('E2E Persisted Moment').first());
  await expect(screen.getByText('E2E Persisted Moment').first()).toBeVisible();
});

test('equalizer is reachable from actual local playback', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: [...fixture, '-e2e-reset-fixture'] });
  await screen.getByTestId('book.card.E2E-Listening-Book').tap();
  await screen.getByTestId('book.play').tap();
  await expect(screen.getByTestId('player.playPause')).toHaveAccessibleName('Pause playback');
  await screen.getByTestId('player.playPause').tap();
  await expect(screen.getByTestId('player.playPause')).toHaveAccessibleName('Play playback');
  await screen.getByTestId('player.equalizer').tap();
  await expandEqualizerSheet({ allowVisibleControls: true });
  await expect(screen.getByText('Equalizer').first()).toBeVisible();
  await expect(screen.getByTestId('equalizer.enabled')).toBeVisible();
  await expect(screen.getByRole('button', 'Voice Boost')).toBeVisible();
});

test('reading activity opens aggregate stats from saved reading sessions', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: [...fixture, '-e2e-reset-fixture'] });
  await expect(screen.getByTestId('readingActivity')).toBeVisible();
  await screen.getByTestId('readingActivity').tap();
  await expect(screen.getByText('Reading').first()).toBeVisible();
  await expect(screen.getByText(/listening across 1 session and 1 day/).first()).toContainText('42m');
  await expect(screen.getByText('with Author.').first()).toBeVisible();
});

test('Plus purchase and restore surfaces remain reachable without iCloud sign-in', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: [...fixture, '-e2e-reset-fixture'] });
  // The header Plus button is unconditional: no iCloud sign-in or sync needed (Apple 3.1.1).
  await screen.getByTestId('plusButton').tap();
  await expect(screen.getByText('Unpaged Plus').first()).toBeVisible();
  await screen.scrollUntilVisible(screen.getByText('Restore purchases').first());
  await expect(screen.getByText('Restore purchases').first()).toBeVisible();
  // No purchase/restore call: this is UI reachability, not transaction qualification.
});

test('offline Shelves keeps cached books and unconfigured ABS setup reachable', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: [...fixture, '-e2e-reset-fixture'] });
  await screen.getByTestId('shelvesTab').tap();
  await expect(screen.getByText('Offline — showing saved books.').first()).toBeVisible();
  // Today's Pick is excluded from the chart. Either cached recording qualifies,
  // and a chart-row locator avoids an offscreen hero above the current scroll position.
  const cachedRecording = screen.getByRole('button', /^\d{2}, Pride and Prejudice(?: \(version 2\))?, /).first();
  await screen.scrollUntilVisible(cachedRecording);
  await expect(cachedRecording).toBeVisible();
  await screen.getByTestId('shelvesTab').tap();
  await screen.getByRole('button', /Audiobookshelf/).tap();
  await expect(screen.getByText('Bring your own shelf.').first()).toBeVisible();
  await expect(screen.getByRole('button', 'Connect')).toBeDisabled();
});

test('onboarding own-books choice and completion persist across relaunch', async ({ device, screen }) => {
  const onboarding = ['-e2e-fixture', '-onboardingComplete', 'NO', '-startOnFreeBooks', 'NO'];
  await device.openApp(bundle, { relaunch: true, launchArguments: [...onboarding, '-e2e-reset-fixture'] });
  await screen.getByTestId('onboarding.choice.own').tap();
  await expect(screen.getByText('Two quick permissions.').first()).toBeVisible();
  await screen.getByTestId('onboarding.page.6').tap();
  await expect(screen.getByText("You're all set.").first()).toBeVisible();
  await screen.getByRole('button', 'Open Library').tap();
  await expect(screen.getByTestId('libraryTab')).toBeVisible();
  // Remove the onboardingComplete launch override to inspect real persisted defaults.
  await device.openApp(bundle, { relaunch: true, launchArguments: ['-e2e-fixture'] });
  await expect(screen.getByTestId('settingsButton')).toBeVisible();
  await expect(screen.getByTestId('onboarding.choice.own')).toBeHidden();
});

test('speed and sleep timer change through native player menus', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: [...fixture, '-e2e-reset-fixture'] });
  await screen.getByTestId('book.card.E2E-Listening-Book').tap();
  await screen.getByTestId('book.play').tap();
  await screen.getByTestId('player.speed').tap();
  await screen.getByRole('button', /^1[.,]5×$/).tap();
  await expect(screen.getByTestId('player.speed')).toContainText(/1[.,]5/);
  await screen.getByTestId('player.sleep').tap();
  await screen.getByRole('button', '15 minutes').tap();
  await expect(screen.getByTestId('player.sleep')).not.toContainText('Sleep Timer');
});

test('editing a saved moment survives process relaunch', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: [...fixture, '-e2e-reset-fixture'] });
  await screen.getByTestId('book.card.E2E-Listening-Book').tap();
  await screen.getByText(/^\d+ moments?$/).first().tap();
  await screen.scrollUntilVisible(screen.getByText('E2E First Moment').first());
  await tapVisibleCenter(screen.getByText('E2E First Moment').first());
  await expandEqualizerSheet();
  await screen.getByTestId('moment.name').fill('E2E Edited Moment');
  await screen.scrollUntilVisible(screen.getByTestId('moment.note'));
  await screen.getByTestId('moment.note').fill('E2E edited note persists.');
  await tapVisibleCenter(screen.getByTestId('moment.done').last());
  await expect(screen.getByTestId('moment.done')).toBeHidden();
  await device.openApp(bundle, { relaunch: true, launchArguments: fixture });
  await screen.getByTestId('book.card.E2E-Listening-Book').tap();
  await screen.getByText(/^\d+ moments?$/).first().tap();
  await screen.scrollUntilVisible(screen.getByText('E2E Edited Moment').first());
  await expect(screen.getByText('E2E edited note persists.').first()).toBeVisible();
  await expect(screen.getByText('E2E First Moment').first()).toBeHidden();
});

test('deleting a moment survives process relaunch', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: [...fixture, '-e2e-reset-fixture'] });
  await screen.getByTestId('book.card.E2E-Listening-Book').tap();
  await screen.getByText(/^\d+ moments?$/).first().tap();
  await screen.scrollUntilVisible(screen.getByText('E2E First Moment').first());
  await screen.getByText('E2E First Moment').first().longPress();
  await screen.getByRole('button', 'Delete').tap();
  await expect(screen.getByText('E2E First Moment').first()).toBeHidden();
  await device.openApp(bundle, { relaunch: true, launchArguments: fixture });
  await screen.getByTestId('book.card.E2E-Listening-Book').tap();
  await screen.getByText(/^\d+ moments?$/).first().tap();
  await screen.scrollUntilVisible(screen.getByText('E2E Second Moment').first());
  await expect(screen.getByText('E2E Second Moment').first()).toBeVisible();
  await expect(screen.getByText('E2E First Moment').first()).toBeHidden();
});

test('moment filter sheet opens and can be dismissed without losing moments', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: [...fixture, '-e2e-reset-fixture'] });
  await screen.getByTestId('book.card.E2E-Listening-Book').tap();
  await screen.getByText(/^\d+ moments?$/).first().tap();
  await screen.scrollUntilVisible(screen.getByLabel('Filter moments').first());
  await screen.getByLabel('Filter moments').first().tap();
  await expect(screen.getByText('Filter Moments').first()).toBeVisible();
  await screen.getByRole('button', 'Done').tap();
  await expect(screen.getByText('E2E First Moment').first()).toBeVisible();
});

test('own-book delete cancellation preserves book then confirmed removal persists', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: [...fixture, '-e2e-reset-fixture'] });
  await screen.getByTestId('book.card.E2E-Listening-Book').longPress();
  await screen.getByRole('button', 'Delete').tap();
  await screen.getByRole('button', 'Cancel').tap();
  await expect(screen.getByTestId('book.card.E2E-Listening-Book')).toBeVisible();
  await screen.getByTestId('book.card.E2E-Listening-Book').longPress();
  await screen.getByRole('button', 'Delete').tap();
  await screen.getByRole('button', 'Also Delete Files').tap();
  await expect(screen.getByTestId('book.card.E2E-Listening-Book')).toBeHidden();
  await device.openApp(bundle, { relaunch: true, launchArguments: fixture });
  await screen.getByTestId('libraryTab').tap();
  await expect(screen.getByTestId('book.card.E2E-Listening-Book')).toBeHidden();
});

test('settings playback preference persists across relaunch', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: [...fixture, '-e2e-reset-fixture'] });
  await screen.getByTestId('settingsButton').tap();
  await screen.scrollUntilVisible(screen.getByTestId('settings.picker.Skip Backward'));
  const pickerBox = await screen.getByTestId('settings.picker.Skip Backward').boundingBox();
  if (!pickerBox || pickerBox.height < 30) throw new Error('Skip Backward picker remains clipped after scrolling');
  await tapVisibleCenter(screen.getByTestId('settings.picker.Skip Backward'));
  await screen.scrollUntilVisible(screen.getByRole('button', '15 seconds'));
  await tapVisibleCenter(screen.getByRole('button', '15 seconds'));
  await device.openApp(bundle, { relaunch: true, launchArguments: fixture });
  await screen.getByTestId('settingsButton').tap();
  await screen.scrollUntilVisible(screen.getByTestId('settings.picker.Skip Backward'));
  await expect(screen.getByTestId('settings.picker.Skip Backward')).toContainText('15 seconds');
});
