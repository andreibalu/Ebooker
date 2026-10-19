import { expect, type Locator, type Screen } from 'e2e';
import { test, tapVisibleCenter, longPressVisibleTop } from './native-actions.js';
import { bundle } from '../support/simulator.js';

// Free iCloud sync and audio in iCloud, without CloudKit or a real iCloud account.
// `-e2e-icloud-account` stands in for a signed-in account, so the real sync gate, its
// relaunch rule and every sync-on surface run while the fixture store stays local.
// `-e2e-icloud-drive` swaps the iCloud Drive container for a folder in the fixture store whose
// files "upload" and "download" on a clock (see Pageless/App/E2ECloudAudioBackend.swift).
// What these runs cannot show: CloudKit carrying records between devices, the system iCloud
// Drive daemon moving real bytes, quota and cellular policy on a real account.
const base = ['-e2e-fixture', '-onboardingComplete', 'YES', '-startOnFreeBooks', 'NO'];
const account = ['-e2e-icloud-account'];
// A launch argument fixes a preference for the whole run, so tests that flip a toggle in the
// UI leave these out and change it through the screen instead.
const syncOn = [...account, '-iCloudSyncEnabled', 'YES'];
const drive = ['-e2e-icloud-drive'];

/** Scrolls down to `target`, and back up if a slow snapshot let a swipe carry it past. */
async function scrollTo(screen: Screen, target: Locator): Promise<void> {
  try {
    await screen.scrollUntilVisible(target, { timeout: 15_000 });
  } catch {
    await screen.scrollUntilVisible(target, { direction: 'up' });
  }
}

/** A tap that lands while the list is still settling can miss the row; try once more. */
async function push(row: Locator, arrived: Locator): Promise<void> {
  await tapVisibleCenter(row);
  try {
    await expect(arrived).toBeVisible({ timeout: 5_000 });
  } catch {
    await tapVisibleCenter(row);
    await expect(arrived).toBeVisible();
  }
}

async function openSettings(screen: Screen): Promise<void> {
  await screen.getByTestId('settingsButton').tap();
  await scrollTo(screen, screen.getByTestId('settings.icloud'));
}

async function openICloudSettings(screen: Screen): Promise<void> {
  await openSettings(screen);
  await push(screen.getByTestId('settings.icloud'), syncSwitch(screen));
}

async function openCloudLibrary(screen: Screen): Promise<void> {
  await openSettings(screen);
  await scrollTo(screen, screen.getByTestId('settings.cloudLibrary'));
  await push(screen.getByTestId('settings.cloudLibrary'), screen.getByText('iCloud Library', { exact: true }).first());
}

const back = (screen: Screen) => screen.getByRole('button', 'Back').first();

/**
 * Picks own books, then jumps to the iCloud scene. Picking animates to Permissions; a rail tap
 * during that animation can land on the wrong page, so wait for it to settle first.
 */
async function openOnboardingCloudScene(screen: Screen): Promise<void> {
  await screen.getByTestId('onboarding.choice.own').tap();
  await expect(screen.getByText('Two quick permissions.').first()).toBeVisible();
  await push(screen.getByTestId('onboarding.page.5'), screen.getByText('Everything in sync.').first());
}
// iOS 18 reports List section headers in capitals.
const inICloudOnly = /^In iCloud only$/i;

const syncSwitch = (screen: Screen) => screen.getByTestId('icloud.syncToggle').getByRole('switch').last();
const audioSwitch = (screen: Screen) => screen.getByTestId('icloud.audioToggle').getByRole('switch').last();

