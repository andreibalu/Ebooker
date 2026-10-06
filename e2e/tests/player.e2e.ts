import { expect, type Screen } from 'e2e';
import { copyFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test, tapVisibleCenter } from './native-actions.js';
import { appDataPath, bundle } from '../support/simulator.js';

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

async function choose(screen: Screen, picker: string, option: string) {
  await screen.scrollUntilVisible(screen.getByTestId(`settings.picker.${picker}`));
  await tapVisibleCenter(screen.getByTestId(`settings.picker.${picker}`));
  await screen.scrollUntilVisible(screen.getByRole('button', option));
  await tapVisibleCenter(screen.getByRole('button', option));
  await expect(screen.getByTestId(`settings.picker.${picker}`)).toContainText(option);
}

test('skip buttons and the resume offset follow Settings, and the library menu resumes the book', {
  timeout: 300_000,
}, async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: [...fixture, '-e2e-reset-fixture'] });
  await screen.getByTestId('settingsButton').tap();
  await choose(screen, 'Skip Forward', '45 seconds');
  await choose(screen, 'Skip Backward', '15 seconds');
  await choose(screen, 'On Resume', 'Resume 15 seconds earlier');
  await tapVisibleCenter(screen.getByRole('button', 'Done'));

  await openListeningBookPaused(screen);
  const scrubber = screen.getByTestId('player.scrubber');
  await screen.getByLabel('Skip forward').first().tap();
  await screen.getByLabel('Skip forward').first().tap();
  await expect(scrubber).toHaveValue(/^01:3\d of 05:00$/);
  await screen.getByLabel('Skip backward').first().tap();
  await expect(scrubber).toHaveValue(/^01:[12]\d of 05:00$/);
  // Playing and pausing again saves the position.
  await screen.getByTestId('player.playPause').tap();
  await screen.getByTestId('player.playPause').tap();
  await expect(scrubber).toHaveValue(/^01:[12]\d of 05:00$/);

  await device.openApp(bundle, { relaunch: true, launchArguments: fixture });
  await screen.getByTestId('libraryTab').tap();
  await screen.getByTestId('book.card.E2E-Listening-Book').longPress();
  await screen.getByRole('button', 'Resume').tap();
  await expect(screen.getByTestId('player.playPause')).toHaveAccessibleName('Pause playback');
  await screen.getByTestId('player.playPause').tap();
  // The first resume after launch starts 15 seconds before the saved position.
  await expect(scrubber).toHaveValue(/^01:0\d of 05:00$/);
});

test('the chapter list marks the current chapter and jumps to another', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: [...fixture, '-e2e-reset-fixture'] });
  await openListeningBookPaused(screen);
  await screen.getByTestId('player.chapters').tap();
  await expect(screen.getByTestId('chapters.row.0')).toBeSelected();
  await expect(screen.getByTestId('chapters.row.1')).toHaveAccessibleName('Chapter 2, E2E Chapter 2');
  await screen.getByTestId('chapters.row.1').tap();
  await expect(screen.getByTestId('player.title')).toHaveText('E2E Chapter 2');
  await screen.getByTestId('player.chapters').tap();
  await expect(screen.getByTestId('chapters.row.1')).toBeSelected();
  await screen.getByRole('button', 'Done').tap();
});

test('an imported M4B shows its embedded chapters and plays from the chosen one', {
  timeout: 300_000,
}, async ({ device, screen }) => {
  // A reset launch empties the fixture folder, so the file goes in after it.
  await device.openApp(bundle, { relaunch: true, launchArguments: [...fixture, '-e2e-reset-fixture'] });
  const m4b = fileURLToPath(new URL('../../PagelessTests/Fixtures/chaptered.m4b', import.meta.url));
  copyFileSync(m4b, join(appDataPath(), 'Library', 'Application Support', 'E2EFixtures', 'chaptered.m4b'));
  await device.openApp(bundle, { relaunch: true, launchArguments: [...fixture, '-e2e-import', '-e2e-import-file', 'chaptered.m4b'] });
  await screen.getByTestId('importButton').tap();
  await screen.getByPlaceholder('Title').fill('E2E Chaptered Book');
  await screen.getByRole('button', 'Save').tap();
  await screen.getByTestId('libraryTab').tap();
  await tapVisibleCenter(screen.getByText('E2E Chaptered Book').first());
  await screen.getByTestId('book.play').tap();
  await expect(screen.getByTestId('player.playPause')).toHaveAccessibleName('Pause playback');
  await screen.getByTestId('player.playPause').tap();

  // One file, three chapter markers: the list comes from the M4B itself.
  await screen.getByTestId('player.chapters').tap();
  await expect(screen.getByTestId('chapters.row.0')).toHaveAccessibleName('Chapter 1, Opening');
  await expect(screen.getByTestId('chapters.row.1')).toHaveAccessibleName('Chapter 2, The Middle');
  await expect(screen.getByTestId('chapters.row.2')).toHaveAccessibleName('Chapter 3, Ending');
  await screen.getByTestId('chapters.row.1').tap();
  await expect(screen.getByTestId('player.currentChapter')).toHaveAccessibleName('Chapter: The Middle');
  await expect(screen.getByTestId('player.title')).toHaveText('E2E Chaptered Book');
});
