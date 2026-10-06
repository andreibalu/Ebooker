import { expect } from 'e2e';
import { test, tapVisibleCenter, expandEqualizerSheet } from './native-actions.js';
import { setSystemAppearance } from '../support/simulator.js';

const bundle = 'andreibaludev.Pageless';
const args = ['-e2e-fixture', '-onboardingComplete', 'YES', '-startOnFreeBooks', 'NO', '-shelvesSource', 'librivox'];
const reset = [...args, '-e2e-reset-fixture'];

test('EQ preset enabled state persists and reset returns flat', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: reset });
  await screen.getByTestId('book.card.E2E-Listening-Book').tap();
  await screen.getByTestId('book.play').tap();
  await expect(screen.getByTestId('player.playPause')).toHaveAccessibleName('Pause playback');
  await screen.getByTestId('player.playPause').tap();
  await screen.getByTestId('player.equalizer').tap();
  await expandEqualizerSheet();
  await tapVisibleCenter(screen.getByTestId('equalizer.enabled').getByRole('switch').last());
  await expect(screen.getByTestId('equalizer.enabled').getByRole('switch').last()).toBeChecked();
  await screen.getByRole('button', 'Voice Boost').tap();
  await expect(screen.getByTestId('equalizer.preset.voiceBoost')).toBeSelected();
  await device.openApp(bundle, { relaunch: true, launchArguments: args });
  await screen.getByTestId('book.card.E2E-Listening-Book').tap();
  await screen.getByTestId('book.play').tap();
  await expect(screen.getByTestId('player.playPause')).toHaveAccessibleName('Pause playback');
  await screen.getByTestId('player.playPause').tap();
  await screen.getByTestId('player.equalizer').tap();
  await expandEqualizerSheet();
  await expect(screen.getByTestId('equalizer.enabled').getByRole('switch').last()).toBeChecked();
  await expect(screen.getByTestId('equalizer.preset.voiceBoost')).toBeSelected();
  await screen.scrollUntilVisible(screen.getByRole('button', 'Reset to Flat'));
  await screen.getByRole('button', 'Reset to Flat').tap();
  await expect(screen.getByTestId('equalizer.preset.flat')).toBeSelected();
});

test('moment category filters select and clear a real result subset', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: reset });
  await screen.getByTestId('book.card.E2E-Listening-Book').tap();
  await screen.getByText(/^\d+ moments?$/).first().tap();
  await screen.scrollUntilVisible(screen.getByLabel('Filter moments').first());
  await screen.getByLabel('Filter moments').first().tap();
  await screen.getByRole('button', 'Dialogue').tap();
  await screen.getByRole('button', 'Done').tap();
  await expect(screen.getByText('E2E First Moment').first()).toBeVisible();
  await expect(screen.getByText('E2E Second Moment').first()).toBeHidden();
  await screen.getByLabel('Filter moments').first().tap();
  await screen.getByRole('button', 'Clear All').tap();
  await screen.getByRole('button', 'Done').tap();
  await expect(screen.getByText('E2E Second Moment').first()).toBeVisible();
});

test('Appearance supports all system combinations and persists across relaunch', {
  timeout: 300_000,
}, async ({ app, device, screen }) => {
  try {
    await device.openApp(bundle, { relaunch: true, launchArguments: reset });
    await screen.getByTestId('settingsButton').tap();
    await screen.scrollUntilVisible(screen.getByTestId('settings.appearance.system'));
    await tapVisibleCenter(screen.getByTestId('settings.appearance.system'));
    for (const system of ['light', 'dark'] as const) {
      setSystemAppearance(system);
      for (const choice of ['dark', 'light', 'system'] as const) {
        const option = screen.getByTestId(`settings.appearance.${choice}`);
        await tapVisibleCenter(option);
        await expect(option).toBeSelected();
        await app.screenshot(`appearance-system-${system}-choice-${choice}`);
      }
    }
    await tapVisibleCenter(screen.getByTestId('settings.appearance.light'));
    await device.openApp(bundle, { relaunch: true, launchArguments: args });
    await screen.getByTestId('settingsButton').tap();
    await screen.scrollUntilVisible(screen.getByTestId('settings.appearance.light'));
    await expect(screen.getByTestId('settings.appearance.light')).toBeSelected();
    await tapVisibleCenter(screen.getByRole('button', 'Done'));
    await screen.getByTestId('plusButton').tap();
    await expect(screen.getByText('Unpaged Plus').first()).toBeVisible();
    await app.screenshot('appearance-light-plus-sheet-on-dark-system');
  } finally {
    setSystemAppearance('light');
  }
});

test('settings home tab preference survives relaunch', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: reset });
  await screen.getByTestId('settingsButton').tap();
  await screen.scrollUntilVisible(screen.getByTestId('settings.home.Shelves'));
  await tapVisibleCenter(screen.getByTestId('settings.home.Shelves')); 
  await device.openApp(bundle, { relaunch: true, launchArguments: ['-e2e-fixture', '-onboardingComplete', 'YES'] });
  await expect(screen.getByText('Offline — showing saved books.').first()).toBeVisible();
  await expect(screen.getByTestId('book.card.E2E-Listening-Book')).toBeHidden();
});