test('a free user turns iCloud sync on in Settings, and it takes effect after relaunch', async ({ device, screen, app }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: [...base, ...account, '-e2e-reset-fixture'] });
  await openSettings(screen);
  await expect(screen.getByTestId('settings.icloud')).toContainText('Off · free with your iCloud account');
  await expect(screen.getByTestId('settings.cloudLibrary')).toBeHidden();
  await push(screen.getByTestId('settings.icloud'), syncSwitch(screen));

  // No Plus purchase anywhere on the page: the toggle is enabled for a free user.
  await expect(screen.getByText(/Free with any iCloud account/).first()).toBeVisible();
  await expect(screen.getByText('View Unpaged Plus')).toBeHidden();
  await expect(syncSwitch(screen)).toBeEnabled();
  await expect(syncSwitch(screen)).toBeChecked({ checked: false });
  await tapVisibleCenter(syncSwitch(screen));
  await expect(screen.getByText('Relaunch Required').first()).toBeVisible();
  await tapVisibleCenter(screen.getByRole('button', 'OK'));
  await expect(screen.getByText(/Will turn on after relaunch/).first()).toBeVisible();
  // Audio waits for the relaunch too: this launch's store is still local.
  await expect(audioSwitch(screen)).toBeDisabled();
  await expect(screen.getByText(/Available after you reopen Unpaged with sync on/).first()).toBeVisible();
  await app.screenshot('icloud-free-toggle-pending');

  await device.openApp(bundle, { relaunch: true, launchArguments: [...base, ...account] });
  await expect(screen.getByTestId('book.card.E2E-Listening-Book')).toBeVisible();
  // The backup badge renders only while the gate is on.
  await expect(screen.getByLabel('Backed up to iCloud').first()).toBeVisible();
  await openSettings(screen);
  await expect(screen.getByTestId('settings.icloud')).toContainText('On · free with your iCloud account');
  // A short screen (iPhone SE) shows the row only after scrolling.
  await scrollTo(screen, screen.getByTestId('settings.cloudLibrary'));
  await push(screen.getByTestId('settings.icloud'), syncSwitch(screen));
  await expect(syncSwitch(screen)).toBeChecked();
  await expect(screen.getByText(/On — your library syncs across devices/).first()).toBeVisible();
  // Without iCloud Drive the audio option explains why it is off.
  await expect(audioSwitch(screen)).toBeDisabled();
  await expect(screen.getByText(/Turn on iCloud Drive for Unpaged/).first()).toBeVisible();
  await app.screenshot('icloud-free-sync-on');

  await tapVisibleCenter(syncSwitch(screen));
  await tapVisibleCenter(screen.getByRole('button', 'OK'));
  await expect(screen.getByText(/Will turn off after relaunch/).first()).toBeVisible();
  await device.openApp(bundle, { relaunch: true, launchArguments: [...base, ...account] });
  await expect(screen.getByTestId('book.card.E2E-Listening-Book')).toBeVisible();
  await expect(screen.getByLabel('Backed up to iCloud')).toBeHidden();
});

test('without an iCloud account the sync toggle explains how to sign in', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: [...base, '-e2e-reset-fixture'] });
  await openICloudSettings(screen);
  await expect(syncSwitch(screen)).toBeDisabled();
  await expect(screen.getByText(/Sign in to iCloud in System Settings/).first()).toBeVisible();
  await expect(audioSwitch(screen)).toBeDisabled();
});

test('onboarding offers iCloud sync as a free opt-in that starts on the next launch', async ({ device, screen, app }) => {
  const onboarding = ['-e2e-fixture', '-onboardingComplete', 'NO', '-startOnFreeBooks', 'NO', ...account];
  await device.openApp(bundle, { relaunch: true, launchArguments: [...onboarding, '-e2e-reset-fixture'] });
  await openOnboardingCloudScene(screen);
  const toggle = screen.getByTestId('onboarding.icloud.toggle').getByRole('switch').last();
  await expect(toggle).toBeChecked({ checked: false });
  await expect(screen.getByText(/Off\. You can turn it on in Settings anytime\./).first()).toBeVisible();
  await tapVisibleCenter(toggle);
  await expect(toggle).toBeChecked();
  await expect(screen.getByText('Starts the next time you open Unpaged.').first()).toBeVisible();
  await app.screenshot('icloud-onboarding-on');

  await screen.getByTestId('onboarding.page.6').tap();
  await screen.getByRole('button', 'Open Library').tap();
  await expect(screen.getByTestId('libraryTab')).toBeVisible();
  await device.openApp(bundle, { relaunch: true, launchArguments: ['-e2e-fixture', ...account] });
  await openSettings(screen);
  await expect(screen.getByTestId('settings.icloud')).toContainText('On · free with your iCloud account');
});

