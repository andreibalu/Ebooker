import { expect, type Screen } from 'e2e';
import { setTimeout as delay } from 'node:timers/promises';
import { test, tapVisibleCenter } from './native-actions.js';
import { startFakeLibriVox } from '../support/fake-librivox.js';
import { bundle } from '../support/simulator.js';

// `-e2e-rating-stub` counts requests in `ratingPrompt.requests` instead of raising Apple's sheet.
// `-e2e-rating-install-days 3` ages the install past the two-day minimum; without it the launch is a first day.
// `-e2e-rating-finished-hours-ago 1` records a book finished an hour ago, so most cases skip playing one.
// `-e2e-rating-near-end` leaves four seconds of the fixture book, so one tap on Play finishes it.
// `-e2e-rating-poll-seconds 6` slows the watch's poll, for cases that assert "nothing yet" right after a sheet closes.
// `-e2e-rating-seed-listening` adds four listening days of an hour each.
const base = ['-e2e-fixture', '-e2e-reset-fixture', '-onboardingComplete', 'YES', '-startOnFreeBooks', 'NO',
  '-shelvesSource', 'librivox', '-resumeBacktrackSeconds', '0', '-e2e-rating-stub'];
const aged = [...base, '-e2e-rating-install-days', '3'];
const finished = [...aged, '-e2e-rating-finished-hours-ago', '1'];
// Slow polls (two calm ones needed, 12 s) give "nothing yet" a margin over a slow driver after a sheet closes.
const slow = [...finished, '-e2e-rating-poll-seconds', '6'];
// The watch polls every two seconds and needs two calm polls in a row.
const quietFor = 9_000;

async function requests(screen: Screen, count: string, timeout = 5_000) {
  await expect(screen.getByTestId('ratingPrompt.requests')).toHaveText(count, { timeout });
}

test('a book played to its end asks once the player closes', { timeout: 360_000 }, async ({ app, device, screen }) => {
  // Seen on loaded simulators: AVPlayer sometimes runs past the end of the fixture's silent WAV and never
  // posts its end notification, so the book never finishes. Another fresh launch plays it to the end.
  let ended = false;
  for (let attempt = 0; attempt < 8 && !ended; attempt++) {
    await device.openApp(bundle, { relaunch: true, launchArguments: [...aged, '-e2e-rating-near-end'] });
    await screen.getByTestId('book.card.E2E-Listening-Book').tap();
    await screen.getByTestId('book.play').tap();
    try {
      await expect(screen.getByTestId('player.playPause')).toHaveAccessibleName('Play playback', { timeout: 12_000 });
      ended = true;
    } catch { /* retry on a fresh launch */ }
  }
  expect(ended).toBe(true);
  // The finished book is a positive moment, but the player is still open.
  await delay(quietFor);
  await requests(screen, '0');
  await screen.getByRole('button', 'Close player').tap();
  await requests(screen, '1', 20_000);
  await app.screenshot('rating-prompt-asked-after-finished-book');
});

test('a finished book asks once and never again in the same version, even after relaunch', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: finished });
  await requests(screen, '1', 20_000);
  await device.openApp(bundle, { relaunch: true, launchArguments: finished.filter((a) => a !== '-e2e-reset-fixture') });
  await delay(quietFor);
  await requests(screen, '0');
});

test('a first-day launch never asks', async ({ app, device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: [...base, '-e2e-rating-finished-hours-ago', '1', '-e2e-rating-seed-listening'] });
  await delay(quietFor);
  await requests(screen, '0');
  await app.screenshot('rating-prompt-first-day-quiet');
});

test('a sheet holds the request until it closes', async ({ app, device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: slow });
  await screen.getByTestId('settingsButton').tap();
  await delay(quietFor + 6_000);
  await tapVisibleCenter(screen.getByRole('button', 'Done'));
  // Closing the sheet starts the calm count over, so nothing has fired yet.
  await requests(screen, '0', 2_000);
  await requests(screen, '1', 30_000);
  await app.screenshot('rating-prompt-asked-after-sheet-closed');
});

