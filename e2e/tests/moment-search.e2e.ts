import { expect } from 'e2e';
import { test, fillSearchWhenSettled } from './native-actions.js';
import { bundle } from '../support/simulator.js';

const fixture = ['-e2e-fixture', '-e2e-reset-fixture', '-e2e-moment-search', '-onboardingComplete', 'YES', '-startOnFreeBooks', 'NO'];
const cases = [
  ['quote word', 'lantern', 'E2E Harbor'],
  ['character name', 'Ariadne', 'E2E Arrival'],
  ['diacritic folded spelling', 'cafe', 'E2E Café'],
  ['multi-word AND matching', 'lantern listening', 'E2E Harbor'],
] as const;
for (const [name, query, label] of cases) {
  test(`moment search: ${name}`, async ({ device, screen, app }) => {
    await device.openApp(bundle, { relaunch: true, launchArguments: fixture });
    await screen.getByTestId('momentSearchButton').tap();
    await fillSearchWhenSettled(screen, 'Search saved moments', query);
    await expect(screen.getByTestId(`momentSearch.row.${label}`)).toBeVisible();
    await expect(screen.getByTestId('momentSearch.row.E2E Unrelated')).toBeHidden();
    await app.screenshot(`moment-search-${name.replaceAll(' ', '-')}`);
  });
}

test('moment search: no results and AND exclusion', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: fixture });
  await screen.getByTestId('momentSearchButton').tap();
  await fillSearchWhenSettled(screen, 'Search saved moments', 'lantern Ariadne');
  await expect(screen.getByTestId('momentSearch.noResults')).toBeVisible();
  await fillSearchWhenSettled(screen, 'Search saved moments', 'zzzzmissing');
  await expect(screen.getByTestId('momentSearch.noResults')).toBeVisible();
});

test('moment search: result opens the correct book and time', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: fixture });
  await screen.getByTestId('momentSearchButton').tap();
  await fillSearchWhenSettled(screen, 'Search saved moments', 'Ariadne');
  await screen.getByTestId('momentSearch.row.E2E Arrival').tap();
  await expect(screen.getByTestId('player.title')).toHaveText('E2E Another Book');
  await expect(screen.getByTestId('player.scrubber')).toHaveValue(/^01:(28|29|30|31|32) of 05:00$/);
  await screen.getByTestId('player.playPause').tap();
});

test('moment search: orphan row is disabled', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: fixture });
  await screen.getByTestId('momentSearchButton').tap();
  // The empty query lists recent moments, so the orphan row is reachable without typing.
  await expect(screen.getByTestId('momentSearch.recent')).toBeVisible();
  await expect(screen.getByTestId('momentSearch.row.E2E Orphan')).toBeDisabled();
  await expect(screen.getByTestId('momentSearch.row.E2E Orphan')).toContainText('Audio is not on this iPhone');
});

test('moment search: disconnected Audiobookshelf row is disabled', async ({ device, screen }) => {
  // Online, so the row is disabled for the missing connection rather than the network.
  await device.openApp(bundle, { relaunch: true, launchArguments: [...fixture, '-e2e-online'] });
  await screen.getByTestId('momentSearchButton').tap();
  await fillSearchWhenSettled(screen, 'Search saved moments', 'Server Moment');
  await expect(screen.getByTestId('momentSearch.row.E2E Server Moment')).toBeDisabled();
  await expect(screen.getByTestId('momentSearch.row.E2E Server Moment')).toContainText('Connect your Audiobookshelf server to play');
});

test('moment search: row whose track file is missing is disabled', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: fixture });
  await screen.getByTestId('momentSearchButton').tap();
  await fillSearchWhenSettled(screen, 'Search saved moments', 'Missing Track');
  await expect(screen.getByTestId('momentSearch.row.E2E Missing Track')).toBeDisabled();
  await expect(screen.getByTestId('momentSearch.row.E2E Missing Track')).toContainText('Audio is not on this iPhone');
});

// "lighthouse" appears only in the transcript of the listening book's "E2E Second Moment".
test('moment search: a transcript-only word finds the moment and shows a snippet', async ({ device, screen, app }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: fixture });
  await screen.getByTestId('momentSearchButton').tap();
  await fillSearchWhenSettled(screen, 'Search saved moments', 'lighthouse');
  await expect(screen.getByTestId('momentSearch.row.E2E Second Moment')).toBeVisible();
  const snippet = screen.getByTestId('momentSearch.snippet.E2E Second Moment');
  await expect(snippet).toBeVisible();
  await expect(snippet).toContainText('lighthouse');
  // At most two lines: the snippet windows the transcript instead of printing all of it.
  const box = await snippet.boundingBox();
  if (!box) throw new Error('Snippet has no bounds');
  expect(box.height).toBeLessThan(60);
  await expect(screen.getByTestId('momentSearch.row.E2E Harbor')).toBeHidden();
  await expect(screen.getByTestId('momentSearch.row.E2E Unrelated')).toBeHidden();
  await app.screenshot('moment-search-transcript-snippet');
});

test('moment search: a transcript-only multi-word query matches, and mixed words need all of them', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: fixture });
  await screen.getByTestId('momentSearchButton').tap();
  await fillSearchWhenSettled(screen, 'Search saved moments', 'lighthouse keeper');
  await expect(screen.getByTestId('momentSearch.row.E2E Second Moment')).toBeVisible();
  // The cast and the transcript each match one word.
  await fillSearchWhenSettled(screen, 'Search saved moments', 'lighthouse Marlow');
  await expect(screen.getByTestId('momentSearch.row.E2E Second Moment')).toBeVisible();
  // A word from the transcript and one from another moment never match one row.
  await fillSearchWhenSettled(screen, 'Search saved moments', 'lighthouse lantern');
  await expect(screen.getByTestId('momentSearch.noResults')).toBeVisible();
});

test('moment search: a hit in the name, note or quote shows no transcript snippet', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: fixture });
  await screen.getByTestId('momentSearchButton').tap();
  // "fog" is in the note and "strangers" in the quote and the transcript: both are visible
  // elsewhere on the row, so the row needs no snippet.
  await fillSearchWhenSettled(screen, 'Search saved moments', 'fog');
  await expect(screen.getByTestId('momentSearch.row.E2E Second Moment')).toBeVisible();
  await expect(screen.getByTestId('momentSearch.snippet.E2E Second Moment')).toBeHidden();
  await fillSearchWhenSettled(screen, 'Search saved moments', 'strangers');
  await expect(screen.getByTestId('momentSearch.row.E2E Second Moment')).toBeVisible();
  await expect(screen.getByTestId('momentSearch.snippet.E2E Second Moment')).toBeHidden();
  await fillSearchWhenSettled(screen, 'Search saved moments', 'lantern');
  await expect(screen.getByTestId('momentSearch.row.E2E Harbor')).toBeVisible();
  await expect(screen.getByTestId('momentSearch.snippet.E2E Harbor')).toBeHidden();
});
