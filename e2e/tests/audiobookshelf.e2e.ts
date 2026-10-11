import { expect, type Screen } from 'e2e';
import { test, tapVisibleCenter, longPressVisibleTop } from './native-actions.js';
import { appDataPath, bundle, terminate } from '../support/simulator.js';
import { existsSync, readFileSync, readdirSync, rmSync, statSync } from 'node:fs';
import { join } from 'node:path';
import {
  ABS_API_KEY, ABS_PASSWORD, ABS_USERNAME, startFakeAudiobookshelf, type FakeAudiobookshelf,
} from '../support/fake-audiobookshelf.js';

// `-e2e-online` lets NetworkMonitor report a connection; the fixture is offline by default.
// The fixture keeps its ABS login in a separate Keychain item that `-e2e-reset-fixture` clears.
const fixture = ['-e2e-fixture', '-e2e-online', '-onboardingComplete', 'YES', '-startOnFreeBooks', 'NO', '-shelvesSource', 'librivox'];
const reset = [...fixture, '-e2e-reset-fixture'];
// Once connected, the Shelves tab shows the server instead of LibriVox.
const onServer = ['-e2e-fixture', '-e2e-online', '-onboardingComplete', 'YES', '-startOnFreeBooks', 'NO', '-shelvesSource', 'audiobookshelf'];

const supportPath = () => join(appDataPath(), 'Library', 'Application Support');
const manifests = () => {
  const root = join(supportPath(), 'ABSDownloads');
  return existsSync(root) ? readdirSync(root).filter((name) => name.endsWith('.json')).map((name) => readFileSync(join(root, name), 'utf8')) : [];
};
function assertNoCachedTokens(root: string): void {
  if (!existsSync(root)) return;
  for (const entry of readdirSync(root)) {
    const path = join(root, entry);
    if (statSync(path).isDirectory()) assertNoCachedTokens(path);
    else {
      const value = readFileSync(path, 'utf8');
      expect(value).not.toContain('e2e-access-token');
      expect(value).not.toContain('e2e-refresh-token');
      expect(value).not.toContain('e2e-api-key');
    }
  }
}

type Keyboard = { typeFocusedText: (text: string) => Promise<void>; submitFocused: () => Promise<void> };

