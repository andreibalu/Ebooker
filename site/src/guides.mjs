// Setup guides. English only, written against the shipping app (see docs/ios/audiobookshelf.md and support.md).
// The nav label and the home strip are translated; the guides themselves are English and carry lang="en"
// wherever they appear on a localized page.
//
// Block types in `sections[].body`: a string is a paragraph; { ul }, { ol } are lists; { note } is a callout.
// Inline: **bold** and `code`. Media files live in public/guides/.

export const guideNav = { en: 'Guides', de: 'Anleitungen', es: 'Guías', fr: 'Guides', it: 'Guide', 'pt-br': 'Guias' };

export const guideStrip = {
  en: { eyebrow: 'Guides', heading: 'Set it up<br>in <em>minutes.</em>', text: 'Two short, tested walk-throughs, each with a real screen recording.', all: 'All guides' },
  de: { eyebrow: 'Anleitungen', heading: 'In wenigen Minuten<br><em>eingerichtet.</em>', text: 'Zwei kurze, getestete Anleitungen, jeweils mit einer echten Bildschirmaufnahme. Die Anleitungen sind auf Englisch.', all: 'Alle Anleitungen' },
  es: { eyebrow: 'Guías', heading: 'Listo en<br><em>minutos.</em>', text: 'Dos guías breves y probadas, cada una con una grabación de pantalla real. Las guías están en inglés.', all: 'Todas las guías' },
  fr: { eyebrow: 'Guides', heading: 'Prêt en<br><em>quelques minutes.</em>', text: 'Deux guides courts et testés, chacun avec un vrai enregistrement d’écran. Les guides sont en anglais.', all: 'Tous les guides' },
  it: { eyebrow: 'Guide', heading: 'Pronto in<br><em>pochi minuti.</em>', text: 'Due guide brevi e verificate, ciascuna con una vera registrazione dello schermo. Le guide sono in inglese.', all: 'Tutte le guide' },
  'pt-br': { eyebrow: 'Guias', heading: 'Pronto em<br><em>poucos minutos.</em>', text: 'Dois guias curtos e testados, cada um com uma gravação de tela real. Os guias estão em inglês.', all: 'Todos os guias' }
};

export const guidesIndex = {
  title: 'Guides · Unpaged',
  description: 'Short, tested guides for Unpaged, the audiobook player for iPhone: connect an Audiobookshelf server, and play your own M4B and MP3 audiobooks.',
  eyebrow: 'Guides',
  heading: 'Set it up<br>in <em>minutes.</em>',
  text: 'Each guide was written from using the app, with a screen recording of the steps. They say plainly what Unpaged does not do.',
  read: 'Read the guide',
  back: 'Back to Unpaged'
};

