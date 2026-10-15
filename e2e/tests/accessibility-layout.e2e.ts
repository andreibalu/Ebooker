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