async function openConnectSheet(screen: Screen) {
  // The first tap selects Shelves; tapping the selected tab opens its source menu. Right after a
  // reset launch a tap can be dropped, so tap one at a time until the menu shows.
  const source = screen.getByRole('button', /Audiobookshelf/);
  for (let attempt = 0; attempt < 4; attempt++) {
    await screen.getByTestId('shelvesTab').tap();
    await expect.poll(() => source.isVisible(), { timeout: 3_000 }).toBe(true).catch(() => undefined);
    if (await source.isVisible()) break;
  }
  await source.tap();
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
    await expect(screen.getByTestId('player.smartMoments.downloadRequired')).toBeVisible();
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

test('an unreachable server shows cached shelves, and Retry refreshes once it is back', async ({ device, screen, nativeKeyboard }) => {
  let server = await startFakeAudiobookshelf();
  try {
    await device.openApp(bundle, { relaunch: true, launchArguments: reset });
    await openConnectSheet(screen);
    await signIn(screen, nativeKeyboard, server.serverURL);
    await expect(screen.getByRole('button', 'The Fixture Hobbit, by E2E Tolkien')).toBeVisible({ timeout: 30_000 });
    await server.close();

    await device.openApp(bundle, { relaunch: true, launchArguments: onServer });
    await screen.getByTestId('shelvesTab').tap();
    await expect(screen.getByTestId('abs.browse.offline')).toBeVisible({ timeout: 45_000 });
    await screen.scrollUntilVisible(screen.getByRole('button', 'The Fixture Hobbit, by E2E Tolkien'));
    await expect(screen.getByRole('button', 'The Fixture Hobbit, by E2E Tolkien')).toBeVisible();
    await screen.scrollUntilVisible(screen.getByTestId('abs.browse.retry'));
    server = await startFakeAudiobookshelf();
    await screen.getByTestId('abs.browse.retry').tap();
    await expect(screen.getByRole('button', 'The Fixture Hobbit, by E2E Tolkien')).toBeVisible({ timeout: 30_000 });
  } finally {
    await server.close();
  }
});

test('ABS downloads show progress, play after an offline relaunch, and return to streaming', { timeout: 300_000 }, async ({ device, screen, nativeKeyboard, app }) => {
  await withServer(async (server) => {
    server.audioDelayMS = 4_000;
    await device.openApp(bundle, { relaunch: true, launchArguments: reset });
    await openConnectSheet(screen);
    await signIn(screen, nativeKeyboard, server.serverURL);
    await tapVisibleCenter(screen.getByRole('button', 'The Fixture Hobbit, by E2E Tolkien').first());
    await screen.getByTestId('abs.detail.add').tap();
    await expect(screen.getByTestId('abs.ai.downloadRequired')).toBeVisible();
    await screen.getByTestId('abs.download.start').tap();
    await expect(screen.getByTestId('abs.download.progress')).toBeVisible();
    const jobs = manifests();
    expect(jobs).toHaveLength(1);
    expect(jobs[0]).not.toContain('e2e-access-token');
    expect(jobs[0]).not.toContain('e2e-refresh-token');
    await app.screenshot('abs-download-progress');
    await expect(screen.getByTestId('abs.download.remove')).toBeVisible({ timeout: 60_000 });
    await expect(screen.getByTestId('abs.ai.downloadRequired')).toBeHidden();
    assertNoCachedTokens(join(appDataPath(), 'Library', 'Caches', 'Audiobookshelf'));
    await server.close();
    await device.openApp(bundle, { relaunch: true, launchArguments: onServer });
    await screen.getByTestId('shelvesTab').tap();
    await expect(screen.getByTestId('abs.browse.offline')).toBeVisible({ timeout: 45_000 });
    await app.screenshot('abs-offline-cached-shelves');
    await expect(screen.getByText('Continue Listening', { exact: true })).toBeVisible();
    await screen.scrollUntilVisible(screen.getByRole('button', 'The Fixture Hobbit, by E2E Tolkien').first());
    await tapVisibleCenter(screen.getByRole('button', 'The Fixture Hobbit, by E2E Tolkien').first());
    await expect(screen.getByTestId('abs.download.remove')).toBeVisible();
    await screen.getByTestId('abs.detail.play').tap();
    await expect(screen.getByTestId('player.playPause')).toHaveAccessibleName('Pause playback', { timeout: 30_000 });
    await expect(screen.getByTestId('player.scrubber')).toHaveValue(/^00:0[2-9] of 00:30$/, { timeout: 15_000 });
    await expect(screen.getByTestId('player.smartMoments.downloadRequired')).toBeHidden();
    await app.screenshot('abs-downloaded-offline-playback');
    await screen.getByTestId('player.playPause').tap();
    await screen.getByRole('button', 'Close player').tap();
    await screen.getByTestId('abs.download.remove').tap();
    await expect(screen.getByTestId('abs.download.start')).toBeVisible();
    await expect(screen.getByTestId('abs.ai.downloadRequired')).toBeVisible();
    await expect(screen.getByTestId('abs.detail.play')).toBeDisabled();
    await app.screenshot('abs-download-removed-streaming');
  });
});

test('cancelling an ABS download keeps the book streaming across relaunch', async ({ device, screen, nativeKeyboard, app }) => {
  await withServer(async (server) => {
    server.audioDelayMS = 30_000;
    await device.openApp(bundle, { relaunch: true, launchArguments: reset });
    await openConnectSheet(screen);
    await signIn(screen, nativeKeyboard, server.serverURL);
    await tapVisibleCenter(screen.getByRole('button', 'The Fixture Hobbit, by E2E Tolkien').first());
    await screen.getByTestId('abs.detail.add').tap();
    await screen.getByTestId('abs.download.start').tap();
    await expect(screen.getByTestId('abs.download.progress')).toBeVisible();
    await screen.getByTestId('abs.download.cancel').tap();
    await expect(screen.getByTestId('abs.download.start')).toBeVisible();
    await expect(screen.getByTestId('abs.download.remove')).toBeHidden();
    await expect.poll(() => manifests().length).toBe(0);
    await expect.poll(() => readdirSync(join(supportPath(), 'ABSDownloads')).length).toBe(0);
    await device.openApp(bundle, { relaunch: true, launchArguments: onServer });
    await screen.getByTestId('shelvesTab').tap();
    await tapVisibleCenter(screen.getByRole('button', 'The Fixture Hobbit, by E2E Tolkien').first());
    await expect(screen.getByTestId('abs.download.start')).toBeVisible();
    await expect(screen.getByTestId('abs.ai.downloadRequired')).toBeVisible();
    await app.screenshot('abs-cancelled-download-remains-streaming');
  });
});

test('missing downloaded ABS files return the book to streaming after relaunch', async ({ device, screen, nativeKeyboard, app }) => {
  await withServer(async (server) => {
    server.audioDelayMS = 2_000;
    await device.openApp(bundle, { relaunch: true, launchArguments: reset });
    await openConnectSheet(screen);
    await signIn(screen, nativeKeyboard, server.serverURL);
    await tapVisibleCenter(screen.getByRole('button', 'The Fixture Hobbit, by E2E Tolkien').first());
    const audioRoot = join(supportPath(), 'Audiobooks');
    const previousFolders = new Set(existsSync(audioRoot) ? readdirSync(audioRoot) : []);
    await screen.getByTestId('abs.download.start').tap();
    await expect(screen.getByTestId('abs.download.progress')).toBeVisible();
    const job = JSON.parse(manifests()[0]) as { tracks: { id: string }[] };
    expect(job.tracks).toHaveLength(2);
    await expect(screen.getByTestId('abs.download.remove')).toBeVisible({ timeout: 60_000 });
    terminate(bundle);
    const absFolder = readdirSync(audioRoot).find((name) => !previousFolders.has(name) && existsSync(join(audioRoot, name, '0.wav')));
    expect(absFolder).toBeTruthy();
    rmSync(join(audioRoot, absFolder!), { recursive: true });
    await device.openApp(bundle, { relaunch: true, launchArguments: onServer });
    await screen.getByTestId('libraryTab').tap();
    await expect(screen.getByRole('button', /The Fixture Hobbit, E2E Tolkien, .*Stream$/).first()).toBeVisible({ timeout: 30_000 });
    await tapVisibleCenter(screen.getByRole('button', /The Fixture Hobbit, E2E Tolkien, .*Stream$/).first());
    await expect(screen.getByTestId('abs.download.start')).toBeVisible();
    await expect(screen.getByTestId('abs.ai.downloadRequired')).toBeVisible();
    await app.screenshot('abs-missing-files-returned-to-streaming');
  });
});

test('ABS storage controls keep downloads on disconnect and remove all audio with confirmation', { timeout: 300_000 }, async ({ device, screen, nativeKeyboard, app }) => {
  await withServer(async (server) => {
    server.audioDelayMS = 2_000;
    await device.openApp(bundle, { relaunch: true, launchArguments: reset });
    await openConnectSheet(screen);
    await signIn(screen, nativeKeyboard, server.serverURL);
    await tapVisibleCenter(screen.getByRole('button', 'The Fixture Hobbit, by E2E Tolkien').first());
    await screen.getByTestId('abs.download.start').tap();
    await expect(screen.getByTestId('abs.download.remove')).toBeVisible({ timeout: 60_000 });
    await device.openApp(bundle, { relaunch: true, launchArguments: onServer });
    await screen.getByTestId('settingsButton').tap();
    await tapVisibleCenter(screen.getByRole('button', /^Audiobookshelf Server/));
    await screen.scrollUntilVisible(screen.getByTestId('abs.settings.downloadSize'));
    await expect(screen.getByTestId('abs.settings.downloadSize')).toHaveText(/Downloaded audio: (?!Zero KB|0 bytes|0 KB).+/);
    await tapVisibleCenter(screen.getByTestId('abs.settings.disconnect'));
    await expect(screen.getByRole('button', 'Keep Downloads and Disconnect').last()).toBeVisible();
    await expect(screen.getByTestId('abs.settings.disconnect.removeDownloads').last()).toBeVisible();
    await tapVisibleCenter(screen.getByTestId('abs.settings.disconnect.confirm').last());
    await expect(screen.getByTestId('abs.settings.connect')).toBeVisible();
    await server.close();
    await device.openApp(bundle, { relaunch: true, launchArguments: onServer });
    await screen.getByTestId('libraryTab').tap();
    await tapVisibleCenter(screen.getByRole('button', /The Fixture Hobbit, E2E Tolkien/).first());
    await expect(screen.getByTestId('abs.download.remove')).toBeVisible();
    await screen.getByTestId('book.play').tap();
    await expect(screen.getByTestId('player.playPause')).toHaveAccessibleName('Pause playback', { timeout: 30_000 });
    await app.screenshot('abs-kept-download-plays-after-disconnect');
    await screen.getByTestId('player.playPause').tap();
    await device.openApp(bundle, { relaunch: true, launchArguments: onServer });
    await screen.getByTestId('settingsButton').tap();
    await tapVisibleCenter(screen.getByRole('button', /^Audiobookshelf Server/));
    await screen.scrollUntilVisible(screen.getByTestId('abs.settings.removeDownloads'));
    await tapVisibleCenter(screen.getByTestId('abs.settings.removeDownloads'));
    await expect(screen.getByText('Your books, progress, moments, and EQ stay in Unpaged. Audio will stream from your server.')).toBeVisible();
    // The dialog presents as a popover with no Cancel button; tapping outside it cancels.
    await tapVisibleCenter(screen.getByTestId('abs.settings.downloadSize'));
    await expect(screen.getByTestId('abs.settings.removeDownloads.confirm')).toBeHidden();
    await expect(screen.getByTestId('abs.settings.removeDownloads')).toBeEnabled();
    await tapVisibleCenter(screen.getByTestId('abs.settings.removeDownloads'));
    await tapVisibleCenter(screen.getByTestId('abs.settings.removeDownloads.confirm').last());
    await expect(screen.getByTestId('abs.settings.removeDownloads')).toBeDisabled();
    await expect(screen.getByTestId('abs.settings.downloadSize')).toHaveText(/Downloaded audio: (Zero KB|0 bytes|0 KB)/);
    await app.screenshot('abs-all-downloads-removed');
  });
});
