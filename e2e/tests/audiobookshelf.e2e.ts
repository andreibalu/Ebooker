import { expect, type Screen } from 'e2e';
import { test, tapVisibleCenter, longPressVisibleTop } from './native-actions.js';
import { bundle } from '../support/simulator.js';
import {
  ABS_API_KEY, ABS_PASSWORD, ABS_USERNAME, startFakeAudiobookshelf, type FakeAudiobookshelf,
} from '../support/fake-audiobookshelf.js';

// `-e2e-online` lets NetworkMonitor report a connection; the fixture is offline by default.
// The fixture keeps its ABS login in a separate Keychain item that `-e2e-reset-fixture` clears.
const fixture = ['-e2e-fixture', '-e2e-online', '-onboardingComplete', 'YES', '-startOnFreeBooks', 'NO', '-shelvesSource', 'librivox'];
const reset = [...fixture, '-e2e-reset-fixture'];
// Once connected, the Shelves tab shows the server instead of LibriVox.
const onServer = ['-e2e-fixture', '-e2e-online', '-onboardingComplete', 'YES', '-startOnFreeBooks', 'NO', '-shelvesSource', 'audiobookshelf'];

type Keyboard = { typeFocusedText: (text: string) => Promise<void>; submitFocused: () => Promise<void> };

async function openConnectSheet(screen: Screen) {
  await screen.getByTestId('shelvesTab').tap();
  // Tapping the selected Shelves tab opens its source menu.
  await screen.getByTestId('shelvesTab').tap();
  await screen.getByRole('button', /Audiobookshelf/).tap();
  await expect(screen.getByTestId('abs.connect.server')).toBeVisible();
}

async function signIn(screen: Screen, keyboard: Keyboard, server: string, password = ABS_PASSWORD) {
  await screen.getByTestId('abs.connect.server').fill(server);
  await screen.getByTestId('abs.connect.username').fill(ABS_USERNAME);
  await screen.getByTestId('abs.connect.username').press('Enter');
  await keyboard.typeFocusedText(password);
  await keyboard.submitFocused();
}

async function withServer(body: (server: FakeAudiobookshelf) => Promise<void>) {
  const server = await startFakeAudiobookshelf();
  try { await body(server); } finally { await server.close(); }
}

test('signing in shows the server shelf, filters it, and switches libraries', async ({ device, screen, nativeKeyboard }) => {
  await withServer(async (server) => {
    await device.openApp(bundle, { relaunch: true, launchArguments: reset });
    await openConnectSheet(screen);
    await signIn(screen, nativeKeyboard, server.serverURL);
    await expect(screen.getByTestId('abs.browse')).toBeVisible({ timeout: 30_000 });
    await expect(screen.getByRole('button', 'The Fixture Hobbit, by E2E Tolkien')).toBeVisible({ timeout: 30_000 });
    // Dune is 12 s into 30 s on the server, so Continue Listening leads with it.
    await expect(screen.getByText('Continue Listening', { exact: true })).toBeVisible();
    await expect(screen.getByRole('button', 'Dune of Fixtures, by E2E Herbert, 40 percent listened')).toBeVisible();
    // The poetry book lives in the other book library.
    await expect(screen.getByText('Collected Test Poems')).toBeHidden();

    await screen.getByTestId('abs.browse.search').fill('Tolkien');
    await expect(screen.getByRole('button', 'The Fixture Hobbit, by E2E Tolkien')).toBeVisible();
    await expect(screen.getByRole('button', 'Dune of Fixtures, by E2E Herbert')).toBeHidden();
    await screen.getByTestId('abs.browse.search').fill('no such title');
    await expect(screen.getByText(/No titles or authors match/).first()).toBeVisible();
    await screen.getByLabel('Clear search').tap();

    await screen.getByTestId('abs.browse.libraryMenu').tap();
    // Podcast libraries are never offered.
    await expect(screen.getByRole('button', 'Podcasts')).toBeHidden();
    await screen.getByRole('button', 'Poetry Shelf').tap();
    await expect(screen.getByRole('button', 'Collected Test Poems, by E2E Dickinson')).toBeVisible({ timeout: 30_000 });

    // The login and the chosen library survive a relaunch; nothing asks to sign in again.
    await device.openApp(bundle, { relaunch: true, launchArguments: onServer });
    await screen.getByTestId('shelvesTab').tap();
    await expect(screen.getByRole('button', 'Collected Test Poems, by E2E Dickinson')).toBeVisible({ timeout: 30_000 });
    expect(server.requests.filter((line) => line.startsWith('POST /login'))).toHaveLength(1);
  });
});

