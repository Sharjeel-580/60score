# 60Score v1.3.0 — Live-test bug report (Dazy, 2026-10-20 ~21:25)

## Bug: Account data visible & editable to EVERYONE (guest / new account)

**Reported:** After installing v1.3.0, Super Sixty shows up — fully
editable — no matter how the app is opened: Guest mode, Google login,
or a brand-new account. Fixtures could be cancelled and data changed
by a non-owner. Expected design: the tournament belongs to the OWNER's
account only; guests/new accounts start empty and can only find a
published tournament via Search, view-only.

**Root causes (code-verified):**
1. `Store` kept ONE global set of SharedPreferences keys — local data
   was device-global, never scoped to an identity. Whoever opened the
   app got the same data with full edit rights.
2. `AuthService.signOut()` never touched local data — after logout the
   owner's data stayed on screen, and choosing Guest walked straight
   back into it.
3. `SyncService.pull()` on a fresh account (no backup doc yet) PUSHED
   the device's local data up as that account's baseline — so every
   new account instantly "owned" the owner's data, locally and in its
   cloud backup.
4. Debounced sync/republish timers captured the store, not the
   identity — a pending push could fire after an account switch and
   write one identity's data into another account's documents.
5. Login pulled cloud state into the same shared store
   (last-write-wins), so a stale cloud snapshot could replace the
   phone's current data (fixtures seen cancelled / scoring state
   stale — same family of symptoms).

## Fix — v1.3.1+14: per-identity local data

- All Store data keys are scoped: `<base>__<identityId>`, identityId =
  'guest' or the account uid. `welcomeDone` stays global; the sync
  clock (lastModified) is scoped per account.
- `Store.activateIdentity(id)` cancels pending cloud writes, clears
  memory, loads only that identity's scope. `activateAccount(uid)`
  first claims pre-v1.3.1 unscoped ("legacy") data into the account —
  only when legacy data exists AND the account's scope is empty;
  legacy keys are then deleted. Guests never claim and never see it.
- Login (gate + Settings): activate the account's scope BEFORE pull.
  Guest: activate the 'guest' scope before passing the gate.
- Logout (Settings): sign out → activate the always-empty 'locked'
  scope → pop to root; the SplashGate now derives the gate LIVE from
  auth state, so the login gate returns immediately. Button subtitle
  corrected ("Your data stays saved under your account").
- Boot: auth settles first; a restored session activates its account
  scope (+ background pull); otherwise the guest scope loads.
- Sync/publish timers now verify the identity at fire time
  (`currentUser.uid` + `store.identityId`) and are cancelled on every
  identity switch.
- Tests: `test/store_identity_test.dart` (4 tests) — guest/account
  isolation, locked scope, legacy claim (first account only),
  no-overwrite claim. Suite: 102/102, analyze clean.

**Owner note:** on Dazy's phone the first v1.3.1 login with HIS
account claims the on-device Super Sixty data into that account
(it is also in that account's cloud backup). Guests and other
accounts on the same phone see only their own empty workspace +
Search (published, view-only).

---

# More points from Dazy's testing (batch — fix together in one build)

**STATUS (2026-10-21 ~12:27):** List complete — Dazy ne "Baki kam
start kro" kaha. Saare points (#1 family + #2 + #3) EK batch mein
implement ho gaye: owner claim-guard (sirf xharitarar580@gmail.com),
account profile + deterministic user code (60S-XXXXXX) + My Profile
screen (apne stats), Statistics cards redesign (shared
StatCategoryCard), published preview mein Statistics tab + read-only
scorecard. flutter analyze saaf, tests 108/108 pass (2 dafa verify).
Files GitHub push ho rahi hain → final CI build → APK delivery.

## #1b — Point #1 clarified by Dazy (2026-10-21, emphasis: "ye cheez sab se main hai")
- Guest mode = BILKUL khali. Guest sirf apna naya data khud create
  kar sakta hai; by default us mein kuch nahi hona chahiye.
- Super Sixty search karke khule to sirf PREVIEW ho: stats, fixtures,
  schedule — sirf dekhne ke liye. Koi edit / add / delete NAHI.
- Gap found vs this spec: the published (preview) screen currently
  has Fixtures & Results / Points Table / Teams tabs but NO player
  stats tab. Batch fix: add a read-only STATS tab to the published
  preview (most runs / wickets etc. from the snapshot, same stats
  engine) so the preview covers stats + fixtures + schedule exactly
  as Dazy specified. Still zero edit/add/delete controls.

## #1c — Owner-account binding confirmed by Dazy (2026-10-21)
- Super Sixty sirf OWNER ke account par milega — guest par nahi,
  kisi aur Google account par nahi.
- Wo email jis bhi mobile par login ho, Super Sixty waisa hi aa jaye
  (per-account cloud sync/backup se — pehle se yahi system hai).
- Dazy ne email share karne ki offer ki — system ko zaroorat nahi:
  har account ka data app khud alag rakhti hai (v1.3.1 fix). Us se
  sirf confirm karna hai ke main account xharitarar580@gmail.com hi
  hai (Firebase project wala account) taake note ho jaye.

## #2 — Statistics screen cards look plain; redesign in a better shape
(2026-10-21, screenshot: ~/workspace/user/files/406346_1_muea.jpg)
Dazy: "Ys stats wala button abi tak esy e ha esy ksi bhtr shakal ma
lekho" — the Statistics top-performer cards (Most Runs, Most Wickets,
Highest Score, Best Bowling, Most Sixes, Most Fours, Most Catches,
Most Stumpings, Fastest Fifty, Fastest Hundred) are big plain blue
boxes, mostly empty space, label + "No data yet" only.
Fix direction: compact, better-looking cards — per-category icon,
player photo/avatar + name + value when data exists, small elegant
empty state when not, Ocean-theme accents; same data/engine, only
the presentation changes.

