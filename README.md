# Browser

An iOS browser where a query goes through a router that decides what kind of
card to show. The router is TypeSafe's Jev, a System One model: it picks one of
five response formats and reports how sure it is. Three cards exist: a Google
results web view (`web_results`), and two Gemini answer cards, `narrative`
(a few paragraphs that answer only the question) and `one_line` (a single
line such as "24 days"). `map` and `stock` still render web results. The
decision and the answer's cost are shown in a Debug ribbon and logged on the
device. Every future format is a new `CardPlan` case, a new SwiftUI card view,
and a provider behind the router.

## Run

1. Open `Browser.xcodeproj` in Xcode 26, pick your team under
   Signing & Capabilities once. Minimum iOS 26.
2. Get a Jev key from https://console.typesafe.ai/keys and a Gemini key from
   https://aistudio.google.com/apikey (on a project with billing enabled;
   Google Search grounding is not on the free tier), then:
   ```
   cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
   ```
   and paste both keys. The file is gitignored. Without the Jev key the app
   runs with the local router (every query is a Google search) and the ribbon
   says "no key"; without the Gemini key `narrative` and `one_line` show web
   results and the ribbon says "no Gemini key".
3. Run on a device.

## How a query is routed

`BrowserSession.submit` → `Router.route` → `RouteResult { plan, decision }`.

`JevRouter` (used when a key is configured):
- An address (`example.com`, `https://…`) loads directly; Jev is not asked.
- Anything else is sent as `{ query, locale }` with one Choice question over
  `ResponseFormat.allCases`. Options reach Jev in declaration order, with
  `web_results` first, because Jev leans toward the first option when unsure.
- Confidence below `JevRouting.confidenceFloor` (0.5) falls back to
  `web_results`. Any error or a 2.5 s timeout does the same.
- The format maps to a plan in `JevRouter.plan(for:query:)`: `web_results`,
  `map` and `stock` load a Google results page; `narrative` and `one_line`
  become `.answer(format:query:)`.
- Each decision is appended to `Application Support/Browser/decisions.jsonl`
  (query, format, confidence, every option's probability, model, latency,
  tokens; for answer plans, the answer summary too). Nothing leaves the phone
  unless you export it from the ribbon.

Model is pinned to `jev-1.13.0`. A routing request is roughly 500 input tokens
at $0.042 per million, so a few hundred searches a month cost under a cent.

## Answer cards

`AnswerSession` streams one answer at a time from Gemini `gemini-3.1-flash-lite`
(Interactions API, thinking `minimal`, `store: false`, no tools). The system
instruction is the per-format rule set in `AnswerPrompt`
(`Packages/Routing/Sources/Answers`): narrative answers only the question in
two to four plain paragraphs; one-line gives the answer itself in at most
twelve words, never a sentence restating the question. The input carries the
query plus the device date, time and zone and the locale, so "today", "now"
and "the time in X" work without any lookup.

The model has no web access, on purpose. Grounding with Google Search was
built and removed: Google's terms require their Search Suggestions bar,
unmodified and full width, under every grounded answer, and it cannot be
restyled. So:
- a one-line question that needs live data (today's weather, a price, a
  rate, a score, the latest news) makes the model reply with the marker
  `NEEDS_LIVE_DATA`, which the app never shows; it loads the Google results
  page for the query instead and logs `needsLiveData`;
- a narrative question about recent events gets one plain sentence saying
  the answer may be out of date, then what the model knows; the Web results
  button is on every answer card.

No first byte in 10 s, or any failure before text arrives, falls back to web
results; a failure after some text keeps the text and says it stopped early.

Cost, from Google's pricing page on 2026-10-21 (pinned in `GeminiPricing`):
$0.25 per million input tokens, $1.50 per million output tokens including
thinking, so about $0.0005 per narrative answer and nothing per search,
because there are none. The ribbon shows each answer's tokens, cost and
outcome. If live answers are wanted later, a search source such as Serper
(prepaid, about $1 per 1,000 queries) can feed results into the same input
block without changing the cards.

