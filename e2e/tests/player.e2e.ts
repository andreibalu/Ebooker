import { expect, type Screen } from 'e2e';
import { test, tapVisibleCenter } from './native-actions.js';
import { bundle } from '../support/simulator.js';

const fixture = ['-e2e-fixture', '-onboardingComplete', 'YES', '-startOnFreeBooks', 'NO', '-shelvesSource', 'librivox'];

async function openListeningBookPaused(screen: Screen) {
  await screen.getByTestId('book.card.E2E-Listening-Book').tap();
  await screen.getByTestId('book.play').tap();
  await expect(screen.getByTestId('player.playPause')).toHaveAccessibleName('Pause playback');
  await screen.getByTestId('player.playPause').tap();
  await expect(screen.getByTestId('player.playPause')).toHaveAccessibleName('Play playback');
}

test('dragging the scrubber seeks, and VoiceOver reads the new position', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: [...fixture, '-e2e-reset-fixture'] });
  await openListeningBookPaused(screen);
  const scrubber = screen.getByTestId('player.scrubber');
  await expect(scrubber).toHaveValue(/^00:0\d of 05:00$/);
  const box = await scrubber.boundingBox();
  if (!box) throw new Error('Scrubber has no bounds');
  const y = box.y + box.height * 0.75;
  // A horizontal drag at the track's own height is full-speed scrubbing: a half-track drag
  // from 10% lands near the middle of 5:00 (the thumb follows the finger's travel).
  await screen.swipe({ from: { x: box.x + box.width * 0.1, y }, to: { x: box.x + box.width * 0.6, y } });
  await expect(scrubber).toHaveValue(/^(02:[0-5]\d|03:[0-1]\d) of 05:00$/);
  // The seek commits to the player: resuming continues from the new position.
  await screen.getByTestId('player.playPause').tap();
  await screen.getByTestId('player.playPause').tap();
  await expect(scrubber).toHaveValue(/^(02:[0-5]\d|03:[0-2]\d) of 05:00$/);
});

test('the sleep timer pauses playback when it expires', async ({ device, screen }) => {
  // DEBUG-only: every timer choice lasts 4 seconds in this launch.
  await device.openApp(bundle, { relaunch: true, launchArguments: [...fixture, '-e2e-reset-fixture', '-e2e-sleep-timer-seconds', '4'] });
  await screen.getByTestId('book.card.E2E-Listening-Book').tap();
  await screen.getByTestId('book.play').tap();
  await expect(screen.getByTestId('player.playPause')).toHaveAccessibleName('Pause playback');
  await screen.getByTestId('player.sleep').tap();
  await screen.getByRole('button', '15 minutes').tap();
  await expect(screen.getByTestId('player.sleep')).not.toContainText('Sleep Timer');
  await expect(screen.getByTestId('player.playPause')).toHaveAccessibleName('Play playback', { timeout: 15_000 });
  await expect(screen.getByTestId('player.sleep')).toContainText('Sleep Timer');
});

test('a chosen playback speed is remembered for the book after relaunch', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: [...fixture, '-e2e-reset-fixture'] });
  await openListeningBookPaused(screen);
  await screen.getByTestId('player.speed').tap();
  await screen.getByRole('button', /^1[.,]5×$/).tap();
  await expect(screen.getByTestId('player.speed')).toContainText(/1[.,]5/);
  await device.openApp(bundle, { relaunch: true, launchArguments: fixture });
  await openListeningBookPaused(screen);
  await expect(screen.getByTestId('player.speed')).toContainText(/1[.,]5/);
});

test('the mini player shows the book, toggles playback and reopens the player', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: [...fixture, '-e2e-reset-fixture'] });
  await screen.getByTestId('book.card.E2E-Listening-Book').tap();
  await screen.getByTestId('book.play').tap();
  await expect(screen.getByTestId('player.playPause')).toHaveAccessibleName('Pause playback');
  await screen.getByRole('button', 'Close player').tap();
  await expect(screen.getByTestId('miniPlayer.title')).toHaveText('E2E The Listening Book');
  await expect(screen.getByText('E2E Chapter 1').first()).toBeVisible();
  await expect(screen.getByTestId('miniPlayer.playPause')).toHaveAccessibleName('Pause playback');
  await screen.getByTestId('miniPlayer.playPause').tap();
  await expect(screen.getByTestId('miniPlayer.playPause')).toHaveAccessibleName('Play playback');
  await tapVisibleCenter(screen.getByTestId('miniPlayer.title'));
  await expect(screen.getByTestId('player.playPause')).toHaveAccessibleName('Play playback');
});

test('renaming a single-track book renames what the player and mini player show', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: [...fixture, '-e2e-reset-fixture'] });
  await screen.getByTestId('libraryTab').tap();
  await screen.getByTestId('book.card.E2E-Another-Book').longPress();
  await screen.getByRole('button', 'Rename').tap();
  await screen.getByPlaceholder('Book title').fill('E2E Renamed Single');
  await screen.getByRole('button', 'Save').tap();
  await screen.getByTestId('book.card.E2E-Another-Book').tap();
  await screen.getByTestId('book.play').tap();
  // Single-track books show the renamable book title, not the file's chapter metadata.
  await expect(screen.getByTestId('player.title')).toHaveText('E2E Renamed Single');
  await expect(screen.getByText('E2E Another Chapter')).toBeHidden();
  await screen.getByRole('button', 'Close player').tap();
  await expect(screen.getByTestId('miniPlayer.title')).toHaveText('E2E Renamed Single');
  await expect(screen.getByText('E2E Another Chapter')).toBeHidden();
});