test('a server book is added, streams with the token, reports progress, and is removed from Unpaged only', {
  timeout: 300_000,
}, async ({ device, screen, nativeKeyboard }) => {
  await withServer(async (server) => {
    await device.openApp(bundle, { relaunch: true, launchArguments: reset });
    await openConnectSheet(screen);
    await signIn(screen, nativeKeyboard, server.serverURL);

    // Dune's server position comes along when it is opened.
    await tapVisibleCenter(screen.getByRole('button', 'Dune of Fixtures, by E2E Herbert').first());
    await expect(screen.getByTestId('abs.detail.title')).toHaveText('Dune of Fixtures');
    await expect(screen.getByTestId('abs.detail.status')).toContainText('40% listened');
    await screen.getByRole('button', 'Back').first().tap();

    await tapVisibleCenter(screen.getByRole('button', 'The Fixture Hobbit, by E2E Tolkien').first());
    await expect(screen.getByText('Read by E2E Narrator').first()).toBeVisible();
    await screen.getByTestId('abs.detail.add').tap();
    await expect(screen.getByText('In your Library', { exact: true })).toBeVisible({ timeout: 30_000 });
    await expect(screen.getByTestId('abs.detail.add')).toBeHidden();

    await screen.getByTestId('abs.detail.play').tap();
    await expect(screen.getByTestId('player.playPause')).toHaveAccessibleName('Pause playback', { timeout: 30_000 });
    await expect(screen.getByTestId('player.title')).toHaveText('The Fixture Hobbit Part 1');
    // AVPlayer cannot send headers, so the stream URL carries the session token at play time.
    const tokens = server.audioTokens('abs-hobbit');
    expect(tokens.length).toBeGreaterThan(0);
    expect(tokens.every((token) => token === 'e2e-access-token')).toBe(true);
    await expect(screen.getByTestId('player.scrubber')).toHaveValue(/^00:0[2-9] of 00:30$/, { timeout: 15_000 });
    await screen.getByTestId('player.playPause').tap();
    await expect.poll(() => server.progressPatches.filter((patch) => patch.itemID === 'abs-hobbit' && patch.currentTime > 0).length,
      { timeout: 15_000 }).toBeGreaterThan(0);
    const patch = server.progressPatches.filter((entry) => entry.itemID === 'abs-hobbit').at(-1)!;
    expect(patch.duration).toBe(60);
    expect(patch.isFinished).toBe(false);
    await screen.getByRole('button', 'Close player').tap();
    // The detail now reads the saved position and offers to resume.
    await expect(screen.getByTestId('abs.detail.listened')).toHaveText(/^\d+% listened$/);
    await expect(screen.getByTestId('abs.detail.play')).toHaveAccessibleName('Resume');
    await screen.getByRole('button', 'Back').first().tap();

    // The mini player overlaps the tab bar's hit test, so tap the tab's uncovered center.
    await tapVisibleCenter(screen.getByTestId('libraryTab'));
    // The card is badged as a stream ("Playing, " leads while it is the current book).
    const card = screen.getByRole('button', /The Fixture Hobbit, E2E Tolkien, .*Stream$/).first();
    await expect(card).toBeVisible();
    await longPressVisibleTop(card);
    await screen.getByRole('button', 'Remove from Library').tap();
    await expect(screen.getByText(/stays on your Audiobookshelf server/).first()).toBeVisible();
    await screen.getByRole('button', 'Remove from Library').last().tap();
    await expect(screen.getByText('The Fixture Hobbit').first()).toBeHidden();
    await device.openApp(bundle, { relaunch: true, launchArguments: onServer });
    await screen.getByTestId('libraryTab').tap();
    await expect(screen.getByText('The Fixture Hobbit').first()).toBeHidden();
    expect(server.requests.some((line) => line.startsWith('DELETE'))).toBe(false);
  });
});

