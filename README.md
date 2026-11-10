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
