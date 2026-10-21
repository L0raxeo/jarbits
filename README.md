# Browser

An iOS browser where a query goes through a router that decides what kind of
card to show. The router is TypeSafe's Jev, a System One model: it picks one of
ten response formats and reports how sure it is. Today there is one card type,
a Google results web view, so every format still renders web results; the
decision is shown in a Debug ribbon and logged on the device so routing quality
is visible before any new card is built. Every future format (summary, map,
stock, images, …) is a new `CardPlan` case, a new SwiftUI card view, and a
provider behind the router.

## Run

1. Open `Browser.xcodeproj` in Xcode 26, pick your team under
   Signing & Capabilities once. Minimum iOS 26.
2. Get a Jev key from https://console.typesafe.ai/keys, then:
   ```
   cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
   ```
   and paste the key. The file is gitignored. Without it the app builds and
   runs with the local router (every query is a Google search) and the ribbon
   says "no key".
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
- The format maps to a plan in `JevRouter.plan(for:query:)`. Every format is
  `.web(google search)` today; this switch is where format two plugs in.
- Each decision is appended to `Application Support/Browser/decisions.jsonl`
  (query, format, confidence, every option's probability, model, latency,
  tokens). Nothing leaves the phone unless you export it from the ribbon.

Model is pinned to `jev-1.13.0`. A routing request is roughly 500 input tokens
at $0.042 per million, so a few hundred searches a month cost under a cent.

## Where things live

| Path | Role |
|---|---|
| `Packages/Routing/` | Foundation-only Swift package: the formats and their Jev criteria, the System One client, the decision type, the confidence gate, `QueryParser`. Tests run on macOS. |
| `Browser/Router/Router.swift` | The seam: query in, `RouteResult` out. |
| `Browser/Router/JevRouter.swift` | Asks Jev, maps format → `CardPlan`, writes the log. Also `BrowserSession.makeRouter()`. |
| `Browser/Router/LocalRouter.swift` | No-network fallback used when no key is configured. |
| `Browser/Router/DecisionLog.swift` | JSON Lines log of every decision. |
| `Browser/Router/Secrets.swift` | Reads the key from Info.plist (`TypeSafeAPIKey`). |
| `Browser/Router/CardPlan.swift` | The renderable plans. One enum case per card type. |
| `Browser/Session/BrowserSession.swift` | Owns the single `WebPage`, runs queries through the router, applies the plan. |
| `Browser/Cards/` | One view per card type, plus the Debug-only `RouteDebugRibbon`. |
| `Browser/Shell/` | Custom chrome: bottom address bar and navigation buttons. No system toolbars, so no Liquid Glass. |
| `Browser/Info.plist` | Merged into the generated Info.plist. Holds the two keys Xcode will not take as `INFOPLIST_KEY_` settings: the API key and `UIDesignRequiresCompatibility`. |
| `Config/` | xcconfigs. `Debug`/`Release` optionally include the untracked `Secrets.xcconfig`. |

## Modules

Each response format is a module with a stage recorded in code
(`ResponseFormat.stage` in `Packages/Routing`): `routed` (Jev can pick it,
web results stand in), `built` (a real card renders), `verified` (used on a
device and accepted). The Debug ribbon reads `stock → web (routed, not built)`
for a routed pick, and `JevRouter` asserts a format marked `built` really has a
card. Flip the stage in the same change that adds the card.

## How it routes

[ROUTING.md](ROUTING.md) is the routing contract, generated from the same
`JevRouting.request` the app sends: the state Jev reads, every question with
its type and options, the queries each option is meant to catch, the answer
shape, and what the app does with each outcome. Regenerate it with:

```
swift run --package-path Packages/Routing report routing > ROUTING.md
```

For what real queries triggered, export `decisions.jsonl` from the Debug
ribbon (AirDrop or Files to the Mac) and run:

```
swift run --package-path Packages/Routing report decisions ~/Downloads/decisions.jsonl
```

That prints picks per format, how often each was acted on or fell back, mean
confidence, recent example queries, errors, and the unsure picks with their
runner-up.

## Tests

```
swift test --package-path Packages/Routing
```

Covers the request body against TypeSafe's documented shape and option order,
decoding of their example response, the confidence gate, every failure path
falling back to web results, and the address bypass. Nothing here needs a
simulator.

## Deliberately absent

Tabs, history, bookmarks, content blocking, reader mode, any card other than
web, the backend (the same Jev request moves behind it later), Serper.