export const guides = [
  {
    slug: 'audiobookshelf-iphone',
    title: 'Listen to your Audiobookshelf server on iPhone · Unpaged',
    description: 'Connect an Audiobookshelf server to Unpaged on iPhone: sign in with a password or API key, browse series and authors, sync progress, download for offline, and use plain-http LAN or Tailscale servers.',
    short: 'Listen to your Audiobookshelf server on iPhone',
    summary: 'Sign in or paste an API key, browse your shelves, keep your place in step with the server, and download books for the road.',
    eyebrow: 'Guide · Audiobookshelf',
    heading: 'Listen to your <em>Audiobookshelf</em> server on iPhone',
    intro: 'Unpaged is a free iPhone audiobook player with a built-in Audiobookshelf client. This guide connects it to your own server, then covers browsing, progress sync, offline downloads and the network setups that work. Limits are listed at the end.',
    tested: 'Written against Unpaged 1.5.1. The steps were run and recorded in the iOS Simulator (iOS 27) against a local test server with public-domain titles.',
    published: '2026-10-18',
    video: {
      src: 'guides/audiobookshelf-iphone.mp4',
      poster: 'guides/audiobookshelf-iphone-poster.webp',
      width: 402, height: 874,
      label: 'Screen recording: connecting Unpaged to an Audiobookshelf server, browsing the library, downloading a book and starting it.',
      caption: 'Connect, browse, download, play. Recorded in the iOS Simulator against a local test server, so the address is 127.0.0.1.'
    },
    sections: [
      {
        id: 'before', title: 'What you need',
        body: [
          { ul: [
            'An Audiobookshelf server your iPhone can reach, and either a username and password or an API key for it.',
            'Unpaged on an iPhone with iOS 18 or later. The player is free, and so is the Audiobookshelf source.',
            'At least one **book** library on the server. Podcast libraries are not shown.'
          ] }
        ]
      },
      {
        id: 'connect', title: 'Connect your server',
        body: [
          { ol: [
            'Open the **Shelves** tab and tap **Shelves** again to open the source menu, then choose **Audiobookshelf**. You can also go to **Settings → Audiobookshelf Server**.',
            'Type your server address, for example `https://abs.example.com`. A port is fine: `http://192.168.1.20:13378`.',
            'Pick **Sign in** and enter your username and password, or pick **API key** and paste a key. Create keys in Audiobookshelf under **Settings → API Keys**. A new key may need to be switched on there before it works.',
            'Tap **Connect**. Your books appear in Shelves.'
          ] },
          'Those are the two ways in: username and password, or an API key. Unpaged has no browser or single sign-on screen, so if you normally sign in to Audiobookshelf through OpenID, create an API key instead. The login is stored only in the iPhone Keychain, and **Settings → Audiobookshelf Server → Disconnect** removes it.'
        ],
        figure: { src: 'guides/audiobookshelf-connect.webp', alt: 'The Unpaged connect screen: server address, Sign in and API key tabs, username and password fields and a Connect button.', caption: 'The connect screen, with the Sign in and API key tabs.' }
      },
      {
        id: 'network', title: 'Home network, VPN and plain http',
        body: [
          'Both `https://` and plain `http://` addresses work. That is what makes a server at home usable without a certificate:',
          { ul: [
            '**On your home Wi-Fi**: use the server’s LAN address, such as `http://192.168.1.20:13378` or `http://nas.local:13378`. The first time, iOS asks to allow **Local Network** access. Say yes, or Unpaged cannot see the server.',
            '**Away from home with Tailscale or another VPN**: use the VPN address, such as `http://nas.your-tailnet.ts.net:13378` or `http://100.101.102.103:13378`. If it stops working, check the VPN is switched on.',
            '**Over the public internet**: use HTTPS, for instance behind a reverse proxy. If you enter a plain `http://` address for a public host, Unpaged warns you before sending anything, because your password and listening activity would travel unencrypted.'
          ] },
          'Private addresses (LAN, loopback, link-local, Tailscale and similar) connect over plain http without the warning.'
        ]
      },
      {
        id: 'browse', title: 'Browse your library',
        body: [
          'Shelves shows **Continue Listening**, **Recently Added** and the full library with search. If the server has several book libraries, tap the library name to switch.',
          { ul: [
            '**Series** lists books in reading order, including fractional book numbers such as 1.5.',
            '**Collections** follow the order saved on your server.',
            'Tap an **author** or **narrator** in a book’s details to see their books in the current library.',
            'A progress filter (All, Not started, In progress, Finished) works together with search.'
          ] },
          'Browsed screens are saved on the iPhone. If the server is unreachable you still see them, with an offline banner, but you cannot add, stream or download until it is back.'
        ],
        figure: { src: 'guides/audiobookshelf-browse.webp', alt: 'Unpaged Shelves connected to an Audiobookshelf server, showing Continue Listening and the library.', caption: 'Shelves with Continue Listening and the full library.' }
      },
      {
        id: 'play', title: 'Play, chapters and your place',
        body: [
          'Tap **Play** on a book (it says **Resume** once you have started it). Unpaged adds it to your Library as a streaming book and starts playing, using the chapters your server knows. The player, chapter list and CarPlay show the same chapters.',
          'Unpaged sends your position back to the server when you pause, leave the app or finish a book, so other Audiobookshelf apps pick up where you stopped. If you are offline, the latest position waits on the iPhone and is sent when the connection returns.',
          'Before resuming, Unpaged asks the server whether a newer position exists, with a short timeout. If you listened on another device after your last play here, it continues from there. If the check fails, it simply resumes from the position it has.'
        ]
      },
      {
        id: 'offline', title: 'Download for offline listening',
        body: [
          'Choose **Download** on a book in Shelves or in its Library details. Progress is shown, and you can cancel or retry, including after the app was relaunched. Downloads continue while Unpaged is in the background.',
          { ul: [
            'A downloaded book plays with no connection, and keeps its progress, moments and equalizer.',
            '**Remove Download** deletes the audio from the iPhone and returns the book to streaming. **Remove from Library** drops it from Unpaged. Neither touches your server.',
            '**Settings → Audiobookshelf Server** shows how much space downloads use and offers **Remove All Downloads**. Disconnecting asks whether to keep the downloaded audio.'
          ] }
        ],
        figure: { src: 'guides/audiobookshelf-download.webp', alt: 'An Audiobookshelf book in Unpaged with its Download button.', caption: 'The Download button on a book.' }
      },
      {
        id: 'limits', title: 'What it does not do',
        body: [
          { ul: [
            '**Audiobooks only.** Podcast libraries and ebooks are not shown.',
            '**Read-only on the server.** Unpaged plays and downloads, and reports progress and finished books. It cannot upload, edit metadata or delete anything on your server.',
            '**One server at a time.** Connecting another server replaces the first one, and unsent progress for the old server is discarded.',
            '**Streaming needs the server.** If you are away from it without a VPN, only downloaded books play.',
            '**Moments stay in Unpaged.** The passages you save are not written to Audiobookshelf’s own bookmarks.',
            '**Downloads fetch one file of a book at a time**, and Audiobookshelf downloads have no Lock Screen Live Activity.'
          ] }
        ]
      },
      {
        id: 'trouble', title: 'If it will not connect',
        body: [
          { ul: [
            'Check the address includes the port if your server uses one, and that the server answers in Safari on the same iPhone.',
            'On a home network, make sure Local Network access is allowed for Unpaged in **Settings → Privacy & Security → Local Network**.',
            'Away from home, check that your VPN is connected.',
            'With an API key that fails right after you create it, make sure it is switched on in Audiobookshelf.'
          ] },
          'For anything else, the Support page has the contact address.'
        ]
      }
    ]
  },
  {
    slug: 'm4b-mp3-audiobooks-iphone',
    title: 'Play M4B and MP3 audiobooks on iPhone · Unpaged',
    description: 'Import M4B, M4A and MP3 audiobooks from Files into Unpaged on iPhone: chapters, resume, moments, sleep timer and offline playback. Includes which store purchases (Audible, Apple Books) cannot be imported.',
    short: 'Play M4B and MP3 audiobooks on iPhone',
    summary: 'Import from Files, keep chapters and your place, save moments, set a sleep timer, and listen offline. Plus which purchases cannot be imported.',
    eyebrow: 'Guide · Your own files',
    heading: 'Play <em>M4B and MP3</em> audiobooks on iPhone',
    intro: 'If you own audiobooks as plain files (an M4B from a DRM-free store, a set of MP3 files from a CD rip) Unpaged plays them from the Files app with chapters, a remembered place, bookmarks and a sleep timer. Everything stays on the iPhone.',
    tested: 'Written against Unpaged 1.5.1. The steps were run and recorded in the iOS Simulator (iOS 27) with a short test M4B that has four embedded chapters. In the recording the Files picker is replaced by a test hook that hands the same file to the importer.',
    published: '2026-10-18',
    video: {
      src: 'guides/m4b-mp3-audiobooks-iphone.mp4',
      poster: 'guides/m4b-mp3-audiobooks-iphone-poster.webp',
      width: 402, height: 874,
      label: 'Screen recording: importing an M4B audiobook, opening the chapter list, setting a sleep timer and saving a moment.',
      caption: 'Import, chapters, sleep timer, moment. Recorded in the iOS Simulator with a short test M4B.'
    },
    sections: [
      {
        id: 'drm', title: 'First: what can be imported',
        body: [
          { note: '**Store purchases with DRM cannot be imported.** Audiobooks bought from Audible (AAX and AAXC files) and Apple Books are copy-protected. Unpaged does not remove DRM and cannot play those files, so they have to stay in the app that sold them.' },
          'Unpaged plays files without DRM:',
          { ul: [
            'M4B, M4A, MP3 and AAC audiobooks, including ones bought from stores that sell DRM-free files.',
            'Several MP3 or M4A files, such as a CD rip, where each file is a chapter or a part. Select them all together in the picker.',
            'Public-domain recordings. Unpaged also has a free LibriVox catalog built in, so you do not need to import those.'
          ] },
          'The file picker offers any audio file in Files. If iOS cannot decode a file, it will not play.'
        ]
      },
      {
        id: 'import', title: 'Import from Files',
        body: [
          { ol: [
            'Put the audiobook where the Files app can see it: iCloud Drive, On My iPhone, or any provider connected to Files.',
            'In Unpaged, tap **+** at the top of the library and pick the file or files.',
            'Check the **Title** and **Author**, which are filled in from the file when it has them, and tap **Save**. The sheet also lists the imported files and the total length.'
          ] },
          'Choose several files at once and they import as a single audiobook, with tracks ordered by file name. Name them `01`, `02`, `03` and so on to get the order you want. If the same files are already in your library, Unpaged says **Already in Library** instead of making a copy, even if you renamed or moved them.',
          'Imported audio is copied into Unpaged’s own storage, so the book keeps playing if you later delete the original from Files. Imported books are available offline from the start.'
        ],
        figure: { src: 'guides/m4b-import.webp', alt: 'The Import Audiobook sheet in Unpaged with the title and author fields filled in.', caption: 'The Import Audiobook sheet.' }
      },
      {
        id: 'chapters', title: 'Chapters',
        body: [
          'Unpaged reads chapter markers embedded in M4B, M4A and MP3 files. Tap **Chapters** in the player to jump, and use previous and next chapter to move between them. A file needs at least two chapter markers to count; without them, each file in a multi-file book is one chapter.',
          'The player, the chapter list and CarPlay all show the same chapters.'
        ],
        figure: { src: 'guides/m4b-chapters.webp', alt: 'The chapter list of an imported M4B in Unpaged.', caption: 'The chapter list of an imported M4B.' }
      },
      {
        id: 'resume', title: 'Resume where you stopped',
        body: [
          'Your position is saved as you listen, per book. Close the app, restart the iPhone, switch to another book, and the book opens at the same place.',
          { ul: [
            'The mini player at the bottom of the library takes you straight back.',
            'The **Continue Listening** widget (Home Screen or Lock Screen) shows the last book and its progress. Tap to resume; the medium widget also has a Play button.',
            'Lock Screen controls, headphone buttons and CarPlay work as with any audio app. The skip buttons jump 15, 30 or 45 seconds, whichever you choose in Settings.'
          ] }
        ]
      },
      {
        id: 'moments', title: 'Bookmark a passage with a moment',
        body: [
          'Tap **Save Moment** in the player to keep the passage you just heard, then **Done** on the naming sheet. You can step back 15 seconds, 30 seconds, 1 minute or 2 minutes (or save at the exact position) in Settings, so the moment starts before the line you wanted. Give it a name and a note, and open it later from the book page or from the search across all your books, which jumps playback to that second.',
          'Saving a moment by hand is free. Automatic naming with Apple Intelligence is a separate, optional Unpaged Plus feature and is not needed for anything in this guide.'
        ],
        figure: { src: 'guides/m4b-moment.webp', alt: 'The book page of an imported M4B in Unpaged listing one saved moment with its time.', caption: 'A saved moment on the book page.' }
      },
      {
        id: 'sleep', title: 'Sleep timer, speed and offline',
        body: [
          { ul: [
            '**Sleep timer**: choose 5, 15, 30 or 60 minutes, or **End of chapter**, which pauses at the chapter’s end without starting the next one. Pausing manually keeps the timer armed; choose **Off** to cancel it.',
            '**Speed** and a five-band **equalizer** with Voice Boost are in the player, and the equalizer is remembered for each book.',
            '**Offline**: imported books are stored on the iPhone, so they play with no connection, in airplane mode, anywhere.'
          ] }
        ],
        figure: { src: 'guides/m4b-sleep.webp', alt: 'The sleep timer menu in the Unpaged player with End of chapter, 60, 30, 15 and 5 minutes and Off.', caption: 'The sleep timer menu.' }
      },
      {
        id: 'limits', title: 'What it does not do',
        body: [
          { ul: [
            'No DRM removal, and no import of Audible or Apple Books purchases (see above).',
            'No conversion or editing. Unpaged plays your files as they are and does not rewrite chapter markers or tags.',
            'Files without embedded chapters get one chapter per file, not per section.',
            'iPhone only. There is an Android version, which is a separate app with its own library.'
          ] }
        ]
      }
    ]
  }
];
