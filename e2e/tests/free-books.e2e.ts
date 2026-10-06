import { expect } from 'e2e';
import { test, tapVisibleCenter } from './native-actions.js';
import { startFakeLibriVox, type FakeLibriVox } from '../support/fake-librivox.js';
import { bundle } from '../support/simulator.js';

const base = ['-e2e-fixture', '-onboardingComplete', 'YES', '-startOnFreeBooks', 'NO', '-shelvesSource', 'librivox'];
// The fixture never runs the 20k catalog sync. These argument-domain defaults declare the
// seeded rows a complete local catalog, which is what unlocks local search and the filters.
const catalogReady = ['-librivox.lastCatalogSyncDate', String(Math.floor(Date.now() / 1000)), '-librivox.genresBackfillDone', 'YES'];

/** Mirrors BrowseLibriVoxViewModel.curatedClassicIDs and its `dayOfYear % count` choice. */
const curatedTitles = [
  'Adventures of Sherlock Holmes', 'Pride and Prejudice', 'Jane Eyre', 'Frankenstein, or The Modern Prometheus',
  'Dracula', 'Treasure Island', 'War of the Worlds', 'Tale of Two Cities',
];
function todaysPickTitle(now = new Date()): string {
  const startOfYear = new Date(now.getFullYear(), 0, 1);
  const dayOfYear = Math.floor((now.getTime() - startOfYear.getTime()) / 86_400_000) + 1;
  return curatedTitles[dayOfYear % curatedTitles.length];
}

test('daily pick, collections and Other Recordings browse from the offline cache', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: [...base, '-e2e-reset-fixture'] });
  await screen.getByTestId('shelvesTab').tap();
  const pick = todaysPickTitle();
  // The hero card is one accessible button: "TODAY'S PICK · 6H 20M, <title>, by <author>, <blurb>".
  await expect(screen.getByRole('button', new RegExp(`^TODAY'S PICK · [^,]+, ${pick}, by `)).first()).toBeVisible();

  // Collections are a horizontal rail; swipe along the rail itself until the card shows.
  const rail = await screen.getByRole('button', /^Ancient Wisdom, \d+ books$/).boundingBox();
  if (!rail) throw new Error('Collections rail has no bounds');
  const loveAndSociety = screen.getByRole('button', /^Love & Society, \d+ books$/);
  for (let attempt = 0; attempt < 6 && !(await loveAndSociety.isVisible()); attempt++) {
    const y = rail.y + rail.height / 2;
    await screen.swipe({ from: { x: 360, y }, to: { x: 60, y } });
  }
  await tapVisibleCenter(loveAndSociety);
  for (const title of ['Pride and Prejudice', 'Jane Eyre', 'Persuasion', 'Sense and Sensibility', 'Emma', 'Wuthering Heights']) {
    await screen.scrollUntilVisible(screen.getByText(title, { exact: true }).first());
  }
  await screen.scrollUntilVisible(screen.getByText('Pride and Prejudice', { exact: true }).first());
  await tapVisibleCenter(screen.getByText('Pride and Prejudice', { exact: true }).first());
  await screen.scrollUntilVisible(screen.getByText('Other Recordings').first());
  await screen.scrollUntilVisible(screen.getByText('Version 2').first());
  await tapVisibleCenter(screen.getByText('Version 2').first());
  await expect(screen.getByText('Pride and Prejudice (version 2)').first()).toBeVisible();
  // The alternate's own section points back at the original recording.
  await screen.scrollUntilVisible(screen.getByText('Original').first());
});

test('language, genre and length filters narrow the local catalog', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: [...base, ...catalogReady, '-e2e-reset-fixture'] });
  await screen.getByTestId('shelvesTab').tap();
  await expect(screen.getByText('Filters available when offline search is ready.')).toBeHidden();

  // Filter labels render small caps, so the accessible text is upper-case.
  await screen.getByText('LANGUAGE', { exact: true }).first().tap();
  await screen.getByRole('button', 'German').tap();
  await expect(screen.getByText('Die Verwandlung').first()).toBeVisible();
  await expect(screen.getByText('Jane Eyre', { exact: true })).toBeHidden();
  await screen.getByText('GERMAN', { exact: true }).first().tap();
  await screen.getByRole('button', 'All Languages').tap();

  await screen.getByText('GENRE', { exact: true }).first().tap();
  await screen.getByRole('button', 'Detective Fiction').tap();
  await expect(screen.getByText('Adventures of Sherlock Holmes').first()).toBeVisible();
  await expect(screen.getByText('Persuasion', { exact: true })).toBeHidden();
  await screen.getByText('DETECTIVE FICTION', { exact: true }).first().tap();
  await screen.getByRole('button', 'All Genres').tap();

  await screen.getByText('LENGTH', { exact: true }).first().tap();
  await screen.getByRole('button', '1–3 hrs').tap();
  await expect(screen.getByText('Die Verwandlung').first()).toBeVisible();
  await expect(screen.getByText('Dracula', { exact: true })).toBeHidden();
});

test('a failed download retries, completes, and plays from disk with the server gone', {
  timeout: 300_000,
}, async ({ device, screen }) => {
  let feed: FakeLibriVox | undefined = await startFakeLibriVox();
  try {
    const online = [...base, '-e2e-online', '-e2e-librivox-feed', feed.feedURL];
    // The first chapter request fails with an HTML 500, like an archive.org hiccup.
    feed.failAudio('449', 1, 500);
    await device.openApp(bundle, { relaunch: true, launchArguments: [...online, '-e2e-reset-fixture'] });
    await screen.getByTestId('shelvesTab').tap();
    await screen.getByRole('textbox').fill('Treasure Island');
    await screen.getByRole('textbox').press('Enter');
    await expect(screen.getByText('Treasure Island', { exact: true }).first()).toBeVisible({ timeout: 30_000 });
    await tapVisibleCenter(screen.getByText('Treasure Island', { exact: true }).first());
    await screen.scrollUntilVisible(screen.getByRole('button', 'Download Free Book'));
    await tapVisibleCenter(screen.getByRole('button', 'Download Free Book'));

    await expect(screen.getByRole('button', 'Try Again').first()).toBeVisible({ timeout: 60_000 });
    expect(feed.audioRequests('449').length).toBeGreaterThanOrEqual(1);
    await tapVisibleCenter(screen.getByRole('button', 'Try Again').first());
    await expect(screen.getByText('Added to Your Library').first()).toBeVisible({ timeout: 90_000 });
    // One failed attempt plus both chapters on the retry.
    expect(feed.audioRequests('449').length).toBeGreaterThanOrEqual(3);

    await feed.close();
    feed = undefined;
    await device.openApp(bundle, { relaunch: true, launchArguments: base });
    await screen.getByTestId('libraryTab').tap();
    await tapVisibleCenter(screen.getByText('Treasure Island', { exact: true }).first());
    await screen.getByTestId('book.play').tap();
    await expect(screen.getByTestId('player.playPause')).toHaveAccessibleName('Pause playback', { timeout: 30_000 });
    await expect(screen.getByText('Connecting to stream…')).toBeHidden();
  } finally {
    await feed?.close();
  }
});
