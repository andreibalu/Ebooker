import { expect } from 'e2e';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { test } from './native-actions.js';
import { bundle, iosMajorVersion } from '../support/simulator.js';

const fixture = ['-e2e-fixture', '-onboardingComplete', 'YES', '-startOnFreeBooks', 'NO',
  '-shelvesSource', 'librivox', '-e2e-fake-recap', 'The traveller reached the harbour.',
  '-resumeBacktrackSeconds', '0'];

for (const scenario of ['five days', 'resume', 'dismissal persists', 'today', 'setting off', 'cached recap',
  'cached recap within tolerance']) {
  test(`welcome-back recap: ${scenario}`, async ({ app, device, screen }) => {
    const args = [...fixture, '-e2e-welcome-days', scenario === 'today' ? '0' : '5'];
    if (scenario === 'setting off') args.push('-welcomeBackRecaps', 'NO');
    if (scenario.startsWith('cached recap')) args.push('-e2e-persisted-recap', 'A cached harbour recap.');
    // Saved progress (200s) is 30s past this anchor, inside the 60-second tolerance.
    if (scenario === 'cached recap within tolerance') args.push('-e2e-persisted-recap-anchor', '170');
    await device.openApp(bundle, { relaunch: true, launchArguments: [...args, '-e2e-reset-fixture'] });
    await screen.getByTestId('book.card.E2E-Listening-Book').tap();
    // Recaps need FoundationModels (iOS 26): older runtimes show no card and never call the provider.
    if (scenario === 'today' || scenario === 'setting off' || iosMajorVersion() < 26) {
      await expect(screen.getByTestId('welcomeBack.card')).toBeHidden();
      await expect(screen.getByTestId('welcomeBack.providerCalls')).toHaveText('0');
      await app.screenshot(`welcome-back-${scenario.replaceAll(' ', '-')}`);
      return;
    }
    await expect(screen.getByTestId('welcomeBack.text')).toHaveText(
      scenario.startsWith('cached recap') ? 'A cached harbour recap.' : 'The traveller reached the harbour.');
    await expect(screen.getByTestId('welcomeBack.elapsed')).toHaveText('You last listened 5 days ago');
    await expect(screen.getByTestId('welcomeBack.providerCalls')).toHaveText(scenario.startsWith('cached recap') ? '0' : '1');
    await app.screenshot(`welcome-back-${scenario.replaceAll(' ', '-')}`);
    if (scenario === 'resume') {
      await screen.getByTestId('welcomeBack.resume').tap();
      await expect(screen.getByTestId('player.playPause')).toHaveAccessibleName('Pause playback');
      await expect(screen.getByTestId('player.scrubber')).toHaveValue(/^03:[0-5]\d of 05:00$/);
      await app.screenshot('welcome-back-resumed-position');
    }
    if (scenario === 'cached recap within tolerance') {
      // Opening the detail must not have discarded the saved recap: a relaunch reuses it.
      await device.openApp(bundle, { relaunch: true, launchArguments: args });
      await screen.getByTestId('book.card.E2E-Listening-Book').tap();
      await expect(screen.getByTestId('welcomeBack.text')).toHaveText('A cached harbour recap.');
      await expect(screen.getByTestId('welcomeBack.providerCalls')).toHaveText('0');
      await app.screenshot('welcome-back-cached-after-relaunch');
    }
    if (scenario === 'dismissal persists') {
      await screen.getByTestId('welcomeBack.notNow').tap();
      await expect(screen.getByTestId('welcomeBack.card')).toBeHidden();
      await device.openApp(bundle, { relaunch: true, launchArguments: args });
      await screen.getByTestId('book.card.E2E-Listening-Book').tap();
      await expect(screen.getByTestId('welcomeBack.card')).toBeHidden();
      await expect(screen.getByTestId('welcomeBack.providerCalls')).toHaveText('0');
      await app.screenshot('welcome-back-dismissed-after-relaunch');
    }
  });
}

// Opt in: needs Apple Intelligence on the host Mac (simulators use its model). Passages come from
// E2E_AI_CORPUS (a JSON array of {id, book, recap}) filtered by E2E_AI_IDS, or one built-in
// passage. E2E_AI_RESULTS receives each headline and recap the real model wrote.
test('welcome-back recap: the on-device model recaps fiction passages', {
  timeout: 1_800_000,
  skip: process.env.E2E_REAL_MODEL === '1' ? false : 'Set E2E_REAL_MODEL=1 to exercise the on-device model',
}, async ({ app, device, screen }) => {
  expect(iosMajorVersion(), 'the on-device model needs iOS 26 or later').toBeGreaterThanOrEqual(26);
  type Passage = { id: string; book: string; recap: string };
  const ids = (process.env.E2E_AI_IDS ?? '').split(',').filter(Boolean);
  const corpus: Passage[] = process.env.E2E_AI_CORPUS
    ? (JSON.parse(readFileSync(process.env.E2E_AI_CORPUS, 'utf8')) as Passage[]).filter((p) => !ids.length || ids.includes(p.id))
    : [{ id: 'harbour', book: 'Fixture', recap: 'The storm broke over the harbour at midnight, and nobody in the town slept. '
      + 'Ariadne climbed the lighthouse stairs with the lantern. "They will see it now," she told her brother Tomas, '
      + 'who had followed her up in the dark. Far out, a ship turned toward the light.' }];
  // The app reads transcript files straight from the host; keep them outside the repo.
  const dir = '/private/tmp/unpaged-e2e-recap';
  mkdirSync(dir, { recursive: true });
  const results: { id: string; headline: string; recap: string }[] = [];
  for (const passage of corpus) {
    const file = `${dir}/${passage.id}.txt`;
    writeFileSync(file, passage.recap);
    // A reset per passage, so the previous passage's stored recap is never reused.
    await device.openApp(bundle, { relaunch: true, launchArguments: ['-e2e-fixture', '-onboardingComplete', 'YES',
      '-startOnFreeBooks', 'NO', '-shelvesSource', 'librivox', '-resumeBacktrackSeconds', '0',
      '-e2e-welcome-days', '5', '-e2e-transcript-file', file, '-e2e-reset-fixture'] });
    await screen.getByTestId('book.card.E2E-Listening-Book').tap();
    await expect(screen.getByTestId('welcomeBack.text')).toBeVisible({ timeout: 60_000 });
    const headline = (await screen.getByTestId('welcomeBack.headline').textContent()) ?? '';
    const recap = (await screen.getByTestId('welcomeBack.text').textContent()) ?? '';
    results.push({ id: passage.id, headline, recap });
    if (results.length === 1) await app.screenshot('welcome-back-real-model');
  }
  if (process.env.E2E_AI_RESULTS) writeFileSync(process.env.E2E_AI_RESULTS, JSON.stringify(results, null, 1));
  for (const result of results) {
    expect(result.recap.length, `${result.id} recap`).toBeGreaterThan(20);
    expect(result.recap).not.toMatch(/^(I'm sorry|I cannot|I can't)/i);
    // Seen on the real model: a recap that echoed a transcript opening mid-sentence in lowercase.
    expect(result.recap, `${result.id} recap`).not.toMatch(/^\p{Ll}/u);
    expect(result.headline, `${result.id} headline`).not.toMatch(/\s(and|or|of|at|in|on|to|with|near|the|a)$/i);
  }
});
