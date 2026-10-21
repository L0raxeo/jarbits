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
| 1 | `web_results` | A standard page of web search results. The default for broad, vague, navigational or multi-part queries, for a specific website the user names, for pictures or videos, and for anything the other formats do not clearly fit. | A question that asks why or how something happened, a single short fact, a specific place to find, or a ticker. | "best laptops 2026", "news", "python tutorial reddit", "github login", "dune part 3 trailer", "golden retriever puppies" |
| 2 | `narrative` | A written explanation of a few paragraphs. The query asks why or how something happened or works, for the story behind something, or for a judgement that needs context, such as whether somewhere is safe. | Questions answered by one line, such as a time, a date, a number or a yes/no, and queries that only want a price chart. | "at the end of attack on titan why is levi in a wheelchair", "how did simon cowell get famous", "why are highschool students protesting france?", "how is gingivitis healed", "Why is INTR so low?", "Is south africa safe right now" |
| 3 | `map` | A map with a pin. The query names a physical place to locate or get to: an address, a shop, a city, a landmark, directions, or something near me. | Places mentioned only as the subject of a question or a fact, such as whether a country is safe or what time it is there. | "coffee near me", "directions to austin airport", "where is machu picchu", "blue bottle coffee san francisco" |
| 4 | `stock` | A price chart for a security. The query names a ticker, a public company's stock or share price, a market index, or a cryptocurrency price, and wants the price. | Questions about why a price moved or company news, which want an explanation, and currency conversion. | "nasdaq", "AAPL", "tesla stock", "bitcoin price", "s&p 500 today" |
| 5 | `one_line` | A single short answer that fits on one line: a time, a date, a number, a duration, a yes/no, a conversion or a quick fact, including live ones like the weather. | Questions that ask why or how and need a few paragraphs, and anything that wants a price chart. | "what's the time in costa rica", "will it rain today", "how long do cold sores last", "capital of peru", "100 usd to eur" |

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
