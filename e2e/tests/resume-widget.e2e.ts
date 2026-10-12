import { expect } from 'e2e';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { test, tapVisibleCenter } from './native-actions.js';
import { appGroupPath, bundle, openURL, terminate, writeAppBool } from '../support/simulator.js';

const args = ['-e2e-fixture', '-onboardingComplete', 'YES', '-startOnFreeBooks', 'NO', '-shelvesSource', 'librivox'];
const snapshot = () => JSON.parse(readFileSync(join(appGroupPath(), 'continue-listening.json'), 'utf8')) as {
  title: string; progress: number; bookID: string;
} | null;
/** The app writes the fallback snapshot shortly after a deletion settles, so poll for it. */
async function eventualSnapshotTitle(expected: string | null): Promise<string | null | undefined> {
  let title: string | null | undefined;
  for (let attempt = 0; attempt < 20; attempt += 1) {
    const current = snapshot();
    title = current === null ? null : current.title;
    if (title === expected) break;
    await delay(250);
  }
  return title;
}

test('Continue Listening snapshot saves progress and cover, resumes cold, and falls back after deletion', async ({ device, screen, app }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: [...args, '-e2e-reset-fixture'] });
  await screen.getByTestId('libraryTab').tap();
  await screen.getByTestId('book.card.E2E-Another-Book').tap();
  await screen.getByTestId('book.play').tap();
  await expect(screen.getByTestId('player.playPause')).toHaveAccessibleName('Pause playback');
  await screen.getByTestId('player.playPause').tap();
  await screen.getByRole('button', 'Close player').tap();
  await device.openApp(bundle, { relaunch: true, launchArguments: args });
  await screen.getByTestId('book.card.E2E-Listening-Book').tap();
  await screen.getByTestId('book.play').tap();
  await expect(screen.getByTestId('player.playPause')).toHaveAccessibleName('Pause playback');
  await delay(3500);
  await screen.getByTestId('player.playPause').tap();
  await eventualSnapshotTitle('E2E The Listening Book');
  const saved = snapshot();
  expect(saved?.title).toBe('E2E The Listening Book');
  expect(saved?.progress ?? 0).toBeGreaterThan(0);
  const value = await screen.getByTestId('player.scrubber').inputValue();
  const match = value?.match(/(\d+):(\d+) of (\d+):(\d+)/);
  if (!match || !saved) throw new Error('Missing player progress or snapshot');
  const seconds = Number(match[1]) * 60 + Number(match[2]);
  const total = Number(match[3]) * 60 + Number(match[4]);
  expect(total).toBe(300);
  // The fixture has two five-minute tracks; the scrubber describes the first track.
  expect(Math.abs(saved.progress - seconds / 600)).toBeLessThan(0.003);
  expect(existsSync(join(appGroupPath(), `${saved.bookID}.jpg`))).toBe(true);
  terminate(bundle);
  // A URL launch carries no launch arguments; keep the fixture store for this cold start.
  writeAppBool('e2e.stickyFixture', true);
  try {
    openURL('unpaged://resume');
    // iOS may ask before a link from outside opens the app.
    const open = screen.getByRole('button', 'Open');
    await expect.poll(() => open.isVisible(), { timeout: 3_000 }).toBe(true).catch(() => undefined);
    if (await open.isVisible()) await open.tap();
    await expect(screen.getByTestId('miniPlayer.title')).toHaveText('E2E The Listening Book');
  } finally {
    writeAppBool('e2e.stickyFixture', false);
  }
  await expect(screen.getByTestId('miniPlayer.playPause')).toHaveAccessibleName('Pause playback');
  await tapVisibleCenter(screen.getByTestId('miniPlayer.title'));
  await expect(screen.getByTestId('player.playPause')).toHaveAccessibleName('Pause playback');
  await screen.getByTestId('player.playPause').tap();
  await screen.getByRole('button', 'Close player').tap();
  await screen.getByTestId('book.card.E2E-Listening-Book').longPress();
  await screen.getByRole('button', 'Delete').tap();
  await screen.getByRole('button', 'Remove from App').tap();
  await expect(screen.getByTestId('book.card.E2E-Listening-Book')).toBeHidden();
  expect(await eventualSnapshotTitle('E2E Another Book')).toBe('E2E Another Book');
  await screen.getByTestId('libraryTab').tap();
  await screen.getByTestId('book.card.E2E-Another-Book').longPress();
  await screen.getByRole('button', 'Delete').tap();
  await screen.getByRole('button', 'Remove from App').tap();
  await expect(screen.getByTestId('book.card.E2E-Another-Book')).toBeHidden();
  expect(await eventualSnapshotTitle(null)).toBe(null);
  await app.screenshot('continue-listening-empty-library');
});
