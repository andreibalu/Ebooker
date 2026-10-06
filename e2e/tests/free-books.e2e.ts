import { expect, type Screen } from 'e2e';
import { test, tapVisibleCenter, longPressVisibleTop } from './native-actions.js';
import { startFakeLibriVox, type FakeLibriVox } from '../support/fake-librivox.js';
import { bundle, openURL } from '../support/simulator.js';

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
  // Count calendar days in UTC. Local midnights differ by an hour across a daylight saving change,
  // which made the count one short between midnight and 1 a.m. from spring to autumn.
  const today = Date.UTC(now.getFullYear(), now.getMonth(), now.getDate());
  const dayOfYear = (today - Date.UTC(now.getFullYear(), 0, 1)) / 86_400_000 + 1;
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
  await expect(screen.getByText('Jane Eyre', { exact: true }).first()).toBeHidden();
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
    await openFromSearch(screen, 'Treasure Island');
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

    // A downloaded free book is removed with "Remove Download", which also unloads it.
    await screen.getByRole('button', 'Close player').tap();
    await screen.getByRole('button', 'Back').first().tap();
    const card = screen.getByRole('button', /Treasure Island, Robert Louis Stevenson/).first();
    await longPressVisibleTop(card);
    await screen.getByRole('button', 'Remove Download').tap();
    await expect(screen.getByText('Remove Download?').first()).toBeVisible();
    await screen.getByRole('button', 'Remove Download').last().tap();
    await expect(screen.getByText('Treasure Island', { exact: true }).first()).toBeHidden();
    await expect(screen.getByTestId('miniPlayer.title')).toBeHidden();
    await device.openApp(bundle, { relaunch: true, launchArguments: base });
    await screen.getByTestId('libraryTab').tap();
    await expect(screen.getByText('Treasure Island', { exact: true }).first()).toBeHidden();
  } finally {
    await feed?.close();
  }
});

async function openFromSearch(screen: Screen, title: string) {
  await screen.getByTestId('shelvesTab').tap();
  await screen.getByRole('textbox').fill(title);
  await screen.getByRole('textbox').press('Enter');
  // A result row reads "01, <title>, <author>, <length> · <size>".
  const row = screen.getByRole('button', new RegExp(`^\\d+, ${title}, `)).first();
  await expect(row).toBeVisible({ timeout: 30_000 });
  await tapVisibleCenter(row);
}

test('a book added to the library streams from the feed and "Remove from Library" takes it out', {
  timeout: 300_000,
}, async ({ device, screen }) => {
  const feed = await startFakeLibriVox();
  try {
    const online = [...base, '-e2e-online', '-e2e-librivox-feed', feed.feedURL];
    await device.openApp(bundle, { relaunch: true, launchArguments: [...online, '-e2e-reset-fixture'] });
    await openFromSearch(screen, 'Jane Eyre');
    await screen.scrollUntilVisible(screen.getByRole('button', 'Add to Library'));
    await tapVisibleCenter(screen.getByRole('button', 'Add to Library'));
    await expect(screen.getByText('Added to Your Library').first()).toBeVisible({ timeout: 30_000 });
    // Adding writes no audio: nothing is fetched until the book plays.
    expect(feed.audioRequests('133')).toHaveLength(0);

    await tapVisibleCenter(screen.getByRole('button', 'View in Library'));
    await screen.getByTestId('book.play').tap();
    await expect(screen.getByTestId('player.playPause')).toHaveAccessibleName('Pause playback', { timeout: 30_000 });
    expect(feed.audioRequests('133').length).toBeGreaterThan(0);
    await screen.getByRole('button', 'Close player').tap();
    // Back buttons carry the previous screen's title, so find them by identifier.
    await screen.getByTestId('BackButton').first().tap();
    await screen.getByTestId('BackButton').first().tap();

    await tapVisibleCenter(screen.getByTestId('libraryTab'));
    await longPressVisibleTop(screen.getByRole('button', /Jane Eyre, Charlotte Brontë, .*Stream$/).first());
    await screen.getByRole('button', 'Remove from Library').tap();
    await expect(screen.getByText('Remove from Library?').first()).toBeVisible();
    await screen.getByRole('button', 'Remove from Library').last().tap();
    await expect(screen.getByText('Jane Eyre', { exact: true }).first()).toBeHidden();
    await expect(screen.getByTestId('miniPlayer.title')).toBeHidden();
    await device.openApp(bundle, { relaunch: true, launchArguments: online });
    await screen.getByTestId('libraryTab').tap();
    await expect(screen.getByText('Jane Eyre', { exact: true }).first()).toBeHidden();
  } finally {
    await feed.close();
  }
});