## Where things live

| Path | Role |
|---|---|
| `Packages/Routing/` | Foundation-only Swift package with two libraries. `Routing`: the formats and their Jev criteria, the System One client, the decision type, the confidence gate, `QueryParser`, the log record and reports. `Answers`: the Gemini streaming client, SSE parsing, and the per-format prompts. Tests run on macOS. |
| `Browser/Router/Router.swift` | The seam: query in, `RouteResult` out. |
| `Browser/Router/JevRouter.swift` | Asks Jev, maps format → `CardPlan`. Also `BrowserSession.makeRouter()` and `makeAnswerClient()`. |
| `Browser/Answers/AnswerSession.swift` | Streams one Gemini answer: the text, the live-data marker check, and the summary for the log. |
| `Browser/Router/LocalRouter.swift` | No-network fallback used when no key is configured. |
| `Browser/Router/DecisionLog.swift` | JSON Lines log of every decision and answer. |
| `Browser/Router/Secrets.swift` | Reads the keys from Info.plist (`TypeSafeAPIKey`, `GeminiAPIKey`). |
| `Browser/Router/CardPlan.swift` | The renderable plans. One enum case per card type. |
| `Browser/Session/BrowserSession.swift` | Owns the single `WebPage` and the `AnswerSession`, runs queries through the router, applies the plan, writes the log. |
| `Browser/Cards/` | One view per card type (`WebCardView`, `AnswerCardView`), plus the Debug-only `RouteDebugRibbon`. |
| `Browser/Shell/` | Custom chrome: bottom address bar and navigation buttons. No system toolbars, so no Liquid Glass. |
| `Browser/Info.plist` | Merged into the generated Info.plist. Holds what Xcode will not take as `INFOPLIST_KEY_` settings: the two API keys and `UIDesignRequiresCompatibility`. |
| `Config/` | xcconfigs. `Debug`/`Release` optionally include the untracked `Secrets.xcconfig`. |

## Modules

Each response format is a module with a stage recorded in code
(`ResponseFormat.stage` in `Packages/Routing`): `routed` (Jev can pick it,
web results stand in), `built` (a real card renders), `verified` (used on a
device and accepted). Today: `web_results` verified; `narrative` and
`one_line` built; `map` and `stock` routed. The Debug ribbon reads
`stock → web (routed, not built)` for a routed pick, and `JevRouter` asserts
the stage and the switch agree. Flip the stage in the same change that adds
the card.

## How it routes

[ROUTING.md](ROUTING.md) is the routing contract, generated from the same
code the app runs: the state Jev reads, every question with its type and
options, the queries each option is meant to catch, the answer shape, what
the app does with each outcome, and then the exact Gemini system
instructions and input block for the answer formats. Regenerate it with:

```
swift run --package-path Packages/Routing report routing > ROUTING.md
```

For what real queries triggered, export `decisions.jsonl` from the Debug
ribbon (AirDrop or Files to the Mac) and run:

```
swift run --package-path Packages/Routing report decisions ~/Downloads/decisions.jsonl
```

That prints picks per format, how often each was acted on or fell back, mean
confidence, recent example queries, errors, the unsure picks with their
runner-up, and an Answers table: per format, how many completed, needed live
data, fell back or stopped early, median first-token and total latency, mean
output tokens, and the token cost for the log.

## Tests

```
swift test --package-path Packages/Routing
```

Covers the Jev request body against TypeSafe's documented shape and option
order, decoding of their example response, the confidence gate, every failure
path falling back to web results, and the address bypass; and for Gemini, the
request body and key order (and that no tool is sent), the per-format prompts
and budgets, the context block, SSE parsing, a canned stream end to end,
error frames, timeouts, and old log lines without answers. Nothing here needs
a simulator.

## Deliberately absent

Tabs, history, bookmarks, content blocking, reader mode, the map and stock
cards, follow-up questions on an answer, live search behind answers (see
"Answer cards" for why Google's grounding was removed), location, the
backend (the Jev and Gemini requests move behind it later, taking the keys
with them).
