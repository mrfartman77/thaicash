# ThaiCash — App Store listing kit

Everything ready to paste into App Store Connect. Character limits noted.

## Identity

| Field | Value |
|---|---|
| Name (30) | `ThaiCash` |
| Subtitle (30) | `The true cost of your baht` |
| Bundle ID | `com.thaicash.app` |
| SKU | `thaicash-ios` |
| Primary category | Finance |
| Secondary category | Travel |
| Price | Free (no IAP) |
| Age rating | 4+ (answer "No" to all content questions) |

## Promotional text (170 max — editable without review)

> Live booth boards, real card fees, verified transfer pricing — five
> corridors into Thai baht, ranked by what you actually keep. Free, no
> accounts, nothing tracked.

## Description

> Getting baht costs more than the fee on the receipt. The booth has "no
> commission" but a quiet rate margin. Your debit card adds a foreign-transaction
> percentage, your bank's ATM fee, and Thailand's ฿250 machine fee — twice if
> you withdraw twice. Transfers hide their cost inside the exchange rate.
>
> ThaiCash shows the TRUE COST of every way to turn your money into Thai
> baht, ranked, in one screen.
>
> FIVE CORRIDORS
> USD, EUR, AUD, CNY and USDT — each with the methods that actually exist for
> that home currency, priced from verified, dated sources.
>
> LIVE DATA, HONESTLY LABELED
> • Exchange-booth board rates from Bangkok's best-known chains, refreshed
>   hourly — the rate you'd see standing at the counter.
> • Live USDT/THB bids from Thailand's licensed venues.
> • Daily mid-market rates with a 7-day trend.
> Every number shows its age. Nothing pretends to be fresher than it is.
>
> EVERY METHOD, ALL-IN
> Cash at a booth, the right card at an ATM (and which machines charge what),
> bank transfers from Wise to Alipay Flash Remit, selling USDT — including
> delivery time, because a transfer that lands next Wednesday isn't the same
> baht as cash in your hand today.
>
> FIND IT, THEN DO IT
> Tap a booth or ATM to open it in Apple Maps. Tap a provider for its
> official site. Enter your own card's fees once and every comparison
> becomes exactly yours.
>
> FREE, PRIVATE, SELF-CONTAINED
> No accounts. No ads. No tracking. No data collected — your settings never
> leave your phone.

## Keywords (100 max, comma-separated, no spaces)

`thailand,baht,thb,exchange,rate,currency,travel,money,atm,fee,transfer,remit,bangkok,usdt,wise`

(95 characters. Don't waste keywords on "ThaiCash" — the name is indexed.)

## URLs

| Field | Value |
|---|---|
| Support URL | `https://github.com/mrfartman77/thaicash` |
| Privacy Policy URL | `https://github.com/mrfartman77/thaicash/blob/main/PRIVACY.md` |

## App Privacy questionnaire (App Store Connect)

- "Do you or your third-party partners collect data from this app?" → **No**.
- Result: the listing shows **"Data Not Collected"** — the strongest label
  there is. (The app's network calls fetch public reference data only; no
  identifiers are sent, so nothing qualifies as "collection".)

## Export compliance

`ITSAppUsesNonExemptEncryption = NO` is already set in the project — only
standard HTTPS. No dialog at upload, no annual self-classification report
needed for exempt apps.

## App Review notes (paste into the review notes field)

> ThaiCash is a reference utility: it compares the all-in cost of converting
> USD/EUR/AUD/CNY/USDT into Thai baht. No account or sign-in exists; all
> features are immediately accessible. The app fetches public reference data
> (exchange rates and a method catalog) over HTTPS from open.er-api.com,
> frankfurter.dev and raw.githubusercontent.com. It facilitates no
> transactions, holds no funds, and contains no purchases. Crypto-related
> rows are informational price comparisons of Thailand's SEC-licensed
> exchanges; the app links to their public websites only.

## Screenshots

`AppStore/screenshots/` — captured at iPhone 6.9" (1320×2868). Upload the
6.9" set; App Store Connect scales it for smaller devices.

Suggested order: corridor menu → USD home → ATM ranking → booth directory →
USDT corridor → CNY corridor.

## Remaining human steps (need the Apple ID)

1. Enroll: developer.apple.com → Account → Enroll (individual, $99/yr).
2. Xcode → Signing & Capabilities → select the new team.
3. appstoreconnect.apple.com → My Apps → "+" → New App (fill from this file).
4. Xcode → Product → Archive → Distribute App → App Store Connect.
5. TestFlight tab → add internal testers or create an external-test public link.
6. When ready for the real release: attach screenshots + this copy, submit.
