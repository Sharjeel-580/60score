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

## #3 — Har naye account ki apni auto-profile + ID + apne stats alag (2026-10-21)Dazy: owner ke account ke ilawa jo bhi banda Google se login kare ya
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

---

# v1.3.1 RETEST points (2026-10-21, build delivered 12:57)

## #R1 — Data asal account (580) mein nahi, 550 wale backup mein hai
- Dazy ne uninstall karke v1.3.1 install ki, 580 se Google login —
  Super Sixty nahi mila, edit bhi nahi. Search bhi khali.
- Server check (Muse, Firebase console): **published_tournaments
  collection exist hi nahi karti** — Super Sixty kabhi publish nahi
  hua tha (local flag Published dikhata hai lekin server doc nahi
  bana) → search khali hona bug nahi.
- 2 user backups maujood: uid ZWbPNOWBY2... (profile "xharitarar550"
  — tournaments mein "Super sixty league" hai; live update ho raha
  tha) aur uid oUQwZgAx... (profile "Muhammad Sharjeel", contact
  xharitarar580@gmail.com). Asal league data 550 wale backup mein
  lagta hai — purani app mein phone par active account wahi tha.
- 550 se login par tournament aa gaya LEKIN khali shell: 0 teams,
  0 matches (screenshot 13:12). Dono backups ki teams/matches
  tafseel verify ho rahi hai — asal data kahan hai pakka karna hai.
- ⚠️ Mashkook bug: fresh (khali) scope ka sync push login ke baad
  pull se pehle fire ho to cloud backup overwrite ho sakta hai
  (push-before-pull race) — v1.3.2 mein fix: pehla pull complete
  hone tak push band.
- **VERIFIED (13:17, dono backups ka full read):** 580 backup =
  bilkul khali (0/0/0). 550 backup = sirf 1 tournament "Super sixty
  league" (id tournament_1792570168972264_1 — AAJ 13:09 par bana,
  Dazy ne khud add kiya tha naam-wale screenshot ke liye), teams [],
  matches [], baqi sab []. **Cloud mein asal purana data kahin
  nahi bacha.** Phone ka data uninstall ke saath gaya; purana setup
  zyada tar purana SEED tha (6 teams + 18 fixtures) — seed code git
  history mein mehfooz hai (9dcc4e3 se pehle ke commits, e.g.
  d2cac2c). **Recovery plan (Dazy ki haan baqi):** seed JSON history
  se nikaal kar 550 ke backup mein server-side likhna → app pull se
  pura setup wapas. Dazy ke khud add karda extras (players/photos)
  recover nahi honge.
- **✅ RESTORE + PUBLISH DONE (13:45, Dazy ki haan par):** seed
  payload tayyar + validate (restore/app_data_fields.json,
  published_doc.json; generator tool/restore_gen.dart) aur console
  se 550 backup mein likha gaya (matches 8559 chars verified,
  updatedAt 1792571343037, profile untouched) + published doc
  `published_tournaments/seed_tournament_ssl2` banaya gaya (data
  9234 chars verified). **Publish ki asal wajah bhi pakri gayi:**
  local `published` flag backup/pull se aa sakta hai baghair server
  write ke; pull `skipSync` par khatam hota hai (republish kabhi
  arm nahi hota); `_writeDoc` ki har error chup chaap swallow hoti
  hai, badge sirf local flag se banta hai — v1.3.2 mein fix:
  publish par saaf error/confirmation + pull ke baad republish arm
  + size guard. Dazy ka live test baqi: 550 login → pull → data;
  guest search → preview.

## #R2 — Tournaments list card: naam har letter alag line par
(screenshot: ~/workspace/user/files/406551_7_h3m6.jpg)
Tournament card par naam ("Super sixty league") ek letter per line
wrap ho raha hai — title column boht tang hai (badge + action icons
ke saath layout squeeze). Fix: title ko proper width/Expanded mile,
naam ek-do lines mein saaf aye.

## #R3 — Statistics screen ke upar wala "Statistics" heading
(2026-10-21, screenshot: ~/workspace/user/files/406552_8_ub0o.jpg)
Dazy: upar jo "Statistics" likha hai — "isko khatam kar do ya isko
thora sa achhe tareeqe mein kar do". Screenshot mein heading
doubled/ghosted bhi lag raha hai (app bar title + body header
overlap ki surat). Fix direction: duplicate heading khatam — sirf
ek saaf title rahega; body wala bara header hata diya jayega.
Cards ki nayi shakal is screenshot mein theek nazar ayi (icons,
compact, chhota "No data yet") — redesign confirm.

## #R4 — Owner account par EMAIL + PASSWORD login (Dazy, 2026-10-21)
Dazy ki hidayat: us ke apne account ke liye email + password login
lazmi ho — har mobile par Google lagana mumkin nahi hota; wo sirf
email aur password daal kar login kare aur saara data editable
mile. Password Dazy KHUD set karega (Firebase reset/set link se jo
us ki email par jayega) — password na chat mein ayega, na Muse
banayega (security rule, us ko bata diya gaya hai).
PENDING FAISLA: password kis account par lage — 550 (data wahi hai)
ya 580 (designated owner)? Dazy ke jawab par: (a) 550 owner final →
kOwnerEmail constant 550 karna hoga agle build mein + reset link
550 par; (b) data 580 transfer → pehle transfer, phir reset 580 par.
Dazy ne ye bhi kaha: "in cheezon ko note karo, behtar karo, theek
karo" — R1–R4 sab v1.3.2 batch mein fix honge.
**FAISLA (2026-10-21 13:15): "550 he rehny do"** — owner/app account
FINAL = xharitarar550@gmail.com. Data wahi rahega, publish wahi se
hoga, password bhi 550 par lagega (reset link Firebase se bhijwaya
ja raha hai — Dazy khud set karega). 580 sirf Firebase/Play
developer account rahega. v1.3.2 mein kOwnerEmail bhi 550 hoga.
