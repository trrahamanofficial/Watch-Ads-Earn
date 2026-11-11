# Watch Ads & Earn

Mobile-first React + Vite + Supabase rewards dashboard. Black, orange and gold theme.

## Included
- Email/password signup and sign-in
- Responsive dashboard and wallet display
- Earn, redeem, activity, referral and admin placeholder screens
- Starter database schema with row-level security
- No client-side point crediting: only signed, server-verified provider callbacks may award points

## Setup
1. Use Node.js 20+.
2. Copy .env.example to .env and add the Supabase project URL and publishable key.
3. Run npm install and npm run dev.
4. Run supabase/schema.sql in the SQL Editor of the dedicated Watch Ads & Earn project.

## Before real launch
Obtain written approval from an ad/offer provider for incentivized traffic and verify India payout support. Implement signed callback verification, idempotency and fraud checks. Configure payout/redeem inventory, privacy policy, terms, support and compliance. Some services may cost money. This starter is not a live ad network or a promise of earnings.


## Verified ad callback (integration scaffold)

The repository contains a fail-closed Supabase Edge Function at
`supabase/functions/ad-provider-callback/index.ts`. It expects an HMAC-SHA256
signature in `x-provider-signature: sha256=<hex>` over the exact raw request
body and a normalized completion payload. It uses a unique provider/event key
and a single database transaction to prevent duplicate point credits.

**This is not yet connected to an ad network and must not be enabled yet.**
Each provider has its own signature scheme, event fields, user-sub-ID macros,
postback retry rules, and incentive policy. Before deployment, obtain written
approval for incentivized traffic, verify India support, and adapt the handler
to that provider's official documentation. Only then set
`AD_PROVIDER_NAME` and `AD_PROVIDER_WEBHOOK_SECRET` as Edge Function secrets.
Never put a secret in Git or the browser. Do not use a provider that cannot
cryptographically authenticate completion callbacks.

## Current deployment configuration

A Cloudflare Pages project named `watch-ads-earn` is connected to this repository.
- Production branch: `main`
- Build command: `npm run build`
- Output directory: `dist`
- Supabase project URL and publishable key are configured as build-time environment variables in Cloudflare Pages.
- Public site address: https://watch-ads-earn.pages.dev

A Pages project being created does not mean the first deployment has completed. Confirm the first production deployment and test authentication before announcing the site as live.

## Current feature status

- Password reset email flow is included; configure the Supabase Auth Site URL and redirect allow-list for the final deployed domain.
- Wallet, ledger, withdrawal request, admin review/refund, reward publishing, redeem-code inventory and redemption are implemented through database functions and RLS.
- Referral signup attribution is recorded; referral bonuses remain disabled until qualifying activity and anti-fraud checks are implemented.
- Earn offers remain unavailable until an incentivized ad provider approves the site and its signed callback format is integrated.
- UPI payouts are manual: an admin must send the transfer outside the website before marking a request as paid.