test('an API key connects, Settings shows the server, and Disconnect forgets it', async ({ device, screen, nativeKeyboard }) => {
  await withServer(async (server) => {
    await device.openApp(bundle, { relaunch: true, launchArguments: reset });
    await openConnectSheet(screen);
    await screen.getByTestId('abs.connect.mode.apiKey').tap();
    await screen.getByTestId('abs.connect.server').fill(server.serverURL);
    await screen.getByTestId('abs.connect.server').press('Enter');
    await nativeKeyboard.typeFocusedText(ABS_API_KEY);
    await nativeKeyboard.submitFocused();
    await expect(screen.getByRole('button', 'The Fixture Hobbit, by E2E Tolkien')).toBeVisible({ timeout: 30_000 });
    expect(server.requests).toContain('POST /api/authorize');

    await screen.getByTestId('settingsButton').tap();
    // Sources lead Settings; the row's status line names the connected server.
    await expect(screen.getByTestId('settings.audiobookshelf.status')).toContainText('127.0.0.1');
    await tapVisibleCenter(screen.getByRole('button', /^Audiobookshelf Server/));
    await expect(screen.getByTestId('abs.settings.host')).toContainText('127.0.0.1:47378');
    await tapVisibleCenter(screen.getByTestId('abs.settings.disconnect'));
    await tapVisibleCenter(screen.getByTestId('abs.settings.disconnect.confirm').last());
    await expect(screen.getByTestId('abs.settings.connect')).toBeVisible();

    // Nothing is remembered: Shelves falls back to LibriVox, and the source menu offers setup.
    await device.openApp(bundle, { relaunch: true, launchArguments: onServer });
    await screen.getByTestId('shelvesTab').tap();
    await expect(screen.getByTestId('abs.browse')).toBeHidden();
    await screen.getByTestId('shelvesTab').tap();
    await screen.getByRole('button', /Audiobookshelf/).tap();
    await expect(screen.getByTestId('abs.connect.server')).toBeVisible();
  });
});

test('a wrong password is reported on the password field and saves nothing', async ({ device, screen, nativeKeyboard }) => {
  await withServer(async (server) => {
    await device.openApp(bundle, { relaunch: true, launchArguments: reset });
    await openConnectSheet(screen);
    await signIn(screen, nativeKeyboard, server.serverURL, 'not-the-password');
    await expect(screen.getByTestId('abs.connect.password.error')).toBeVisible({ timeout: 30_000 });
    await expect(screen.getByTestId('abs.browse')).toBeHidden();
    expect(server.requests.filter((line) => line.startsWith('GET /api/'))).toHaveLength(0);
  });
});

test('plain http to a public host warns before any credential is sent', async ({ device, screen, nativeKeyboard }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: reset });
  await openConnectSheet(screen);
  // example.com subdomains do not resolve, so even Continue cannot leak the dummy password.
  await signIn(screen, nativeKeyboard, 'http://abs.example.com', 'dummy-password');
  await expect(screen.getByText(/abs\.example\.com uses plain http:\/\//).first()).toBeVisible();
  await tapVisibleCenter(screen.getByTestId('abs.connect.insecure.cancel').last());
  await expect(screen.getByText(/uses plain http:\/\//)).toBeHidden();
  await expect(screen.getByTestId('abs.connect.server')).toBeVisible();

  await screen.getByRole('button', 'Connect').tap();
  await tapVisibleCenter(screen.getByTestId('abs.connect.insecure.continue').last());
  await expect(screen.getByText(/Can't reach abs\.example\.com/).first()).toBeVisible({ timeout: 45_000 });
});

test('an unreachable server shows Retry, and Retry loads the shelf once it is back', async ({ device, screen, nativeKeyboard }) => {
  let server = await startFakeAudiobookshelf();
  try {
    await device.openApp(bundle, { relaunch: true, launchArguments: reset });
    await openConnectSheet(screen);
    await signIn(screen, nativeKeyboard, server.serverURL);
    await expect(screen.getByRole('button', 'The Fixture Hobbit, by E2E Tolkien')).toBeVisible({ timeout: 30_000 });
    await server.close();

    await device.openApp(bundle, { relaunch: true, launchArguments: onServer });
    await screen.getByTestId('shelvesTab').tap();
    await expect(screen.getByText("Can't reach 127.0.0.1:47378.").first()).toBeVisible({ timeout: 45_000 });
    server = await startFakeAudiobookshelf();
    await screen.getByTestId('abs.browse.retry').tap();
    await expect(screen.getByRole('button', 'The Fixture Hobbit, by E2E Tolkien')).toBeVisible({ timeout: 30_000 });
  } finally {
    await server.close();
  }
});
