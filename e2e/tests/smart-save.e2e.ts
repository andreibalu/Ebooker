import { expect, type Screen } from 'e2e';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { test, tapVisibleCenter } from './native-actions.js';
import { bundle } from '../support/simulator.js';

const fixture = ['-e2e-fixture', '-onboardingComplete', 'YES', '-startOnFreeBooks', 'NO', '-shelvesSource', 'librivox'];
// The app reads transcript files straight from the host; keep them outside the repo.
const transcriptDir = '/private/tmp/unpaged-e2e-smart-save';

function transcriptFile(name: string, text: string): string {
  mkdirSync(transcriptDir, { recursive: true });
  const path = `${transcriptDir}/${name}.txt`;
  writeFileSync(path, text);
  return path;
}

async function smartSave(screen: Screen, timeout = 30_000) {
  await screen.getByTestId('book.card.E2E-Listening-Book').tap();
  await screen.getByTestId('book.play').tap();
  await expect(screen.getByTestId('player.playPause')).toHaveAccessibleName('Pause playback');
  await screen.getByTestId('player.playPause').tap();
  await expect(screen.getByText('Smart Save Moment').first()).toBeVisible();
  await screen.getByTestId('player.saveMoment').tap();
  await expect(screen.getByTestId('moment.name')).toBeVisible({ timeout });
}

const letterPassage = 'Elizabeth turned the letter over twice before she opened it. Jane watched her from the window. '
  + '"It is from Mr. Darcy," Elizabeth said at last, and her voice was steady. Elizabeth read it slowly.';

// The owner's bug: about half of saves showed "AI detected content likely to be unsafe" over a
// "Saved Moment" name. A declined passage now opens with a usable name and a calm notice.
test('smart save: a declined passage still gets a name and a calm notice', async ({ app, device, screen }) => {
  const args = [...fixture, '-e2e-moment-analysis', 'declined',
    '-e2e-moment-transcript-file', transcriptFile('letter', letterPassage)];
  await device.openApp(bundle, { relaunch: true, launchArguments: [...args, '-e2e-reset-fixture'] });
  await smartSave(screen);
  await expect(screen.getByTestId('moment.name')).toHaveValue('Elizabeth in E2E Chapter 1');
  await expect(screen.getByTestId('moment.notice')).toContainText("Apple Intelligence couldn't summarize this passage");
  await expect(screen.getByText(/unsafe/).first()).toBeHidden();
  await expect(screen.getByRole('button', 'Remove Elizabeth')).toBeVisible();
  await app.screenshot('smart-save-declined-fallback');
  await expect(screen.getByTestId('moment.done').last()).toBeEnabled();
  await tapVisibleCenter(screen.getByTestId('moment.done').last());
  await expect(screen.getByTestId('moment.done')).toBeHidden();

  await device.openApp(bundle, { relaunch: true, launchArguments: fixture });
  await screen.getByTestId('book.card.E2E-Listening-Book').tap();
  await screen.getByText(/^\d+ moments?$/).first().tap();
  await screen.scrollUntilVisible(screen.getByText('Elizabeth in E2E Chapter 1').first());
  await expect(screen.getByText('Elizabeth in E2E Chapter 1').first()).toBeVisible();
});

// Opt in: needs Apple Intelligence on the host Mac (simulators use its model). Passages come from
// E2E_AI_CORPUS (a JSON array of {id, book, moment}) filtered by E2E_AI_IDS, or one built-in
// passage. E2E_AI_RESULTS receives each name the real model produced.
test('smart save: the on-device model names fiction passages', {
  timeout: 1_800_000,
  skip: process.env.E2E_REAL_MODEL === '1' ? false : 'Set E2E_REAL_MODEL=1 to exercise the on-device model',
}, async ({ app, device, screen }) => {
  type Passage = { id: string; book: string; moment: string };
  const ids = (process.env.E2E_AI_IDS ?? '').split(',').filter(Boolean);
  const corpus: Passage[] = process.env.E2E_AI_CORPUS
    ? (JSON.parse(readFileSync(process.env.E2E_AI_CORPUS, 'utf8')) as Passage[]).filter((p) => !ids.length || ids.includes(p.id))
    : [{ id: 'letter', book: 'Pride and Prejudice', moment: letterPassage }];
  const results: { id: string; name: string; notice: boolean }[] = [];
  let reset = true;
  for (const passage of corpus) {
    const args = [...fixture, '-e2e-moment-transcript-file', transcriptFile(passage.id, passage.moment)];
    await device.openApp(bundle, { relaunch: true, launchArguments: reset ? [...args, '-e2e-reset-fixture'] : args });
    reset = false;
    await smartSave(screen, 60_000);
    const name = await screen.getByTestId('moment.name').inputValue();
    const notice = await screen.getByTestId('moment.notice').count() > 0;
    results.push({ id: passage.id, name, notice });
    if (results.length === 1) await app.screenshot('smart-save-real-model');
    await screen.getByRole('button', 'Cancel').tap();
    await expect(screen.getByTestId('moment.name')).toBeHidden();
  }
  if (process.env.E2E_AI_RESULTS) writeFileSync(process.env.E2E_AI_RESULTS, JSON.stringify(results, null, 1));
  for (const result of results) {
    expect(result.notice, `${result.id} fell back: ${result.name}`).toBe(false);
    expect(result.name).not.toBe('Saved Moment');
  }
});