test('the Plus paywall holds the request until it closes', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: slow });
  await screen.getByTestId('plusButton').tap();
  await delay(quietFor + 6_000);
  await tapVisibleCenter(screen.getByRole('button', 'Done'));
  await requests(screen, '0', 2_000);
  await requests(screen, '1', 30_000);
});

test('three or more listening days ask without a finished book', async ({ app, device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: [...aged, '-e2e-rating-seed-listening'] });
  await requests(screen, '1', 20_000);
  await app.screenshot('rating-prompt-asked-after-listening-habit');
});

test('thin listening and no finished book ask nothing', async ({ device, screen }) => {
  // The fixture's own seeded day is 42 minutes on one day: not a habit.
  await device.openApp(bundle, { relaunch: true, launchArguments: aged });
  await delay(quietFor);
  await requests(screen, '0');
});

test('playing audio holds the request until playback pauses', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: finished });
  await screen.getByTestId('book.card.E2E-Listening-Book').tap();
  await screen.getByTestId('book.play').tap();
  await expect(screen.getByTestId('player.playPause')).toHaveAccessibleName('Pause playback', { timeout: 20_000 });
  // The open player covers the counter, so only the mini player's state is asserted.
  await screen.getByRole('button', 'Close player').tap();
  await delay(quietFor);
  await requests(screen, '0');
  await screen.getByTestId('miniPlayer.playPause').tap();
  await expect(screen.getByTestId('miniPlayer.playPause')).toHaveAccessibleName('Play playback');
  await requests(screen, '1', 20_000);
});

test('a stream still loading holds the request until playback is stopped', { timeout: 300_000 }, async ({ device, screen }) => {
  // First launch: stream Jane Eyre once, so it becomes the latest-played book.
  let feed = await startFakeLibriVox();
  try {
    await device.openApp(bundle, { relaunch: true, launchArguments: [...aged, '-e2e-online', '-e2e-librivox-feed', feed.feedURL] });
    await screen.getByTestId('shelvesTab').tap();
    await screen.getByRole('textbox').fill('Jane Eyre');
    await screen.getByRole('textbox').press('Enter');
    const row = screen.getByRole('button', /^\d+, Jane Eyre, /).first();
    await expect(row).toBeVisible({ timeout: 30_000 });
    await tapVisibleCenter(row);
    await screen.scrollUntilVisible(screen.getByRole('button', 'Add to Library'));
    await tapVisibleCenter(screen.getByRole('button', 'Add to Library'));
    await tapVisibleCenter(screen.getByRole('button', 'View in Library'));
    await screen.getByTestId('book.play').tap();
    await expect(screen.getByTestId('player.playPause')).toHaveAccessibleName('Pause playback', { timeout: 30_000 });
  } finally {
    await feed.close();
  }

  // Second launch: "play latest book" (Siri, widget) starts the stream with the player closed, and the
  // same audio URLs now take seven seconds to answer, so playback is loading but not yet playing.
  feed = await startFakeLibriVox({ audioDelayMs: 7_000 });
  try {
    const relaunch = [...finished.filter((a) => a !== '-e2e-reset-fixture'), '-e2e-online', '-e2e-librivox-feed', feed.feedURL,
      '-intent.playLatestBook', 'YES', '-e2e-rating-poll-seconds', '3'];
    await device.openApp(bundle, { relaunch: true, launchArguments: relaunch });
    // Two calm 3-second polls fall inside the load; loading must not count as calm.
    await expect(screen.getByTestId('miniPlayer.playPause')).toHaveAccessibleName('Pause playback', { timeout: 30_000 });
    expect(feed.audioRequests('133').length).toBeGreaterThan(0);
    await requests(screen, '0');
    await screen.getByTestId('miniPlayer.playPause').tap();
    await requests(screen, '1', 20_000);
  } finally {
    await feed.close();
  }
});

test('onboarding never asks', async ({ device, screen }) => {
  const args = finished.filter((a, i, all) => a !== '-onboardingComplete' && all[i - 1] !== '-onboardingComplete');
  await device.openApp(bundle, { relaunch: true, launchArguments: [...args, '-onboardingComplete', 'NO', '-e2e-rating-seed-listening'] });
  await delay(quietFor);
  await requests(screen, '0');
});