test('onboarding without an iCloud account keeps the sync toggle off and says why', async ({ device, screen }) => {
  await device.openApp(bundle, {
    relaunch: true,
    launchArguments: ['-e2e-fixture', '-onboardingComplete', 'NO', '-startOnFreeBooks', 'NO', '-e2e-reset-fixture'],
  });
  await openOnboardingCloudScene(screen);
  await expect(screen.getByTestId('onboarding.icloud.toggle').getByRole('switch').last()).toBeDisabled();
  await expect(screen.getByText('Sign in to iCloud in Settings to use sync.').first()).toBeVisible();
});

test('storing audio in iCloud uploads every book, survives Remove from this iPhone, and downloads back', {
  timeout: 300_000,
}, async ({ device, screen, app }) => {
  const args = [...base, ...syncOn, ...drive, '-e2e-icloud-upload-seconds', '3'];
  await device.openApp(bundle, { relaunch: true, launchArguments: [...args, '-e2e-reset-fixture'] });
  await openICloudSettings(screen);
  await expect(audioSwitch(screen)).toBeEnabled();
  await expect(screen.getByText(/Off — each device keeps its own audio/).first()).toBeVisible();
  await tapVisibleCenter(audioSwitch(screen));
  await expect(screen.getByText('Store audio in iCloud?').first()).toBeVisible();
  await tapVisibleCenter(screen.getByRole('button', 'Store All 2 Books'));
  await expect(screen.getByTestId('icloud.audioUsage')).toContainText(/Uploading 2 books/, { timeout: 5_000 });
  await app.screenshot('icloud-audio-uploading');
  await expect(screen.getByTestId('icloud.audioUsage')).toHaveText(/^2 books · .+ in iCloud$/, { timeout: 15_000 });
  await app.screenshot('icloud-audio-stored');
  await tapVisibleCenter(screen.getByRole('button', /^(Close|Done)$/).first());

  // The detail card tells the same story per book.
  await screen.getByTestId('book.card.E2E-Listening-Book').tap();
  await screen.scrollUntilVisible(screen.getByTestId('book.cloudAudio.status'));
  await expect(screen.getByTestId('book.cloudAudio.status')).toHaveText('Stored in iCloud. Your other devices can download it.');
  await app.screenshot('icloud-detail-stored');
  await back(screen).tap();

  // Remove from this iPhone keeps the record and, now, the audio in iCloud.
  await longPressVisibleTop(screen.getByTestId('book.card.E2E-Listening-Book'));
  await screen.getByRole('button', 'Delete').tap();
  await expect(screen.getByText(/The book and its audio stay in iCloud/).first()).toBeVisible();
  await app.screenshot('icloud-remove-from-iphone');
  await screen.getByRole('button', 'Remove from this iPhone').tap();
  await expect(screen.getByTestId('book.card.E2E-Listening-Book')).toBeHidden();

  // Cloud Library offers Download instead of Locate…, and the download restores the book.
  await openCloudLibrary(screen);
  await expect(screen.getByText(inICloudOnly).first()).toBeVisible();
  const download = screen.getByTestId('cloudLibrary.download.E2E-Listening-Book');
  await expect(download).toBeVisible();
  await app.screenshot('icloud-cloud-library-download');
  await tapVisibleCenter(download);
  await expect(screen.getByTestId('cloudLibrary.downloading.E2E-Listening-Book')).toBeVisible({ timeout: 5_000 });
  await app.screenshot('icloud-cloud-library-downloading');
  await expect(screen.getByTestId('cloudLibrary.audioStatus.E2E-Listening-Book')).toHaveText('Audio in iCloud', { timeout: 20_000 });
  await expect(screen.getByText(inICloudOnly)).toBeHidden();

  // The downloaded book is back in the library and plays after relaunch.
  await device.openApp(bundle, { relaunch: true, launchArguments: args });
  await screen.getByTestId('book.card.E2E-Listening-Book').tap();
  await screen.getByTestId('book.play').tap();
  await expect(screen.getByTestId('player.playPause')).toHaveAccessibleName('Pause playback');
  await screen.getByTestId('player.playPause').tap();
});

