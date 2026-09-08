# Support window: newsletter signup + "Buy me a coffee" consumable

Date: 2026-09-08. Status: approved in chat, ships as JustMD 1.1.

## Goal

Give users two ways to stay in touch with / support the developer from
inside the app: leave an email for future mailings (stored in Supabase),
and buy a repeatable "Buy me a coffee" in-app purchase (App Store build only).

## Constraints

- 1.0 is in App Store review (build 5). Do not touch that submission. Everything
  here goes out as 1.1 (`MARKETING_VERSION = 1.1`); the IAP is attached to 1.1.
- Both distribution channels build from one source. The DMG (Developer ID)
  build must not contain the purchase UI or StoreKit code; the newsletter form
  stays in both.
- Keep NSDocument editor, Read mode and existing windows untouched.
- Supabase project: **Nuta Apps** (`txeisrdkgcloqjiqexnw`, us-west-2), currently
  paused; restore before use.

## Components (new module `JustMD/JustMD/Support/`)

| File | Role |
|---|---|
| `SupportWindowController.swift` | `NSWindowController` singleton (same shape as Welcome/Preferences), hosts `SupportView`. |
| `SupportView.swift` | SwiftUI: title, "Get updates" section, "Buy me a coffee" section (compiled out under `DIRECT_DISTRIBUTION`). |
| `NewsletterClient.swift` | `NewsletterSubscribing` protocol + `NewsletterClient` (URLSession → Supabase PostgREST). Email validation lives here as a static helper. |
| `NewsletterViewModel.swift` | `@MainActor ObservableObject`; states `idle / sending / subscribed / failed(message)`. |
| `CoffeeStore.swift` | `#if !DIRECT_DISTRIBUTION`. `@MainActor ObservableObject` over StoreKit 2; states `loading / ready(price) / purchasing / thanked / unavailable`. Keeps `coffeeCount` in UserDefaults. |
| `SupportConfig.swift` | Supabase URL + publishable key, product id `com.nuta.JustMD.coffee`. |
| `JustMD.storekit` | Local StoreKit configuration for the Debug scheme. |

Entry points:
- Help menu → "Support JustMD…" (installed from `AppDelegate`).
- Welcome window: small secondary "Support JustMD" text button under the actions.

## Newsletter data flow

1. User types email, presses Subscribe (or Return).
2. `NewsletterClient.isValidEmail` (trim, one `@`, dot in domain, no spaces) gates the request.
3. `POST {SUPABASE_URL}/rest/v1/newsletter_subscribers` with headers
   `apikey`, `Authorization: Bearer <publishable key>`, `Content-Type: application/json`,
   `Prefer: return=minimal`; body `{ "email", "source": "justmd-mac", "app_version" }`.
4. 201 → subscribed. 409 (unique violation) → subscribed (idempotent). Anything else /
   transport error → `failed` with a short human message; the email stays in the field.
5. Subscribed state is remembered in UserDefaults (`support.subscribedEmail`) so the
   form shows "You're on the list" on reopen.

Supabase schema (migration `newsletter_subscribers`):

```sql
create table public.newsletter_subscribers (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  source text not null default 'unknown',
  app_version text,
  created_at timestamptz not null default now()
);
create unique index newsletter_subscribers_email_key on public.newsletter_subscribers (lower(email));
alter table public.newsletter_subscribers enable row level security;
create policy "anon can subscribe" on public.newsletter_subscribers
  for insert to anon with check (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$');
-- no select/update/delete policies for anon
```

Sandbox: `ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES` in both configurations.

## Purchase data flow (App Store build)

1. On window open, `CoffeeStore.load()` → `Product.products(for: [productId])`. Empty
   result → `unavailable` (section hidden).
2. Button "Buy me a coffee · $2.99" → `product.purchase()`.
3. `.success(verified)` → `transaction.finish()`, `coffeeCount += 1`, state `thanked`
   (button re-enabled so it can be bought again). `.userCancelled` → back to `ready`.
   `.pending` → `ready` with note. Errors → `ready` + alert text.
4. `Transaction.updates` listener started at store init finishes any stray consumables
   and bumps the counter.

App Store Connect: consumable IAP, product id `com.nuta.JustMD.coffee`, reference
name "Buy me a coffee", en-US display name "Buy me a coffee", description "A small
thank-you to the developer. Buy as many as you like.", price tier $2.99. Created via
the ASC MCP; submitted with 1.1.

## Build gating

`scripts/release-devid.sh` passes
`SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) DIRECT_DISTRIBUTION'` to the archive
step. Xcode Cloud (App Store) builds without it.

## Error handling

- Newsletter: no retries; one inline message under the field. Never blocks UI.
- Store: StoreKit errors surface as inline text, never modal alerts. Missing product
  hides the section instead of showing a broken button.

## Testing

Swift Testing in `JustMDTests`:
- `NewsletterClientTests`: email validation table; request shape (URL, headers, JSON
  body) and 201/409/500/transport mapping via a `URLProtocol` stub.
- `NewsletterViewModelTests`: state transitions with a fake `NewsletterSubscribing`.
- `CoffeeStoreTests` (`#if !DIRECT_DISTRIBUTION`): state transitions with a fake
  product provider protocol (`CoffeeProductProviding`); no real StoreKit.
- Manual: purchase in the Debug scheme with the `.storekit` file; DMG build compiles
  with the flag and shows no coffee section.

## Follow-ups (not in this change)

- ASC privacy labels: Contact info → Email, used for developer marketing.
- Privacy policy on justmd.nuta.life (repo `yuraist/justmd`): mention email collection.
