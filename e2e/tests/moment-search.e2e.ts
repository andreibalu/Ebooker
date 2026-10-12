import { expect } from 'e2e';
import { test } from './native-actions.js';
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
    await screen.getByPlaceholder('Search saved moments').fill(query);
    await expect(screen.getByTestId(`momentSearch.row.${label}`)).toBeVisible();
    await expect(screen.getByTestId('momentSearch.row.E2E Unrelated')).toBeHidden();
    await app.screenshot(`moment-search-${name.replaceAll(' ', '-')}`);
  });
}

test('moment search: no results and AND exclusion', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: fixture });
  await screen.getByTestId('momentSearchButton').tap();
  await screen.getByPlaceholder('Search saved moments').fill('lantern Ariadne');
  await expect(screen.getByTestId('momentSearch.noResults')).toBeVisible();
  await screen.getByPlaceholder('Search saved moments').fill('zzzzmissing');
  await expect(screen.getByTestId('momentSearch.noResults')).toBeVisible();
});

test('moment search: result opens the correct book and time', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: fixture });
  await screen.getByTestId('momentSearchButton').tap();
  await screen.getByPlaceholder('Search saved moments').fill('Ariadne');
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
  await screen.getByPlaceholder('Search saved moments').fill('Server Moment');
  await expect(screen.getByTestId('momentSearch.row.E2E Server Moment')).toBeDisabled();
  await expect(screen.getByTestId('momentSearch.row.E2E Server Moment')).toContainText('Connect your Audiobookshelf server to play');
});