test('a book can leave iCloud on its own, and turning the setting off can remove the rest', {
  timeout: 300_000,
}, async ({ device, screen, app }) => {
  const args = [...base, ...syncOn, ...drive, '-e2e-icloud-upload-seconds', '1'];
  await device.openApp(bundle, { relaunch: true, launchArguments: [...args, '-e2e-reset-fixture'] });
  await screen.getByTestId('book.card.E2E-Listening-Book').tap();
  await screen.scrollUntilVisible(screen.getByTestId('book.cloudAudio.status'));
  await expect(screen.getByTestId('book.cloudAudio.status')).toHaveText(/^Only on this iPhone/);
  // Per book: store it with the global setting still off.
  await tapVisibleCenter(screen.getByTestId('book.cloudAudio.store'));
  await expect(screen.getByTestId('book.cloudAudio.status')).toHaveText(/^Stored in iCloud/, { timeout: 15_000 });
  await tapVisibleCenter(screen.getByTestId('book.cloudAudio.remove'));
  await expect(screen.getByText(/This iPhone keeps its copy/).first()).toBeVisible();
  await tapVisibleCenter(screen.getByRole('button', 'Remove Audio from iCloud'));
  await expect(screen.getByTestId('book.cloudAudio.status')).toHaveText(/^Only on this iPhone/, { timeout: 10_000 });
  await tapVisibleCenter(screen.getByTestId('book.cloudAudio.store'));
  await expect(screen.getByTestId('book.cloudAudio.status')).toHaveText(/^Stored in iCloud/, { timeout: 15_000 });
  await back(screen).tap();

  // Global setting on, then off with "Remove Audio from iCloud".
  await openICloudSettings(screen);
  await tapVisibleCenter(audioSwitch(screen));
  await tapVisibleCenter(screen.getByRole('button', 'Only New Books'));
  await expect(audioSwitch(screen)).toBeChecked();
  await expect(screen.getByTestId('icloud.audioUsage')).toHaveText(/^1 book · .+ in iCloud$/, { timeout: 10_000 });
  await tapVisibleCenter(audioSwitch(screen));
  await expect(screen.getByText('Stop storing audio in iCloud?').first()).toBeVisible();
  await app.screenshot('icloud-audio-off-prompt');
  await tapVisibleCenter(screen.getByRole('button', 'Remove Audio from iCloud'));
  await expect(audioSwitch(screen)).toBeChecked({ checked: false });
  await expect(screen.getByTestId('icloud.audioUsage')).toBeHidden({ timeout: 10_000 });

  // Removal is lasting: nothing comes back after relaunch.
  await device.openApp(bundle, { relaunch: true, launchArguments: args });
  await screen.getByTestId('book.card.E2E-Listening-Book').tap();
  await screen.scrollUntilVisible(screen.getByTestId('book.cloudAudio.status'));
  await expect(screen.getByTestId('book.cloudAudio.status')).toHaveText(/^Only on this iPhone/);
});