test('the sample plays from 30 seconds in, stops on tap, and stops by itself after 20 seconds', {
  timeout: 300_000,
}, async ({ device, screen }) => {
  // The sample starts 30 seconds into chapter 1 and lasts 20, so chapters must outlast 50 seconds.
  const feed = await startFakeLibriVox({ trackSeconds: 60 });
  try {
    await device.openApp(bundle, { relaunch: true, launchArguments: [...base, '-e2e-online', '-e2e-librivox-feed', feed.feedURL, '-e2e-reset-fixture'] });
    await openFromSearch(screen, 'Dracula');
    const play = screen.getByRole('button', 'Play 20s Sample');
    const stop = screen.getByRole('button', 'Stop Sample');
    await tapVisibleCenter(play);
    await expect(stop).toBeVisible({ timeout: 30_000 });
    expect(feed.requests.some((path) => path.startsWith('/api/feed/audiotracks') && path.includes('project_id=271'))).toBe(true);
    expect(feed.audioRequests('271').length).toBeGreaterThan(0);
    await tapVisibleCenter(stop);
    await expect(play).toBeVisible();

    await tapVisibleCenter(play);
    await expect(stop).toBeVisible({ timeout: 30_000 });
    await expect(play).toBeVisible({ timeout: 40_000 });
  } finally {
    await feed.close();
  }
});

test('the downloads link opens Library at the download, and cancelling it leaves nothing behind', {
  timeout: 300_000,
}, async ({ device, screen }) => {
  // Each chapter takes 30 seconds to start arriving, so the download stays in progress.
  const feed = await startFakeLibriVox({ audioDelayMs: 30_000 });
  try {
    const online = [...base, '-e2e-online', '-e2e-librivox-feed', feed.feedURL];
    await device.openApp(bundle, { relaunch: true, launchArguments: [...online, '-e2e-reset-fixture'] });
    await openFromSearch(screen, 'War of the Worlds');
    await screen.scrollUntilVisible(screen.getByRole('button', 'Download Free Book'));
    await tapVisibleCenter(screen.getByRole('button', 'Download Free Book'));
    await expect(screen.getByRole('button', 'Cancel').first()).toBeVisible({ timeout: 30_000 });

    openURL('unpaged://library/downloads');
    // iOS may ask before a link from outside opens the app.
    const open = screen.getByRole('button', 'Open');
    await expect.poll(() => open.isVisible(), { timeout: 3_000 }).toBe(true).catch(() => undefined);
    if (await open.isVisible()) await open.tap();
    await expect(screen.getByText('Downloads · 1').first()).toBeVisible({ timeout: 15_000 });
    await expect(screen.getByText('War of the Worlds', { exact: true }).first()).toBeVisible();
    await screen.getByRole('button', 'Cancel download').tap();
    await expect(screen.getByText('Downloads · 1')).toBeHidden({ timeout: 30_000 });
    await expect(screen.getByText('War of the Worlds', { exact: true })).toBeHidden();

    await device.openApp(bundle, { relaunch: true, launchArguments: online });
    await screen.getByTestId('libraryTab').tap();
    await expect(screen.getByText('War of the Worlds', { exact: true })).toBeHidden();
  } finally {
    await feed.close();
  }
});

test('a search with no match says so, and a feed outage says the search failed', async ({ device, screen }) => {
  const feed = await startFakeLibriVox();
  try {
    await device.openApp(bundle, { relaunch: true, launchArguments: [...base, '-e2e-online', '-e2e-librivox-feed', feed.feedURL, '-e2e-reset-fixture'] });
    await screen.getByTestId('shelvesTab').tap();
    await screen.getByRole('textbox').fill('Qwertyuiop Zebra');
    await screen.getByRole('textbox').press('Enter');
    await expect(screen.getByText('Nothing on this shelf.').first()).toBeVisible({ timeout: 30_000 });

    feed.failSearch(10);
    await screen.getByRole('textbox').fill('Zebra Qwertyuiop');
    await screen.getByRole('textbox').press('Enter');
    await expect(screen.getByText('Couldn’t search LibriVox.').first()).toBeVisible({ timeout: 30_000 });
  } finally {
    await feed.close();
  }
});
