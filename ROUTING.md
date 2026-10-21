# Routing contract

Generated from `JevRouting` in `Packages/Routing`. Do not edit by hand; run:

```
swift run --package-path Packages/Routing report routing > ROUTING.md
```

## The request

One `POST https://api.typesafe.ai/v1/systemone` per search, model `jev-1.13.0`, timeout 2500 ms.

State (what Jev reads):

| Field | Value |
|---|---|
| `query` | The text as typed, trimmed. |
| `locale` | The device locale identifier, e.g. `en_US`. |

Before any request: text that parses as an address (`example.com`, `https://…`) loads directly and Jev is not asked.

## The questions

### `format` — type `choice`

Pick one option from the list. Instructions sent with the question:

> Which response format best answers this web search query? Judge the query as typed. If several formats could work, prefer web_results.

Options, in the order Jev sees them (it leans toward the first when unsure):

| # | Option | What it is for | Not for | Queries meant to trigger it |
|---|---|---|---|---|
| 1 | `web_results` | A standard page of web search results. The default for broad, vague, navigational or multi-part queries, and for anything the other formats do not clearly fit. | A single fact, a specific place, a ticker, a flight route, or an explicit request to see pictures or videos. | "best laptops 2026", "news", "how is the economy doing", "python tutorial reddit" |
| 2 | `summary` | A short written explanation. The query asks how or why something works, what something is, or for an overview that takes a few sentences to answer. | Questions with a one-word or one-number answer, and queries that want a list of sites rather than an explanation. | "how does compound interest work", "what is a system one model", "why is the sky blue", "explain the offside rule" |
| 3 | `images` | A grid of pictures. The query wants to see what something looks like, or names a visual subject such as a photo, picture, wallpaper, logo, outfit or colour. | Queries that want to watch a clip, or that mention a place in order to get directions. | "golden retriever puppies", "eiffel tower at night photos", "mid century modern living room", "nike logo" |
| 4 | `map` | A map with a pin. The query names a physical place to locate or get to: an address, a shop, a city, a landmark, directions, or something near me. | Places mentioned only as the subject of a fact, a flight, or a picture. | "coffee near me", "directions to austin airport", "where is machu picchu", "blue bottle coffee san francisco" |
| 5 | `flights` | A list of flights. The query is about flying between places: routes, fares, airlines, departure dates or flight numbers. | Hotels, trains, driving directions, or general travel advice without flying. | "flights to tokyo", "austin to new york flights december", "cheapest flight london paris", "united 1234 status" |
| 6 | `stock` | A price chart for a security. The query names a ticker, a public company's stock or share price, a market index, or a cryptocurrency price. | Company news or history without a price intent, and currency conversion. | "nasdaq", "AAPL", "tesla stock", "bitcoin price", "s&p 500 today" |
| 7 | `one_word` | A single short answer: one word, name, number, date or unit conversion that fully answers the query on its own. | Questions whose answer needs a sentence of explanation, and anything with a live price. | "capital of peru", "how tall is mount everest", "100 usd to eur", "when was the moon landing", "how do you spell necessary" |
| 8 | `presentation` | A sectioned, slide-like overview. The query asks to compare several things, outline or break down a topic, list pros and cons, or give a structured plan. | A quick explanation that fits in a paragraph, or a single fact. | "compare iphone vs pixel", "pros and cons of electric cars", "outline of world war 2", "7 day japan itinerary" |
| 9 | `videos` | A list of videos. The query wants to watch something: a trailer, music video, tutorial, highlights, a clip or anything on youtube. | Queries that want still pictures or a written explanation. | "dune part 3 trailer", "how to tie a tie video", "lakers highlights last night", "lofi hip hop youtube" |
| 10 | `links` | One specific website or page the user names and wants to open, such as a brand, product page, login page or documentation site, even without a full address. | A topic with many possible sources, or a company named for its stock price. | "github login", "apple developer documentation", "nytimes", "stripe docs webhooks" |

Answer: `choice` (one option name), `probabilities` (one per option), `confidence` (0–1).

## What comes back

```json
{ "model": "jev-1.13.0", "answers": { "format": { "type": "choice", "choice": "stock", "confidence": 0.91, "probabilities": { "web_results": 0.05, "stock": 0.92, … } } }, "usage": { "input_tokens": 512, "output_tokens": 9 } }
```

- `choice`: the option with the highest probability.
- `probabilities`: one per option, summing to 1.
- `confidence`: `(p_max − 1/n) / (1 − 1/n)`; 0 for a flat spread, 1 for a single peak. Only the top probability matters.

## What the app does with it

| Outcome | Shown | Logged as |
|---|---|---|
| Address typed | That page | `directURL` |
| No API key configured | Web results | `noKey` |
| Request failed or timed out | Web results | `error(reason)` |
| `confidence` below 0.5 | Web results | `confidenceFallback` (the pick is kept as `suggested`) |
| `confidence` at or above 0.5 | The chosen format's card, or web results while that module is only `routed` | `jev` |

Every outcome is appended to `decisions.jsonl` on the device with the query, the pick, every option's probability, confidence, model, latency and input tokens. Summarise an exported log with `swift run --package-path Packages/Routing report decisions <file>`.

## Question types not used yet

- **noul**: a yes/no with a probability, no confidence field. Candidate use: "does this query name a place?" as a companion to the format Choice.
- **score**: a position on an ordered scale with confidence. Candidate use: how much the query needs a written explanation.

Adding a question is one entry in `JevRouting.request`; this file and `RoutingTests` pick it up.
