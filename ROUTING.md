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
| `confidence` at or above 0.5 | The chosen format's card; web results while that module is only `routed` (today: `map`, `stock`) | `jev` |

Every outcome is appended to `decisions.jsonl` on the device with the query, the pick, every option's probability, confidence, model, latency and input tokens. Summarise an exported log with `swift run --package-path Packages/Routing report decisions <file>`.

## Question types not used yet

- **noul**: a yes/no with a probability, no confidence field. Candidate use: "does this query name a place?" as a companion to the format Choice.
- **score**: a position on an ordered scale with confidence. Candidate use: how much the query needs a written explanation.

Adding a question is one entry in `JevRouting.request`; this file and `RoutingTests` pick it up.

## After routing: Gemini answers

`narrative` and `one_line` are answered by Gemini `gemini-3.1-flash-lite` through the Interactions API with Grounding with Google Search on, thinking `minimal`, `store: false`. One streamed request per query. The model decides per request whether to search; the system instruction tells it when.

Prices pinned in `GeminiPricing`: $0.25 per 1M input tokens, $1.5 per 1M output tokens (thinking included), 5000 Google searches a month free, then $14 per 1,000.

### Input (both formats)

```
Query: <query>

Context (use for "today", "now" and "here"; do not repeat it unless the query asks about it):
- Date and time: Wednesday 21 October 2026, 11:26 (America/Chicago)
- Locale: en_US
- Approximate location: Austin, Texas, United States
```

Location is "City, Region, Country" from reduced-accuracy Core Location, only when the user allowed it; the line is left out otherwise.

### `narrative` — system instruction, max 800 output tokens

```
You answer web search queries for a browser. The user typed a query and expects a short written answer.

Rules:
- Answer only the question that was asked. Do not add background, related facts, caveats, tips, or anything that is not a direct part of the answer.
- Write two to four short paragraphs of plain prose. No headings, bullet points, numbered lists, bold text, tables, or emoji.
- No preamble and no closing line. Start with the answer. Do not offer further help or suggest follow-up questions.
- Use Google Search when the question concerns anything recent or still changing: news, events, prices, safety, people in the news, or anything with "now", "today", "currently", "latest" or a recent year. Answer from what you find. Do not search for settled facts you already know.
- Use the context block for "today", "now" and "here". Do not mention the context unless the query is about it.
- If the question rests on a false premise, say so in one sentence, then answer the nearest true question.
- Write in the language of the query.
```

### `one_line` — system instruction, max 160 output tokens

```
You answer web search queries for a browser with a single line.

Rules:
- Reply with one line only: a number, a word, a name, a date, a time, or a short clause. Examples: "24 days", "Lima", "Yes, rain is expected this afternoon", "8:14 PM", "About 92 euros".
- Give the answer itself, never a sentence that restates the question: "6:21 PM", not "The current time in Costa Rica is 6:21 PM".
- Never more than twelve words. No explanation, no second sentence, no preamble, no trailing period.
- For current conditions, use Google Search first and answer from the result: weather, time, exchange rates, prices, scores, who currently holds a role, or anything with "now" or "today".
- Use the context block for "today", "now" and "here": the current date and time with its time zone, and the user's approximate location.
- If the honest answer is a range or depends on something, give the typical value in the line, such as "Usually 7 to 10 days".
- If the question cannot be answered in one line, answer its most direct version in one line anyway.
- Answer in the language of the query.
```

### What comes back

Server-sent events: `google_search_call` steps (the queries run), `google_search_result` steps (Google's Search Suggestions snippet, which the terms require showing with the answer, unmodified), `step.delta` text pieces, `url_citation` annotations on the final text, then `interaction.completed` with usage (`total_input_tokens`, `total_output_tokens`, `total_thought_tokens`, `grounding_tool_count`).

| Outcome | Shown | Logged as |
|---|---|---|
| Streamed to the end | The answer card with sources and Search Suggestions | `answer.outcome = completed` |
| Failed after some text | What arrived, with a note | `partial(reason)` |
| Failed before any text, or no first byte in 10 s, or over 30 s in all | Web results for the query | `fellBackToWeb(reason)` |
| No Gemini key configured | Web results; Jev's pick is still logged | the decision alone |

The answer summary (model, searches run, tokens, first-token and total latency, outcome) is appended to the same `decisions.jsonl` line as the routing decision.
