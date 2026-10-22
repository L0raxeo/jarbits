# Browser

An iOS browser where a query goes through a router that decides what kind of
card to show. The router is TypeSafe's Jev, a System One model: it picks one of
six response formats and reports how sure it is. Three providers exist
behind it: a Google results web view (`web_results`), Gemini answers for
`narrative` and `one_line`, and a Wikipedia picture for `image`.

The screen is white with a purple gradient orb above the middle that
breathes, and a keyboard hint at the bottom. Tapping the orb or the hint, or
swiping up on the hint, raises the keyboard and stretches the orb into a
capsule you type in. Return sends the query and the orb becomes a short line
with one wave sliding along it, for as long as the query is being processed:
routing, then either the Google page committing or Gemini's first text. Then
the line fades out as the result fades in: a web page filling the screen, or
the answer in dark text where the line was, growing as it streams. A page
starts below the status bar and frosts it when it scrolls under. Over a
result a capsule at the foot shows the query, shrinks while you scroll down
and grows on the way up; tapping it raises the keyboard and the capsule
rises with it, morphing into the field, with the result still behind; on a
web result the field holds the query, selected, so typing replaces it.
Return sends the follow-up as a new query, routed like any other. Swiping down on an answer, or tapping the line while it
waves, returns to the circle.

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
`BrowserSession.stage` (`idle`, `routing`, `loading`, `ready`) is what the
home screen reads to show the line or the result; a page counts as ready
when WebKit commits its first content (or after 8 s), an answer when its
first text arrives.

`JevRouter` (used when a key is configured):
- An address (`example.com`, `https://…`) loads directly; Jev is not asked.
- Anything else is sent as `{ query, locale }` with one Choice question over
  `ResponseFormat.allCases`. Options reach Jev in declaration order, with
  `web_results` first, because Jev leans toward the first option when unsure.
- Confidence below `JevRouting.confidenceFloor` (0.5) falls back to
  `web_results`. Any error or a 2.5 s timeout does the same.
- The same request carries a second, yes/no question (`recent`): would the
  right answer depend on something that may have changed in the last two
  years, such as whether a person is alive, who holds an office, or a new
  phrase? A `narrative` or `one_line` pick with that probability at or
  above `JevRouting.recencyThreshold` (0.5) is shown as web results and
  logged as `recencyFallback`, because the model's knowledge is months old.
- The format maps to a plan in `JevRouter.plan(for:query:)`: `web_results`,
  `map` and `stock` load a Google results page; `narrative` and `one_line`
  become `.answer(format:query:)`; `image` becomes `.image(query:)`.
- Each decision is appended to `Application Support/Browser/decisions.jsonl`
  (query, format, confidence, every option's probability, model, latency,
  tokens; for answer plans, the answer summary too). Nothing leaves the phone
  unless you export it from the ribbon.

Model is pinned to `jev-1.13.0`. A routing request is roughly 1,200 input
tokens at $0.042 per million, so a few hundred searches a month cost under a
cent. To see what Jev makes of one query from the Mac (one real call):

```
TYPESAFE_API_KEY=… swift run --package-path Packages/Routing report route "some query"
```

It prints the pick, the confidence and every option's probability.

## Answer cards

`AnswerSession` streams one answer at a time from Gemini `gemini-3.1-flash-lite`
(Interactions API, thinking `minimal`, `store: false`, no tools). The system
instruction is the per-format rule set in `AnswerPrompt`
(`Packages/Routing/Sources/Answers`): narrative opens with the immediate
answer and keeps to the scope the query's wording implies, with no target
length; one-line gives the answer itself in at most twelve words, never a
sentence restating the question. The input carries the
query plus the device date, time and zone and the locale, so "today", "now"
and "the time in X" work without any lookup, and the model's knowledge
cutoff (January 2025, pinned in `AnswerPrompt.knowledgeCutoff`) with the
number of months since, so it knows what may have changed.

The model has no web access, on purpose. Grounding with Google Search was
built and removed: Google's terms require their Search Suggestions bar,
unmodified and full width, under every grounded answer, and it cannot be
restyled. So:
- a one-line question that needs live data (today's weather, a price, a
  rate, a score, the latest news) makes the model reply with the marker
  `NEEDS_LIVE_DATA`, which the app never shows; it loads the Google results
  page for the query instead and logs `needsLiveData`;
- a one-line question whose answer may have changed since the cutoff, such
  as whether someone is alive or who holds a role, gets the same marker;
- a narrative question about anything that can change over that gap gets
  one plain sentence saying the answer is as of January 2025 and may be out
  of date, then what the model knew; the Web results link is under every
  answer. Most such queries never reach the model: the `recent` question at
  Jev sends them to web results first.

Answers carry four levels of emphasis, written by the model as markers that
are not Markdown and parsed by `AnswerMarkup` in the package: `==…==` for
the one thing to take away (purple behind white text, at most once per
answer), `**…**` for the facts that directly answer the question, `__…__`
for a condition or caveat that changes the answer, and `_…_` for a name or
term being introduced. One-line answers may only highlight. An opener with
no closer styles to the end of the text, so emphasis shows as it streams,
and a half-arrived marker is held back rather than flashed. A highlight
with whitespace or nothing on both sides grows one space each way, so the
box breathes; one touching punctuation or a letter stays tight.

