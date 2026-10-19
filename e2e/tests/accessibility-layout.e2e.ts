import { execFileSync } from 'node:child_process';
import { expect, type Screen } from 'e2e';
import { test, tapVisibleCenter } from './native-actions.js';
import { bundle, terminate, udid } from '../support/simulator.js';

// Reported configuration: accessibility-XXXL text + Button Shapes + Bold Text. Before the fix the
// header icon buttons gained an outer pill, "My Library" was squeezed to a sliver that wrapped a
// letter per line, and the header stretched a third of the way down the screen.
const fixture = ['-e2e-fixture', '-e2e-reset-fixture', '-onboardingComplete', 'YES', '-startOnFreeBooks', 'NO', '-e2e-import'];
const shelvesFixture = ['-e2e-fixture', '-onboardingComplete', 'YES', '-startOnFreeBooks', 'YES', '-shelvesSource', 'librivox'];
const screenHeight = 874;

// iOS 27 labels a sheet's dismiss button "Close" even when the app titles it "Done".
const dismissButton = (screen: Screen) => screen.getByRole('button', /^(Close|Done)$/).first();
// The simulator's hit test reports sheet toolbar buttons as covered; tap their current center.
const dismiss = (screen: Screen) => tapVisibleCenter(dismissButton(screen));

const simctl = (...args: string[]): void => {
  execFileSync('xcrun', ['simctl', ...args], { stdio: 'ignore' });
};
const accessibilityCommands = (on: boolean): string[][] => [
  ['ui', udid(), 'content_size', on ? 'accessibility-extra-extra-extra-large' : 'large'],
  ...['ButtonShapesEnabled', 'EnhancedTextLegibilityEnabled'].map((key) => [
    'spawn', udid(), 'defaults', 'write', 'com.apple.Accessibility', key, '-bool', on ? 'YES' : 'NO',
  ]),
];
const setAccessibility = (on: boolean): void => {
  for (const args of accessibilityCommands(on)) simctl(...args);
};

test.afterEach(() => {
  // Restore even on failure so later suites see the default text size and no Button Shapes. Each
  // command runs on its own, so one failing still lets the others restore their setting.
  const errors: unknown[] = [];
  for (const restore of [() => terminate(bundle), ...accessibilityCommands(false).map((args) => () => simctl(...args))]) {
    try {
      restore();
    } catch (error) {
      errors.push(error);
    }
  }
  if (errors.length > 0) throw errors[0];
});

test('large text with Button Shapes and Bold Text keeps the header, tabs and Shelves headings compact', async ({ device, screen, app }) => {
  setAccessibility(true);
  await device.openApp(bundle, { relaunch: true, launchArguments: fixture });

  const title = screen.getByText('My Library', { exact: true }).first();
  await expect(title).toBeVisible();
  const titleBox = await title.boundingBox();
  if (!titleBox) throw new Error('My Library title has no bounds');
  // The bug squeezed the title to a sliver (no usable width) that wrapped a letter per line.
  expect(titleBox.width).toBeGreaterThan(80);
  expect(titleBox.height).toBeLessThan(60);
  expect(titleBox.y).toBeLessThan(screenHeight * 0.2);
  await app.screenshot('a11y-layout-library-header');

  for (const id of ['favoritesTab', 'libraryTab', 'shelvesTab']) {
    const tab = screen.getByTestId(id);
    await expect(tab).toBeVisible();
    const box = await tab.boundingBox();
    if (!box) throw new Error(`${id} has no bounds`);
    expect(box.height).toBeGreaterThan(20);
    expect(box.height).toBeLessThan(90);
    expect(box.y).toBeLessThan(screenHeight * 0.3);
  }

  // Each header button is tappable and opens its screen.
  await screen.getByTestId('momentSearchButton').tap();
  await expect(screen.getByTestId('momentSearch.recent')).toBeVisible();
  await app.screenshot('a11y-layout-moment-search');
  // The search field takes focus on appear, so the first tap can land while the keyboard animates.
  for (let attempt = 0; attempt < 3 && !(await screen.getByTestId('plusButton').isVisible()); attempt += 1) {
    await dismiss(screen);
  }
  await expect(screen.getByTestId('plusButton')).toBeVisible();

  await screen.getByTestId('plusButton').tap();
  await expect(screen.getByText('Unpaged Plus').first()).toBeVisible();
  await app.screenshot('a11y-layout-plus');
  await dismiss(screen);

  await screen.getByTestId('settingsButton').tap();
  await expect(dismissButton(screen)).toBeVisible();
  await app.screenshot('a11y-layout-settings');
  await dismiss(screen);

  await screen.getByTestId('importButton').tap();
  await expect(screen.getByText('Import Audiobook').first()).toBeVisible();
  await app.screenshot('a11y-layout-import');
  await screen.getByRole('button', 'Cancel').tap();
  await expect(title).toBeVisible();

  // Shelves: the "Collections" heading stays on one line.
  await device.openApp(bundle, { relaunch: true, launchArguments: shelvesFixture });
  const heading = screen.getByText('Collections', { exact: true }).first();
  await expect(heading).toBeVisible();
  const headingBox = await heading.boundingBox();
  if (!headingBox) throw new Error('Collections heading has no bounds');
  expect(headingBox.height).toBeLessThan(45);
  expect(headingBox.width).toBeGreaterThan(headingBox.height * 2);
  await app.screenshot('a11y-layout-shelves');
});