## #3 — Har naye account ki apni auto-profile + ID + apne stats alag (2026-10-21)
Dazy: owner ke account ke ilawa jo bhi banda Google se login kare ya
email se naya account banaye, us ke liye:
- Ek NEW profile khud ban jani chahiye — us ki apni PLAYER profile.
- Us ki ek apni ID ban jani chahiye (unique user/player ID).
- Us ke apne stats ALAG se show hon — kisi aur ke stats se mix nahi.
Design (batch build): signup/first-login par account ke liye profile
record bane (naam, unique ID, account se linked); app mein "My
Profile" par us ki ID + us ke apne data ke stats alag nazar ayen.
Per-account data separation (v1.3.1) is ki bunyad pehle se hai —
ye point us par profile/ID/stats-view ka izafa hai. Interpretation
Dazy ko suna di hai; correction aaye to update hoga.

## #1d — System MOBILE-wise nahi, ACCOUNT-wise hoga (Dazy, 2026-10-21)
Dazy ka sawal/confirmation: "mere mobile par koi aur account login
ho to sirf preview show hona chahiye; mera account kisi bhi mobile
par login ho to Super Sixty aa jana chahiye — cloud sync account ke
hisab se ho, mobile ke hisab se nahi. Is tarah ho sakta hai?"
Jawab (confirm kiya gaya): ha — v1.3.1 fix yehi hai. Data account ke
cloud backup + account-scope se bandha hai, device se nahi. Note:
dusre account ko preview tabhi milega jab tournament PUBLISHED ho;
unpublished ho to dusre ko kuch bhi nahi dikhta.

## #1e — FULL ACCOUNT SYSTEM (umbrella design, Dazy 2026-10-21)
Points #1/#1b/#1c/#1d/#3 ka majmua — final design:
- OWNER (Dazy) ki email login → pura ADMIN system: Super Sixty +
  us ka saara data/control, kisi bhi mobile par cloud se.
- KOI AUR email login (Dazy ke apne mobile par bhi) → bilkul SAAF
  naya system us user ke liye: us ki apni player profile, apni ID,
  apne stats, apne tournaments — pura app us ke liye usi ka, lekin
  owner ke data se 100% alag. Baray cricket apps (profile/ID/stats
  wale system) ki tarah har user ka apna mukammal setup.
- Dono systems kabhi mix nahi honge.

## #1f — Super Sixty PUBLISHED rahega; preview = stats + scorecard + fixtures (Dazy, 2026-10-21)
- Dazy ki hidayat: Super Sixty publish hi rahega (owner account se
  published state default rahegi).
- Dusre users ko preview mein ye nazar aye: stats, SCORECARD,
  fixtures — sab sirf dekhne ke liye.
- Batch fix mein izafa: abhi preview mein sirf score lines hain;
  fixture par tap karke pura read-only SCORECARD (batting/bowling
  tafseel, snapshot ke match data se) khulega. Koi edit nahi.

## #1g — OWNER EMAIL designated (Dazy, 2026-10-21) — spelling confirm pending
- Dazy: "xharitarat580@gmail.com is email sa mjhe sab edit milna
  chaye; iska elawa just jo new bnaya jaye ga aur preview."
- Matlab: owner email wale account ko sab edit rights; baqi sab ko
  sirf un ka apna naya data + published preview.
- System design: har account ko APNE data par pura edit milta hai —
  email hardcode karne ki zaroorat nahi; Super Sixty pehle se owner
  account ke cloud mein hai. Extra safety ke liye: phone par para
  purana (legacy) data SIRF owner email wale account mein claim
  hoga (claim-guard owner email se joda jayega).
- ⚠️ SPELLING — RESOLVED (2026-10-21 12:10): Dazy ne confirm kiya
  sahi email **xharitarar580@gmail.com** hai (extra 'r' wali — jo
  aaj subah us ne "xharitarat580" likhi thi wo typo thi). Owner
  account = xharitarar580@gmail.com (yehi Firebase project wala
  account bhi hai).