No first byte in 10 s, or any failure before text arrives, falls back to web
results; a failure after some text keeps the text and says it stopped early.

Cost, from Google's pricing page on 2026-10-21 (pinned in `GeminiPricing`):
$0.25 per million input tokens, $1.50 per million output tokens including
thinking, so about $0.0005 per narrative answer and nothing per search,
because there are none. The ribbon shows each answer's tokens, cost and
outcome. If live answers are wanted later, a search source such as Serper
(prepaid, about $1 per 1,000 queries) can feed results into the same input
block without changing the cards.

## Image cards

`image` is for one specific, named thing with a definitive look: a flag, a
logo, a landmark, a painting, a person, a species. `ImageSession` asks
Wikipedia, free and without a key: the REST page search turns the query
into article candidates, the page summary of the first three with a
thumbnail gives each article's lead image, and disambiguation pages and
articles without an image are skipped. The first picture is downloaded and
decoded before the card fades in, so the wave line lasts until it is on
screen; the others are alternates, up to two, shown as thumbnails under the
title and description with a "Wikipedia" link to the article (which carries
the image's licence and author) and the usual "Web results". Nothing found,
or nothing within 10 s, falls back to web results. The log records the
article, the candidate count, the latency and the outcome; if misses turn
out to be common, the upgrade is to let Gemini turn the query into an
article title before searching.

## Where things live

| Path | Role |
|---|---|
| `Packages/Routing/` | Foundation-only Swift package with three libraries. `Routing`: the formats and their Jev criteria, the System One client, the decision type, the confidence and recency gates, `QueryParser`, the log record and reports. `Answers`: the Gemini streaming client, SSE parsing, the per-format prompts and the emphasis markup. `Images`: the Wikipedia search and summary client. Tests run on macOS. |
| `Browser/Router/Router.swift` | The seam: query in, `RouteResult` out. |
| `Browser/Router/JevRouter.swift` | Asks Jev, maps format → `CardPlan`. Also `BrowserSession.makeRouter()` and `makeAnswerClient()`. |
| `Browser/Answers/AnswerSession.swift` | Streams one Gemini answer: the text, the live-data marker check, and the summary for the log. |
| `Browser/Images/ImageSession.swift` | Loads one Wikipedia picture (and its alternates) for an image plan, and the summary for the log. |
| `Browser/Router/LocalRouter.swift` | No-network fallback used when no key is configured. |
| `Browser/Router/DecisionLog.swift` | JSON Lines log of every decision and answer. |
| `Browser/Router/Secrets.swift` | Reads the keys from Info.plist (`TypeSafeAPIKey`, `GeminiAPIKey`). |
| `Browser/Router/CardPlan.swift` | The renderable plans. One enum case per card type. |
| `Browser/Session/BrowserSession.swift` | Owns the single `WebPage` and the `AnswerSession`, runs queries through the router, applies the plan, writes the log. |
| `Browser/Home/` | The screen: `HomeView` (white background, focus state, the stage-driven cross-fade), `BreathingOrb` (the mesh-gradient circle that morphs into the capsule field and the wave line), `KeyboardHint` (the nodding chevron over a keyboard icon), `ResultView` (the web page or the answer text with its "Web results" link, under a frosted status bar) `QueryCapsule` (Safari's minimised bar: the query at the foot of a result, which becomes the follow-up field above the keyboard) and `QueryField` (the text field the orb and the capsule share). No system toolbars, so no Liquid Glass. |
| `Browser/Info.plist` | Merged into the generated Info.plist. Holds what Xcode will not take as `INFOPLIST_KEY_` settings: the two API keys and `UIDesignRequiresCompatibility`. Light mode is forced by `INFOPLIST_KEY_UIUserInterfaceStyle` in the project and `preferredColorScheme(.light)` at the root. |
| `Config/` | xcconfigs. `Debug`/`Release` optionally include the untracked `Secrets.xcconfig`. |

## Modules

Each response format is a module with a stage recorded in code
(`ResponseFormat.stage` in `Packages/Routing`): `routed` (Jev can pick it,
web results stand in), `built` (a real card renders), `verified` (used on a
device and accepted). Today: `web_results` verified; `narrative`,
`one_line` and `image` built; `map` and `stock` routed. A routed pick shows web
results and is logged as the pick it was, and `JevRouter` asserts the stage
and the switch agree. Flip the stage in the same change that adds the card.

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

Dark mode, Markdown in answers, the Debug ribbon (the log still records every decision; summarise
it with the report CLI), tabs, history, bookmarks, content blocking, reader
mode, the map and stock cards, follow-up questions on an answer, live search behind answers (see
"Answer cards" for why Google's grounding was removed), location, the
backend (the Jev and Gemini requests move behind it later, taking the keys
with them).