test('reset onboarding reopens the welcome flow', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: reset });
  await screen.getByTestId('settingsButton').tap();
  await screen.scrollUntilVisible(screen.getByRole('button', 'Reset').first());
  await tapVisibleCenter(screen.getByRole('button', 'Reset').first());
  await screen.getByRole('button', 'Reset').last().tap();
  await expect(screen.getByTestId('onboarding.choice.own')).toBeVisible();
});

test('coffee support surface is reachable without purchase', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: reset });
  await screen.getByTestId('settingsButton').tap();
  await screen.scrollUntilVisible(screen.getByText('Buy me a coffee').first());
  // The subtitle is part of the row button's label. The snapshot does not always list it as its own text.
  await expect(screen.getByRole('button', 'Buy me a coffee, Optional one-time support. No features attached.')).toBeVisible();
});

test('malformed Audiobookshelf server fails local validation without credentials', async ({ device, screen, nativeKeyboard }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: reset });
  await screen.getByTestId('shelvesTab').tap();
  await screen.getByTestId('shelvesTab').tap();
  await screen.getByRole('button', /Audiobookshelf/).tap();
  await screen.getByTestId('abs.connect.server').fill('https://');
  await screen.getByTestId('abs.connect.username').fill('e2e-invalid-input');
  await screen.getByTestId('abs.connect.username').press('Enter');
  await nativeKeyboard.typeFocusedDummyCredential();
  await expect(screen.getByRole('button', 'Connect')).toBeEnabled();
  await nativeKeyboard.submitFocused();
  await expect(screen.getByText(/That doesn't look like a server address/).first()).toBeVisible();
});

test('onboarding Shelves choice visits all scene rail targets and persists routing', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: ['-e2e-fixture', '-e2e-reset-fixture', '-onboardingComplete', 'NO'] });
  await screen.getByTestId('onboarding.choice.shelves').tap();
  await expect(screen.getByText('Two quick permissions.').first()).toBeVisible();
  const headings = ['', 'Two quick permissions.', 'Set up listening.', 'Imagine your year.', 'Moments, named for you.', 'Everything in sync.', "You're all set."];
  for (let page = 1; page < 7; page++) {
    await screen.getByTestId(`onboarding.page.${page}`).tap();
    await expect(screen.getByText(headings[page]!).first()).toBeVisible();
  }
  await screen.getByRole('button', 'Open Library').tap();
  await expect(screen.getByText('Offline — showing saved books.').first()).toBeVisible();
  await device.openApp(bundle, { relaunch: true, launchArguments: ['-e2e-fixture'] });
  await expect(screen.getByText('Offline — showing saved books.').first()).toBeVisible();
  await expect(screen.getByTestId('onboarding.choice.shelves')).toBeHidden();
});

test('import metadata review uses real file ingestion then imported book survives relaunch', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: [...reset, '-e2e-import'] });
  await screen.getByTestId('importButton').tap();
  await expect(screen.getByText('Import Audiobook').first()).toBeVisible();
  await screen.getByPlaceholder('Title').fill('E2E Imported Book');
  await screen.getByPlaceholder('Author').fill('E2E Imported Author');
  await screen.getByRole('button', 'Save').tap();
  await screen.getByTestId('libraryTab').tap();
  await expect(screen.getByText('E2E Imported Book').first()).toBeVisible();
  await device.openApp(bundle, { relaunch: true, launchArguments: args });
  await screen.getByTestId('libraryTab').tap();
  await screen.getByText('E2E Imported Book').first().tap();
  await screen.getByTestId('book.play').tap();
  await expect(screen.getByTestId('player.playPause')).toHaveAccessibleName('Pause playback');
});

test('library sorting reorders two books by title and survives relaunch', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: reset });
  await screen.getByTestId('libraryTab').tap();
  await screen.getByTestId('libraryTab').tap();
  await screen.getByRole('button', 'Duration').tap();
  const cards = screen.getByRole('button', /E2E (Another Book|The Listening Book),/);
  await expect(cards.first()).toContainText('E2E The Listening Book');
  await screen.getByTestId('libraryTab').tap();
  await screen.getByRole('button', 'Title').tap();
  await expect(cards.first()).toContainText('E2E Another Book');
  await device.openApp(bundle, { relaunch: true, launchArguments: args });
  await screen.getByTestId('libraryTab').tap();
  await expect(cards.first()).toContainText('E2E Another Book');
});

test('progress marker persists and resumes the marked chapter', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: reset });
  await screen.getByTestId('book.card.E2E-Listening-Book').tap();
  await screen.getByTestId('book.play').tap();
  await screen.getByTestId('player.next').tap();
  await screen.getByTestId('player.markProgress').tap();
  await screen.getByRole('button', 'Mark Progress').tap();
  await expect(screen.getByTestId('player.markProgress')).toContainText('Progress Marked!');
  await device.openApp(bundle, { relaunch: true, launchArguments: args });
  await screen.getByTestId('book.card.E2E-Listening-Book').tap();
  await screen.scrollUntilVisible(screen.getByTestId('book.playProgress'));
  await screen.getByTestId('book.playProgress').tap();
  await expect(screen.getByText('E2E Chapter 2').first()).toBeVisible();
});

test('privacy and terms links are exposed in native settings', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: reset });
  await screen.getByTestId('settingsButton').tap();
  await screen.scrollUntilVisible(screen.getByText('Privacy Policy').first());
  await expect(screen.getByText('Privacy Policy').first()).toBeVisible();
  await expect(screen.getByText('Terms of Use').first()).toBeVisible();
});
