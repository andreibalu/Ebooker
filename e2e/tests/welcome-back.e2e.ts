import { expect } from 'e2e';
import { test } from './native-actions.js';
import { bundle } from '../support/simulator.js';

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
    if (scenario === 'today' || scenario === 'setting off') {
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
