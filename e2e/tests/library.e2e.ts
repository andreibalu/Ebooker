import { expect, type Screen } from 'e2e';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { test, tapVisibleCenter } from './native-actions.js';
import { appDataPath, bundle, terminate, waitUntilRunning } from '../support/simulator.js';

const fixture = ['-e2e-fixture', '-onboardingComplete', 'YES', '-startOnFreeBooks', 'NO', '-shelvesSource', 'librivox'];
const listeningFolder = () => join(appDataPath(), 'Library', 'Application Support', 'Audiobooks', 'E2E-Listening-Book');

function shortDate(date: Date): string {
  return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
}

async function seedActivity(screen: Screen, days: 7 | 30 | 113): Promise<void> {
  await screen.getByTestId('settingsButton').tap();
  const seed = screen.getByRole('button', `Seed Reading Activity · ${days} days`);
  await screen.scrollUntilVisible(seed);
  await tapVisibleCenter(seed);
  await tapVisibleCenter(screen.getByRole('button', 'Done'));
}

test('reading stats switch between 7-day, 30-day and 4-month ranges as history grows', {
  timeout: 300_000,
}, async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: [...fixture, '-e2e-reset-fixture'] });
  const today = new Date();
  const daysAgo = (n: number) => new Date(today.getFullYear(), today.getMonth(), today.getDate() - n);
  const ranges = [
    { days: 7, card: 'Last 7 days', eyebrow: /^READING · LAST 7 DAYS$/, from: shortDate(daysAgo(6)) },
    { days: 30, card: 'Last 30 days', eyebrow: /^READING · LAST 30 DAYS$/, from: shortDate(daysAgo(29)) },
    // Four months starts at the first recorded day rather than a fixed offset.
    { days: 113, card: 'Last 4 months', eyebrow: /^READING · LAST 4 MONTHS$/, from: undefined },
  ] as const;
  const to = today.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });

  for (const range of ranges) {
    await seedActivity(screen, range.days);
    await expect(screen.getByTestId('readingActivity')).toContainText(range.card);
    await screen.getByTestId('readingActivity').tap();
    await expect(screen.getByText(range.eyebrow).first()).toBeVisible();
    const span = range.from ? `${range.from} — ${to}` : new RegExp(` — ${to}$`);
    await expect(screen.getByText(span).first()).toBeVisible();
    // The stats view's back button is also called "Library"; the tab behind it comes first.
    await tapVisibleCenter(screen.getByRole('button', 'Library').last());
    await expect(screen.getByTestId('readingActivity')).toBeVisible();
  }
});

test('Privacy Policy and Terms of Use open in Safari', async ({ device, screen }) => {
  for (const link of ['Privacy Policy', 'Terms of Use']) {
    terminate('com.apple.mobilesafari');
    await device.openApp(bundle, { relaunch: true, launchArguments: [...fixture, '-e2e-reset-fixture'] });
    await screen.getByTestId('settingsButton').tap();
    await screen.scrollUntilVisible(screen.getByText(link).first());
    await tapVisibleCenter(screen.getByText(link).first());
    expect(await waitUntilRunning('com.apple.mobilesafari')).toBe(true);
  }
  terminate('com.apple.mobilesafari');
});

test('each tab keeps its own sort order, across relaunch', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: [...fixture, '-e2e-reset-fixture'] });
  // Both fixture books in Favorites so both tabs list the same two books.
  await screen.getByTestId('libraryTab').tap();
  await screen.getByTestId('book.favorite.E2E-Another-Book').tap();
  const cards = screen.getByRole('button', /E2E (Another Book|The Listening Book),/);

  // Library: Title (Another first). Favorites: Duration (the longer Listening Book first).
  await screen.getByTestId('libraryTab').tap();
  await screen.getByRole('button', 'Title').tap();
  await expect(cards.first()).toContainText('E2E Another Book');
  await screen.getByTestId('favoritesTab').tap();
  await screen.getByTestId('favoritesTab').tap();
  await screen.getByRole('button', 'Duration').tap();
  await expect(cards.first()).toContainText('E2E The Listening Book');
  await screen.getByTestId('libraryTab').tap();
  await expect(cards.first()).toContainText('E2E Another Book');

  await device.openApp(bundle, { relaunch: true, launchArguments: fixture });
  await expect(cards.first()).toContainText('E2E The Listening Book');
  await screen.getByTestId('libraryTab').tap();
  await expect(cards.first()).toContainText('E2E Another Book');
});

test('"Remove from App" drops the book but keeps its audio files; "Also Delete Files" removes them', async ({ device, screen }) => {
  await device.openApp(bundle, { relaunch: true, launchArguments: [...fixture, '-e2e-reset-fixture'] });
  expect(existsSync(listeningFolder())).toBe(true);
  await screen.getByTestId('book.card.E2E-Listening-Book').longPress();
  await screen.getByRole('button', 'Delete').tap();
  await screen.getByRole('button', 'Remove from App').tap();
  await expect(screen.getByTestId('book.card.E2E-Listening-Book')).toBeHidden();
  expect(existsSync(listeningFolder())).toBe(true);
  await device.openApp(bundle, { relaunch: true, launchArguments: fixture });
  await screen.getByTestId('libraryTab').tap();
  await expect(screen.getByTestId('book.card.E2E-Listening-Book')).toBeHidden();

  await device.openApp(bundle, { relaunch: true, launchArguments: [...fixture, '-e2e-reset-fixture'] });
  await screen.getByTestId('book.card.E2E-Listening-Book').longPress();
  await screen.getByRole('button', 'Delete').tap();
  await screen.getByRole('button', 'Also Delete Files').tap();
  await expect(screen.getByTestId('book.card.E2E-Listening-Book')).toBeHidden();
  expect(existsSync(listeningFolder())).toBe(false);
});