// The iCloud chrome added with free sync and audio in iCloud: the Settings section and page, the
// book's audio card, Cloud Library's Download row and the onboarding toggle.
const iCloudFixture = ['-e2e-fixture', '-e2e-reset-fixture', '-onboardingComplete', 'YES', '-startOnFreeBooks', 'NO',
  '-e2e-icloud-account', '-iCloudSyncEnabled', 'YES', '-e2e-icloud-drive', '-e2e-cloud-audio'];

/** A label squeezed by fixed-size neighbours wraps a letter per line: narrow and very tall. */
async function expectReadable(screen: Screen, text: string | RegExp): Promise<void> {
  const label = screen.getByText(text).first();
  await expect(label).toBeVisible();
  const box = await label.boundingBox();
  if (!box) throw new Error(`${text} has no bounds`);
  expect(box.width).toBeGreaterThan(80);
  expect(box.width).toBeGreaterThan(box.height);
}

test('large text with Button Shapes and Bold Text keeps the iCloud screens readable', async ({ device, screen, app }) => {
  setAccessibility(true);
  await device.openApp(bundle, { relaunch: true, launchArguments: iCloudFixture });

  await screen.getByTestId('settingsButton').tap();
  await screen.scrollUntilVisible(screen.getByTestId('settings.icloud'));
  await expectReadable(screen, 'iCloud Sync');
  await app.screenshot('a11y-layout-settings-icloud-section');
  await tapVisibleCenter(screen.getByTestId('settings.icloud'));
  await screen.scrollUntilVisible(screen.getByTestId('icloud.audioToggle'));
  await expectReadable(screen, 'Store audio in iCloud');
  await expect(screen.getByTestId('icloud.audioToggle').getByRole('switch').last()).toBeEnabled();
  await app.screenshot('a11y-layout-icloud-settings');
  await tapVisibleCenter(screen.getByRole('button', 'Settings'));

  await screen.scrollUntilVisible(screen.getByTestId('settings.cloudLibrary'));
  await tapVisibleCenter(screen.getByTestId('settings.cloudLibrary'));
  const download = screen.getByTestId('cloudLibrary.download.E2E-Cloud-Book');
  await screen.scrollUntilVisible(download);
  await expectReadable(screen, 'E2E Cloud Book');
  await expect(screen.getByRole('button', 'Locate…').first()).toBeVisible();
  await app.screenshot('a11y-layout-cloud-library');
  await dismiss(screen);

  await screen.getByTestId('book.card.E2E-Listening-Book').tap();
  await screen.scrollUntilVisible(screen.getByTestId('book.cloudAudio.store'));
  await expectReadable(screen, 'Audio in iCloud');
  await app.screenshot('a11y-layout-book-cloud-audio');

  await device.openApp(bundle, {
    relaunch: true,
    launchArguments: ['-e2e-fixture', '-e2e-reset-fixture', '-onboardingComplete', 'NO', '-startOnFreeBooks', 'NO', '-e2e-icloud-account'],
  });
  await screen.getByTestId('onboarding.choice.own').tap();
  await screen.getByTestId('onboarding.page.5').tap();
  const toggle = screen.getByTestId('onboarding.icloud.toggle').getByRole('switch').last();
  await screen.scrollUntilVisible(toggle);
  await expect(toggle).toBeEnabled();
  await expectReadable(screen, /Sync with iCloud · Free/);
  await app.screenshot('a11y-layout-onboarding-icloud');
});