test('Cloud Library downloads a book another device stored, and keeps Locate… for the rest', {
  timeout: 240_000,
}, async ({ device, screen, app }) => {
  const args = [...base, ...syncOn, ...drive, '-e2e-cloud-audio'];
  await device.openApp(bundle, { relaunch: true, launchArguments: [...args, '-e2e-reset-fixture'] });
  await openCloudLibrary(screen);
  await expect(screen.getByText(inICloudOnly).first()).toBeVisible();
  await expect(screen.getByTestId('cloudLibrary.download.E2E-Cloud-Book')).toBeVisible();
  await expect(screen.getByTestId('cloudLibrary.download.E2E-Locate-Book')).toBeHidden();
  await expect(screen.getByRole('button', 'Locate…')).toBeVisible();
  await expect(screen.getByText(/Download brings back a book whose audio is in iCloud/).first()).toBeVisible();
  await app.screenshot('icloud-buckets-seeded');

  await tapVisibleCenter(screen.getByTestId('cloudLibrary.download.E2E-Cloud-Book'));
  await expect(screen.getByTestId('cloudLibrary.audioStatus.E2E-Cloud-Book')).toHaveText('Audio in iCloud', { timeout: 20_000 });
  await expect(screen.getByText(/^On this iPhone$/i).first()).toBeVisible();

  await device.openApp(bundle, { relaunch: true, launchArguments: args });
  await screen.getByTestId('libraryTab').tap();
  await expect(screen.getByTestId('book.card.E2E-Cloud-Book')).toBeVisible();
  await screen.getByTestId('book.card.E2E-Cloud-Book').tap();
  await screen.getByTestId('book.play').tap();
  await expect(screen.getByTestId('player.playPause')).toHaveAccessibleName('Pause playback');
  await screen.getByTestId('player.playPause').tap();
});

test('a book whose audio is in iCloud says so before it is deleted for good', async ({ device, screen, app }) => {
  const args = [...base, ...syncOn, ...drive, '-e2e-cloud-audio'];
  await device.openApp(bundle, { relaunch: true, launchArguments: [...args, '-e2e-reset-fixture'] });
  await openCloudLibrary(screen);
  await expect(screen.getByTestId('cloudLibrary.download.E2E-Cloud-Book')).toBeVisible();
  const title = await screen.getByText('E2E Cloud Book', { exact: true }).first().boundingBox();
  if (!title) throw new Error('Cloud Library row has no bounds');
  const y = title.y + title.height / 2;
  await screen.swipe({ from: { x: title.x + title.width, y }, to: { x: 20, y } });
  await tapVisibleCenter(screen.getByRole('button', 'Delete').first());
  await expect(screen.getByText(/progress, moments, EQ and audio from iCloud and all your devices/).first()).toBeVisible();
  await app.screenshot('icloud-delete-with-audio');
  await tapVisibleCenter(screen.getByRole('button', 'Delete Permanently'));
  await expect(screen.getByTestId('cloudLibrary.download.E2E-Cloud-Book')).toBeHidden();
  await device.openApp(bundle, { relaunch: true, launchArguments: args });
  await openCloudLibrary(screen);
  await expect(screen.getByText('E2E Cloud Book')).toBeHidden();
});

test('with the setting on, an imported book uploads; a full iCloud says so', {
  timeout: 240_000,
}, async ({ device, screen, app }) => {
  const args = [...base, ...syncOn, ...drive, '-iCloudAudioEnabled', 'YES', '-e2e-import'];
  await device.openApp(bundle, { relaunch: true, launchArguments: [...args, '-e2e-reset-fixture'] });
  await screen.getByTestId('importButton').tap();
  await screen.getByPlaceholder('Title').fill('E2E Cloud Import');
  await screen.getByRole('button', 'Save').tap();
  await screen.getByTestId('libraryTab').tap();
  await tapVisibleCenter(screen.getByText('E2E Cloud Import').first());
  await screen.scrollUntilVisible(screen.getByTestId('book.cloudAudio.status'));
  await expect(screen.getByTestId('book.cloudAudio.status')).toHaveText(/^Stored in iCloud/, { timeout: 15_000 });

  await device.openApp(bundle, { relaunch: true, launchArguments: [...base, ...syncOn, ...drive, '-e2e-icloud-full'] });
  await screen.getByTestId('book.card.E2E-Listening-Book').tap();
  await screen.scrollUntilVisible(screen.getByTestId('book.cloudAudio.store'));
  await tapVisibleCenter(screen.getByTestId('book.cloudAudio.store'));
  await expect(screen.getByTestId('book.cloudAudio.status')).toHaveText(/^iCloud storage is full/, { timeout: 10_000 });
  await app.screenshot('icloud-quota-full');
});
