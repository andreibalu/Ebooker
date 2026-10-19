// English concept site. Product facts come from AGENTS.md and the shipping app; prices come from StoreKit.
// The moment anatomy is an illustrative walkthrough of the real pipeline (window, transcription, field
// order, closed label sets, verbatim quote check). Its generated values are an example, not a captured result.
export const site = {
  name: 'Unpaged',
  // Interface strings used by the layout and the anatomy stage.
  ui: {
    skip: 'Skip to content',
    home: 'Unpaged home',
    primaryNav: 'Primary',
    nav: ['Library', 'Moments', 'Listening', 'Plus'],
    getApp: 'Get the app',
    badgeAlt: 'Download on the App Store',
    legalNav: 'Legal',
    support: 'Support',
    privacy: 'Privacy',
    terms: 'Terms',
    language: 'Language',
    reduceMotion: 'Reduce motion',
    ogAlt: 'Unpaged: listen to the book, keep the moments.',
    iconAlt: 'The Unpaged app icon: a cream bookmark with an amber dot on deep navy.',
    tabsLabel: 'Ways to fill your library',
    stageLabel: 'Illustration: a moment being written, step by step',
    stepsLabel: 'Choose a step',
    step: 'Step',
    of: 'of',
    savedAt: 'Saved at',
    transcript: 'Transcript',
    cardLabel: 'The finished moment',
    newMoment: 'New moment',
    fields: { name: 'Name', categories: 'Categories', categoriesHint: 'pick 1–3 of 10', mood: 'Mood', moodHint: 'pick 1 of 8', characters: 'Characters', quote: 'Quote', verified: 'Found word for word', note: 'Note' },
    freePlan: 'Free, for good',
    plusPlan: 'Everything free, and',
    plusIncludes: 'What Plus includes',
    back: 'Back to Unpaged'
  },
  url: 'https://andreibalu.github.io/Ebooker',
  appStore: 'https://apps.apple.com/app/id6761081641',
  title: 'Unpaged · Listen to the book. Keep the moments.',
  description: 'An audiobook player for iPhone. Play your own audiobooks, 20,000+ free LibriVox classics and your Audiobookshelf library, and keep the passages that stay with you.',
  hero: {
    eyebrow: 'Audiobook player for iPhone',
    lines: ['Listen to the book.', 'Keep the <em>moments.</em>'],
    text: 'Unpaged plays your own audiobooks, more than 20,000 free classics and your Audiobookshelf library. Save the passages that stay with you, and let Apple Intelligence name them, right on your iPhone.',
    secondary: 'See a moment being made',
    facts: ['Free to listen', 'iOS 18 and later', 'No account, no ads, no tracking'],
    alt: 'The Unpaged library with Pride and Prejudice, Notes from the Underground, The Odyssey and Meditations, each with its listening progress.',
    chip: { title: 'A Truth Universally Acknowledged', time: '00:42', book: 'Pride and Prejudice' }
  },
  sources: {
    eyebrow: 'Your library',
    heading: 'Three ways in.<br><em>One shelf.</em>',
    items: [
      { name: 'Your books', title: 'Already yours. Right at home.', text: 'Import DRM-free audiobooks from Files. Unpaged keeps the chapters, cover art and your exact place together in one personal library.', details: ['MP3, M4B, M4A and AAC', 'Embedded chapters, read straight from the file', 'Offline by default'], screen: 'library', alt: 'The Unpaged library tab with four audiobooks, their covers, lengths and progress bars.' },
      { name: 'Free classics', title: 'Twenty thousand first chapters.', text: 'Browse the LibriVox catalog of public-domain audiobooks. Hear a 20-second sample, compare other recordings of the same book, then stream it or download it.', details: ['A new classic picked every day', 'Curated collections and filters for language, genre and length', 'Downloads continue in the background'], screen: 'librivox', alt: 'The Unpaged Shelves tab: today’s pick, curated collections and a numbered list of popular classics.' },
      { name: 'Audiobookshelf', title: 'Your server, in your pocket.', text: 'Connect your own Audiobookshelf server over your home network or VPN. Browse series, collections, authors and narrators, and keep your place in step with the server.', details: ['Stream, or download for the road', 'Listening progress syncs both ways', 'Works over Tailscale and plain LAN'], screen: 'abs', alt: 'Unpaged connected to an Audiobookshelf server, showing Continue Listening and the full library.' }
    ]
  },
  moments: {
    eyebrow: 'Moments',
    heading: 'Some passages deserve<br>a <em>bookmark.</em>',
    text: 'Tap Save Moment and Unpaged marks the exact second, stepping back as far as you choose so you catch the start of the line. Name it, add a note, and come back to it whenever you like.',
    points: [
      ['Search every moment', 'One search across every book, by name, note, quote or title, even for books no longer on this iPhone.'],
      ['Back to the second', 'Tap a moment on the book page or in search, and playback jumps straight to it.'],
      ['Yours to keep', 'With iCloud sync, moments follow your library to your other devices.']
    ],
    alt: 'Four saved moments in Pride and Prejudice, each with a name, a timestamp and a short note.'
  },
  anatomy: {
    eyebrow: 'Anatomy of a moment',
    heading: 'How a moment<br><em>writes itself.</em>',
    text: 'With Unpaged Plus, Apple Intelligence can fill in a moment for you. Here is what happens when you tap Save Moment in a downloaded book. All of it runs on your iPhone. The audio and the words never leave it.',
    book: 'Pride and Prejudice',
    author: 'Jane Austen',
    chapter: 'Chapter 1',
    saved: '01:40',
    // Transcript tokens. Plain strings are text; arrays are [text, key, target?].
    // key ⇒ which step lights it; target ⇒ the field or label it feeds.
    transcript: [
      'It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.',
      [' However little known the feelings or views of such a man may be on his first entering a neighbourhood, this truth is so well fixed in the minds of the surrounding families, that he is considered as the rightful property of some one or other of their daughters.', 'skip'], ' ',
      ['“My dear', 'cat', 'chip-characterIntro'], ' ', ['Mr. Bennet,”', 'who', 'who-mr'], ' ', ['said his lady', 'cat', 'chip-dialogue'], ' to him one day, “have you heard that ', ['Netherfield Park is let', 'name', 'f-name'], ' at last?” ',
      ['Mr. Bennet', 'who', 'who-mr'], ' replied that he had not. “But it is,” returned she; “for ', ['Mrs. Long', 'who', 'who-long'], ' has just been here, and she told me all about it.” ',
      ['Mr. Bennet made no answer.', 'cat', 'chip-humor'], ' “Do you not want to know ', ['who has taken it?', 'name', 'f-name'], '” cried ', ['his wife', 'who', 'who-mrs'], ' ', ['impatiently.', 'mood', 'mood-funny'], ' ',
      ['“You want to tell me, and I have no objection to hearing it.”', 'quote', 'f-quote'], ' This was invitation enough.'
    ],
    result: {
      name: 'Netherfield Park Is Let',
      categories: [['dialogue', 'Dialogue'], ['action', 'Action'], ['plotTwist', 'Plot Twist'], ['characterIntro', 'Character Intro'], ['worldBuilding', 'World Building'], ['quote', 'Quote'], ['reflection', 'Reflection'], ['humor', 'Humor'], ['tension', 'Tension'], ['romance', 'Romance']],
      picked: ['dialogue', 'characterIntro', 'humor'],
      moods: [['tense', 'Tense'], ['funny', 'Funny'], ['sad', 'Sad'], ['romantic', 'Romantic'], ['inspirational', 'Inspirational'], ['mysterious', 'Mysterious'], ['peaceful', 'Peaceful'], ['dramatic', 'Dramatic']],
      mood: 'funny',
      characters: [['who-mr', 'Mr. Bennet'], ['who-mrs', 'Mrs. Bennet'], ['who-long', 'Mrs. Long']],
      quote: 'You want to tell me, and I have no objection to hearing it.',
      note: 'Mrs. Bennet rushes to share the news that Netherfield Park has a new tenant. Mr. Bennet’s dry replies set up the comedy of the marriage plot.'
    },
    steps: [
      { k: 'listen', label: 'Listen back', title: 'It hears what you just heard.', text: 'Unpaged takes the 75 seconds behind the playhead and 15 ahead. The moment is what you just heard, without spoiling what comes next.' },
      { k: 'transcribe', label: 'Transcribe', title: 'The words, on device.', text: 'Apple’s speech model reads that stretch of the audio file directly, punctuation included. Recognition is required to happen on device, so nothing is uploaded.' },
      { k: 'name', label: 'Name', title: 'A title from the turning point.', text: 'The on-device model writes a three-to-five word title around the event the passage turns on. Short fields come first, so a long passage can only ever trim the last one.' },
      { k: 'cat', label: 'Categories & mood', title: 'Labels from a closed list.', text: 'Categories and mood aren’t free text. The model picks one to three of ten categories and one of eight moods, so every label is one you can filter by.' },
      { k: 'who', label: 'Characters', title: 'Who is in the scene.', text: 'Up to six names, speaking or mentioned. “His wife” becomes Mrs. Bennet because the passage makes it plain.' },
      { k: 'quote', label: 'Quote', title: 'A quote it cannot make up.', text: 'The quote has to be copied word for word. Unpaged then checks it against the transcript, ignoring case and punctuation. A near miss snaps to the real sentence, and an invented line is dropped.' },
      { k: 'note', label: 'Note', title: 'Then a note, and it’s yours.', text: 'Two short sentences on what is happening and why it matters, written last. Edit anything before you save.' }
    ],
    caption: 'An illustrative example. Real results depend on the passage and the device. Excerpt from Pride and Prejudice by Jane Austen, in the public domain.',
    requires: 'Smart naming needs Unpaged Plus, iOS 26 or later and Apple Intelligence. Without it, moments still save with the exact time, and you can name them yourself.'
  },
  habits: {
    eyebrow: 'Listening',
    heading: 'A chapter&nbsp;here.<br>A habit, <em>eventually.</em>',
    text: 'The walk. The dishes. The last half hour of the day. Unpaged keeps a quiet record of the time you spend with books, and helps you back in when life gets in the way.',
    items: [
      { title: 'See it add up', text: 'A heatmap of every listening day, streaks, your best day and hour, and the authors you keep returning to.', screen: 'stats', alt: 'Unpaged reading statistics: a four-month amber heatmap and 92 hours of listening across 180 sessions.' },
      { title: 'Where was I?', text: 'After three days away, a welcome-back recap sums up where you left the story, just above Continue.', tag: 'Plus', screen: 'recap', alt: 'The Frankenstein book page with a Where Was I recap above the saved moments.' }
    ]
  },
  playback: {
    eyebrow: 'The player',
    heading: 'Made for the way<br>you <em>listen.</em>',
    text: 'The small controls that make one more chapter possible.',
    items: [
      ['Chapter by chapter', 'Embedded chapters from M4B, M4A and MP3 files, or the chapters your Audiobookshelf server knows. The player, the chapter list and CarPlay all agree.', 'chapters'],
      ['A proper stopping point', 'Sleep in fifteen minutes, or at the end of this chapter. Pausing keeps the timer armed.', 'moon'],
      ['The voice, just right', 'A five-band equalizer with Voice Boost, remembered for each book.', 'eq'],
      ['Pick up anywhere', 'Continue Listening widgets, a Siri shortcut and CarPlay put your book one tap away.', 'devices']
    ],
    alts: ['The Unpaged player on chapter 12 of Pride and Prejudice, with speed, equalizer, sleep timer and Save Moment.', 'The per-book equalizer with Voice Boost selected and five manual bands.']
  },
  plus: {
    eyebrow: 'Free to listen',
    heading: 'Your library is personal.<br>So is the <em>intelligence.</em>',
    text: 'No ads, no tracking, no account to create. The player and iCloud sync are free, for good. Unpaged Plus adds the Apple Intelligence features, and the AI runs on your iPhone.',
    link: 'Meet Unpaged Plus',
    free: ['Your own audiobook files', 'LibriVox classics and Audiobookshelf', 'Moments, search and listening stats', 'Chapters, sleep timer and equalizer', 'CarPlay, Siri and widgets', 'iCloud sync, with your audio if you like'],
    paid: ['Smart moment naming', 'Welcome-back recaps', 'Future Plus features'],
    note: 'AI features need iOS 26 or later and Apple Intelligence. iCloud sync is free with an iCloud account and can keep your own books’ audio too. Plans and any trial are shown in the app.'
  },
  close: { eyebrow: 'Good books go with you', title: 'Make room for<br>another <em>chapter.</em>', text: 'Free on the App Store, for iPhone with iOS 18 or later.' },
  footer: { credit: 'Made by Andrei Baluta.', links: [['Support', 'support'], ['Privacy', 'privacy'], ['Terms', 'terms']] },
  plusPage: {
    title: 'Unpaged Plus · Keep the place. Keep the moments.',
    description: 'Unpaged Plus adds smart moment naming and welcome-back recaps to your audiobook library, with Apple Intelligence on your iPhone. See what is included and which devices support it.',
    eyebrow: 'Unpaged Plus',
    heading: 'Keep the place.<br>Keep the <em>moments.</em>',
    intro: 'Plus helps you remember the story, with Apple Intelligence running on your iPhone. iCloud sync stays free for everyone.',
    details: [
      ['sparkles', 'Names for the moments you keep', 'Smart naming reads the passage around your bookmark on device and suggests a title, a note, categories, a mood, the characters, and a quote checked word for word against the transcript. You can edit all of it.'],
      ['recap', 'A reminder after time away', 'Come back after three days or more and the book page opens with a short recap of where you left the story. Dismiss it once and it stays dismissed until you listen again.'],
      ['cloud', 'iCloud sync, free for everyone', 'Without Plus too, iCloud sync backs up your library, listening progress, moments, equalizer settings and reading activity. Keep your own books’ audio in iCloud as well, and another iPhone downloads the whole book.'],
      ['plans', 'Choose the plan in the app', 'Monthly and yearly plans through the App Store. Current prices and any trial are shown before you subscribe. Earlier AI and iCloud purchases are still recognized.']
    ],
    qualification: 'Apple Intelligence features require iOS 26 or later on a supported iPhone with Apple Intelligence turned on. Smart naming and recaps work on books stored on your iPhone, not while streaming. The player runs on iOS 18 and later. iCloud sync is free and requires iCloud sign-in.'
  },
  notFound: { title: 'Lost your place? · Unpaged', heading: 'Lost your <em>place?</em>', text: 'This page isn’t in the book. Your next chapter starts back at the beginning.', cta: 'Back to Unpaged' }
};
