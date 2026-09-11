# operating_rules.md — Non-negotiable operating rules

> These rules come from the user's directives + plan §Anti-overengineering + §Priority Principle.
> When any instruction conflicts with these, STOP and ask the user.

## 1. Priority Principle (applies to every technical decision, in this exact order)

1. **0đ operating cost** — free tiers only: Cloudflare Workers/D1/KV free limits, OSRM +
   Nominatim public servers. No paid APIs, no Google Maps, no paid SMS in P0.
   Check write/read quotas before adding any storage write path.
2. **Matching quality** — the corridor/direction/detour pipeline is the product. Do not
   simplify it into plain proximity search.
3. **Reliability** — atomicity for money-like invariants (accept, limits), server-side
   enforcement, no silent failure swallowing (offline end-trip must surface "chưa sync").
4. **No over-engineering** — see §2.

## 2. Anti-overengineering rules

- No feature outside P0/P1 scope as defined in the plans. The P1 list
  (notifications, history, ratings, secure storage, map picker…) stays frozen until the
  pilot passes.
- No AI/ML, no payments, no realtime chat, no WebSockets, no background daemons.
- No abstraction layers "for later" beyond what a plan explicitly calls for
  (the MapsProvider and TokenStorage interfaces are the ONLY sanctioned seams).
- Prefer stdlib / platform features over adding dependencies. Ask before adding any
  package to pubspec.yaml or package.json.
- Lazy expiry over cron jobs. KV over D1 for hot data. One query over many.
- If a change can be done by deleting code, prefer that.

## 3. Evidence discipline (user directive, verbatim spirit)

The user does NOT accept verbal reports: agents have claimed "done" without changing
anything. Therefore:

- **"Done" = code diff + real test output.** No exceptions.
- Never say PASS without a run that printed it in this session.
- If verification is impossible (e.g. no local builds allowed), say exactly what was
  NOT verified and hand the user the exact command to verify.
- After each phase/task: list completed items vs the DoD checklist, then ASK before
  moving to the next phase.

## 4. Server-side authority

- Every permission check (role, ownership, consent, block, rate limit, state machine)
  lives in the Worker. Client checks are UX only and must never be trusted.
- Role and account status are read from D1 on every request (auth middleware).
- State transitions go through `order_state_machine.ts` only — no ad-hoc status writes.

## 5. Privacy rules (plan §18)

- Driver's raw lat/lng NEVER leaves the backend; customers get rounded distance only.
- Customer phone number is revealed to a driver only after a successful contact.
- GPS tracking exists only while a trip is active; location KV entries are deleted at
  trip end.

## 6. Communication

- Working language: Vietnamese (match the user); keep code/identifiers in English.
- Keep responses short and factual; tables for checklists.
- All destructive/irreversible actions (git push, deploy, DB mutations on real
  resources) require explicit user permission.

## 7. SSOT discipline

- `.plan/*.md` documents are the source of truth. Code conflicts → code is wrong unless
  the user approved a deviation (record deviations in README "Quyết định kỹ thuật").
- Do not rewrite plan docs on your own initiative.
