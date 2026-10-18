# App Store campaign links

Campaign links attribute first-time downloads to a channel in App Store Connect Analytics → Acquisition → Campaigns. They are public URLs, not secrets. Apple counts a download when it happens within 24 hours of the tap, shows a campaign after at least 24 hours, and hides any metric below five ([campaign links](https://developer.apple.com/help/app-store-connect-analytics/acquisition/campaign-links)).

## The one missing value

A link needs two tokens: the provider token `pt` (the same for every link from this developer account) and a campaign token `ct` (one per channel, up to 30 characters, no leading or trailing space). The App Store Connect API doesn't expose the provider token or create campaign links ([developer forums](https://developer.apple.com/forums/thread/765763)), so read it once in the web UI:

1. App Store Connect → Apps → Unpaged → **Analytics** tab → **Acquisition** → **Campaigns**, then click **+** next to Campaigns.
2. In the **Campaign** field, type `website`. The field's text becomes the campaign token.
3. Copy the generated link. Copy the number after `pt=` and replace `PROVIDER_TOKEN` in the table below.
4. Optionally repeat steps 1–3 with `audiobookshelf-directory`, `reddit` and `custom-page`, so each campaign is listed by name. A hand-built link with the same `pt` attributes downloads either way.

## Links

| Channel | Campaign token | Link |
| --- | --- | --- |
| Audiobookshelf third-party apps directory | `audiobookshelf-directory` | `https://apps.apple.com/app/apple-store/id6761081641?pt=PROVIDER_TOKEN&ct=audiobookshelf-directory&mt=8` |
| Reddit posts and replies | `reddit` | `https://apps.apple.com/app/apple-store/id6761081641?pt=PROVIDER_TOKEN&ct=reddit&mt=8` |
| Marketing site (`site/`) | `website` | `https://apps.apple.com/app/apple-store/id6761081641?pt=PROVIDER_TOKEN&ct=website&mt=8` |
| Audiobookshelf custom product page | `custom-page` | `https://apps.apple.com/app/apple-store/id6761081641?pt=PROVIDER_TOKEN&ct=custom-page&mt=8&ppid=0acf5796-9bc2-40d1-ac4a-eac2b3b583cb` |

The `custom-page` link opens the Audiobookshelf custom product page (`ppid`, see `CUSTOM-PRODUCT-PAGE.md`). Use it wherever Audiobookshelf users are the audience: setup guides, Audiobookshelf community replies, reviewer pitches about self-hosting. Custom product page traffic also shows separately under Acquisition → Product Pages, with or without a campaign.

## Where each link goes

- **audiobookshelf-directory:** the directory entry in audiobookshelf/audiobookshelf-docs#59 links to the website, because the maintainers' other entries link to project pages. Once the provider token is filled in, the website's Audiobookshelf section can use this link on its App Store button, or the entry can switch to it in a later update.
- **reddit:** new posts and replies only. Links in already published posts can't be tagged after the fact.
- **website:** the App Store buttons rendered from `site/site.config.json` (`appStoreUrl`). Change it in a site commit once the token is known.
- **custom-page:** any link meant for Audiobookshelf users.

Record source, territory, publication date and hours spent next to each campaign's downloads, as `docs/research/marketing-channels-2026-10-06.md` describes.
