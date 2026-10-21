# App Store campaign links

Campaign links attribute first-time downloads to a channel in App Store Connect Analytics → Acquisition → Campaigns. They are public URLs, not secrets. Apple counts a download when it happens within 24 hours of the tap, shows a campaign after at least 24 hours, and hides any metric below five ([campaign links](https://developer.apple.com/help/app-store-connect-analytics/acquisition/campaign-links)).

## Tokens

A link needs two tokens: the provider token `pt`, which is `128699460` for every link from this developer account, and a campaign token `ct`, one per channel (up to 30 characters, no leading or trailing space). The App Store Connect API doesn't create campaign links ([developer forums](https://developer.apple.com/forums/thread/765763)). A hand-built link with this `pt` and a new `ct` attributes downloads the same way as one generated in App Store Connect → Analytics → Acquisition → Campaigns.

## Links

| Channel | Campaign token | Link |
| --- | --- | --- |
| Audiobookshelf third-party apps directory | `audiobookshelf-directory` | `https://apps.apple.com/app/apple-store/id6761081641?pt=128699460&ct=audiobookshelf-directory&mt=8` |
| Reddit posts and replies | `reddit` | `https://apps.apple.com/app/apple-store/id6761081641?pt=128699460&ct=reddit&mt=8` |
| Marketing site (`site/`) | `website` | `https://apps.apple.com/app/apple-store/id6761081641?pt=128699460&ct=website&mt=8` |
| Audiobookshelf custom product page | `custom-page` | `https://apps.apple.com/app/apple-store/id6761081641?pt=128699460&ct=custom-page&mt=8&ppid=0acf5796-9bc2-40d1-ac4a-eac2b3b583cb` |

The `custom-page` link opens the Audiobookshelf custom product page (`ppid`, see `CUSTOM-PRODUCT-PAGE.md`). Use it wherever Audiobookshelf users are the audience: setup guides, Audiobookshelf community replies, reviewer pitches about self-hosting. Custom product page traffic also shows separately under Acquisition → Product Pages, with or without a campaign.

## Where each link goes

- **audiobookshelf-directory:** the directory entry in audiobookshelf/audiobookshelf-docs#59 links to the website, because the maintainers' other entries link to project pages. The entry can switch to this link in a later update.
- **reddit:** new posts and replies only. Links in already published posts can't be tagged after the fact.
- **website:** the site's App Store badges and buttons (`appStoreLink` in `site/site.config.json`).
- **custom-page:** any link meant for Audiobookshelf users.

Record source, territory, publication date and hours spent next to each campaign's downloads, as `docs/research/marketing-channels-2026-10-06.md` describes.
