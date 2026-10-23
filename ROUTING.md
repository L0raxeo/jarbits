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
| `previous_queries`, `previous_answer` | Only while a narrative answer is on screen and the query was typed over it: every query of that conversation, oldest first, and the last answer cut to 1500 characters. The format question then reads differently and a third question is asked; see "When a narrative is on screen". |

Before any request: text that parses as an address (`example.com`, `https://…`) loads directly, and a query the device can answer itself becomes a card at once; Jev is not asked either way.

## Answered on the device

The time in a named place needs no model. A query that is exactly one opener, a place and at most one trailer (case, accents and punctuation aside) is answered from the device clock when the place is a country, a US state or a city in the device's zone database; otherwise it goes on to Jev like any other query. English only.

- Openers before a place: "what time is it in", "what's the time in", "what is the time in", "what time is in", "what time in", "current time in", "local time in", "the time in", "time now in", "time in"
- Whole queries meaning the time here: "what time is it", "what's the time", "what is the time", "current time", "local time", "the time", "time now"
- Trailers, at the end or between "is it" and "in": "at the moment", "right now", "currently", "now", "today"

Shown as `==7:56 PM==`, with `tomorrow` or `yesterday` when the date there differs, and `in Mexico City` when the place spans zones. Logged as `local("time")` with none of the Jev fields.

## The questions

### `format` — type `choice`

Pick one option from the list. Instructions sent with the question:

> Which response format best answers this web search query? Judge the query as typed. If several formats could work, prefer web_results.

Options, in the order Jev sees them (it leans toward the first when unsure):

| # | Option | What it is for | Not for | Queries meant to trigger it |
|---|---|---|---|---|
| 1 | `web_results` | A standard page of web search results. The default for broad, vague, navigational or multi-part queries, for a specific website the user names, for browsing many pictures or videos, and for anything the other formats do not clearly fit. | A question that asks why or how something happened, a single short fact, a specific place to find, a ticker, or the bare name of one famous thing the user wants to see. | "best laptops 2026", "news", "python tutorial reddit", "github login", "dune part 3 trailer", "golden retriever puppies" |
| 2 | `narrative` | A written explanation. The query asks why or how something happened or works, what something is or means (a definition, or the expansion of an acronym or term within a field, which needs the full name and a sentence or two of context), for the story behind something, where a phrase, slogan, name or meme came from, or for a judgement that needs context, such as whether somewhere is safe. | Questions answered by one line, such as a time, a date, a number or a yes/no, and queries that only want a price chart. | "at the end of attack on titan why is levi in a wheelchair", "how did simon cowell get famous", "why are highschool students protesting france?", "how is gingivitis healed", "Why is INTR so low?", "Is south africa safe right now", "where did the phrase ok boomer come from", "whats isi in ipe", "what does gdp mean", "define hegemony" |
| 3 | `map` | A map with a pin. The query names a physical place to locate or get to: an address, a shop, a city, a landmark, directions, or something near me. | Places mentioned only as the subject of a question or a fact, such as whether a country is safe or what time it is there. | "coffee near me", "directions to austin airport", "where is machu picchu", "blue bottle coffee san francisco" |
| 4 | `stock` | A price chart for a security. The query names a ticker, a public company's stock or share price, a market index, or a cryptocurrency price, and wants the price. | Questions about why a price moved or company news, which want an explanation, and currency conversion. | "nasdaq", "AAPL", "tesla stock", "bitcoin price", "s&p 500 today" |
| 5 | `one_line` | A single short answer that fits on one line: a time, a date, a number, a duration, a yes/no, a conversion, or a quick fact that is itself a name, number or date, including live ones like the weather. | Questions that ask why or how and need a few paragraphs; definitions and what-is questions, which need the full name and some context rather than one value; and anything that wants a price chart. | "what's the time in costa rica", "will it rain today", "how long do cold sores last", "capital of peru", "100 usd to eur" |
| 6 | `recall` | Something the user saw in this app before and wants back: a page they were on, an answer they got, a list they made. The query points at the past ("that", "again", "my", "remember", "pull up", "where's", "go back to") instead of asking something new. | A new question or search that merely contains such a word, like a film title or a package delivery; anything the user has not seen in this app. | "where's my grocery list", "remember that convo on the dyson pencilvac", "pull up that youtube page from earlier", "pull up the video I was watching about muse", "that thing about gingivitis again", "go back to the reddit thread" |
| 7 | `image` | A single picture of one specific, named thing with a definitive look: a flag, a logo or emblem, a landmark or monument, a painting, a person, a product, a species, a chemical structure. The bare name of such a thing, with no other words, means the user wants to see it, not read about it. | Browsing many pictures of a category, mood or idea, which wants web results; and questions about why something looks the way it does, which want an explanation. | "dominican flag", "eiffel tower", "starry night painting", "nvidia logo", "what does a capybara look like", "mona lisa", "aston martin db5" |

Answer: `choice` (one option name), `probabilities` (one per option), `confidence` (0–1).

### `recent` — type `noul`

A yes/no question answered with the probability of yes. Instructions sent with the question:

> Would the correct answer to this query depend on something that may have changed in the last two years? For example whether a person is alive, who currently holds an office, title or job, a record, a price, a recent event or its aftermath, or a phrase, slogan or meme that became known recently.

| Means | Description |
|---|---|
| yes | The right answer could have changed since early 2025: it depends on someone's current status, the current holder of a position, a recent or ongoing event, or a new phrase. |
| no | A settled fact, history, how something works, a definition, a conversion, a place, a date or time, or anything else that does not go stale. |

Answer: `noul`, the probability of yes (0–1). No confidence field.

## When a narrative is on screen

A follow-up typed over a narrative answer is read as the conversation makes it. The `format` question's instructions become:

> Which response format best answers this web search query? The state carries the conversation so far: the earlier queries and the answer on screen. Judge the query as that conversation makes it, not as typed on its own. A reply, a reaction or a question that leans on the answer, however short, wants narrative, the format of the answer it replies to. Pick another format only when the query asks for the kind of thing that format shows: map, stock, recall, image, each described below; or web_results for a page to browse.

and a third question is asked:

### `continues` — type `noul`

A yes/no question answered with the probability of yes. Instructions sent with the question:

> The state carries the previous query and the answer the user is looking at. Is this query a continuation of that exchange: a reply, a reaction, a request to go on or to clarify, or a question that only makes sense given that answer?

| Means | Description |
|---|---|
| yes | The query answers, reacts to, questions or builds on the previous answer, or would be incomplete without it, however short: "why?", "can I use water", "and with oat milk", "tell me more", "is that true for cats too". |
| no | A new question that stands on its own, even about a nearby topic: it would mean the same thing with no previous answer. |

Answer: `noul`, the probability of yes (0–1). No confidence field.

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
| The time in a named place (see above) | A one-line card computed on the device | `local("time")` |
| Address typed | That page | `directURL` |
| No API key configured | Web results | `noKey` |
| Request failed or timed out | Web results | `error(reason)` |
| `confidence` below 0.5 | Web results | `confidenceFallback` (the pick is kept as `suggested`) |
| `confidence` at or above 0.5 and `recent` below 0.5 | The chosen format's card; web results while that module is only `routed` (today: `map`, `stock`) | `jev` |
| `narrative` or `one_line` picked with confidence, but `recent` at or above 0.5 | Web results (the model's knowledge is months old; see the answer prompts) | `recencyFallback` (the pick is kept as `suggested`) |
| Over a narrative on screen, `continues` at or above 0.5 and a card format (`map`, `stock`, `recall`, `image`) picked with confidence | That card | `jev` |
| Over a narrative on screen, `continues` at or above 0.5 and any other pick, sure or not, with `recent` below 0.5 | The narrative on screen grows: the query as a line, then a reply written with the earlier turns in view | `continuation` (the pick is kept as `suggested`) |

Every outcome is appended to `decisions.jsonl` on the device with the query, the pick, every option's probability, confidence, the recency probability, model, latency and input tokens. Summarise an exported log with `swift run --package-path Packages/Routing report decisions <file>`.

## Question types not used yet

- **score**: a position on an ordered scale with confidence. Candidate use: how much the query needs a written explanation.

Adding a question is one entry in `JevRouting.request`; this file and `RoutingTests` pick it up. The yes/no `recent` question above is a noul.

## After routing: Gemini answers

`narrative` and `one_line` are answered by Gemini `gemini-3.1-flash-lite` through the Interactions API, thinking `minimal`, `store: false`, no tools. One streamed request per query. The model answers from what it knows; it has no web access.

Grounding with Google Search was tried and dropped: Google's terms require their Search Suggestions bar, unmodified, under every grounded answer. Live-data questions go to web results instead (below).

Prices pinned in `GeminiPricing`: $0.25 per 1M input tokens, $1.5 per 1M output tokens (thinking included).

### Input (both formats)

```
Query: <query>

Context (use for "today" and "now"; do not repeat it unless the query asks about it):
- Date and time: Wednesday 21 October 2026, 11:26 (America/Chicago)
- Your knowledge ends around January 2025, about 21 months before this date.
- Locale: en_US
```

### Input for a narrative that continues

When Jev judged the query a continuation of the narrative on screen (`continuation` in the decision), `input` is a list of `user_input` and `model_output` steps instead of a string, Google's stateless shape; `store` stays false. Oldest first: `{"type": "user_input", "content": [{"type": "text", "text": "<earlier query>"}]}`, `{"type": "model_output", "content": [{"type": "text", "text": "<earlier answer, markup included>"}]}`, and so on, then one last `user_input` step holding the block above. At most 6 earlier turns are sent.

### `narrative` — system instruction, max 800 output tokens

```
You answer web search queries for a browser. The user typed a query and expects a short written answer.

Rules:
- Open with the most immediate, simple answer in the first line or two. Everything after that supports it.
- Match the scope to the wording of the query. "What is X" wants what X is: the full name and a sentence or two of meaning, not how it works, examples or history. "How does X work" wants how it works and nothing adjacent: not its background, its context in the field, or why it rose or declined. Add nothing the query did not ask for: no related facts, caveats or tips.
- There is no target length. Stop when the question is answered. Never pad, ramble, or add a closing thought. Plain prose in short paragraphs; no headings, bullet points, numbered lists, tables, emoji, or Markdown other than the emphasis markers below.
- No preamble and no closing line. Start with the answer. Do not offer further help or suggest follow-up questions.
- Earlier turns of this conversation may come before the query, oldest first; the context block applies to all of them. Then the query is a reply to your last answer: resolve "it", "that", "why" and the like against the conversation, do not repeat what you already said, and answer only the new question.
- Your knowledge ends around January 2025 and you have no access to the web; the context says how long ago that was. Answer with what you knew then, stated as plain fact. Never say when your knowledge ends, that the answer may be out of date, or that you cannot check: the browser puts a web link under every answer. Do not invent developments after that date.
- Use the context block for "today" and "now". Do not mention the context unless the query is about it.
- If the question rests on a false premise, say so in one sentence, then answer the nearest true question.
- Write in the language of the query.

Emphasis. Mark it with exactly these markers and nothing else:
- ==…== for the single most important thing the user should take away, at most once in the whole answer (each answer in a conversation has its own).
- **…** for the facts that directly answer the question, a few at most.
- __…__ for a condition or caveat that changes the answer.
- _…_ for a name, title or term you are introducing.
Most sentences have no markers. Never put a marker around a whole sentence or paragraph.
```

### `one_line` — system instruction, max 160 output tokens

```
You answer web search queries for a browser with a single line.

Rules:
- Reply with one line only: a number, a word, a name, a date, a time, or a short clause. Examples: "24 days", "Lima", "8:14 PM", "About 92 euros".
- Give the answer itself, never a sentence that restates the question: "6:21 PM", not "The current time in Costa Rica is 6:21 PM".
- Never more than twelve words. No explanation, no second sentence, no preamble, no trailing period.
- Your knowledge ends around January 2025 and you have no access to the web. If the question needs live data, such as today's weather, a current price or exchange rate, a live score, or the latest news, or if the answer may have changed since January 2025, such as whether a person is alive or who currently holds a role, reply with exactly: NEEDS_LIVE_DATA
- You do know the current date and time from the context block. Compute dates, countdowns and the time in other places from it.
- If the honest answer is a range or depends on something, give the typical value in the line, such as "Usually 7 to 10 days".
- If the question cannot be answered in one line, answer its most direct version in one line anyway.
- Answer in the language of the query.
- You may wrap the key word or number in ==…==, as in "About ==92== euros". No other markers, no Markdown.
```

### What comes back

Server-sent events: `step.delta` text pieces, then `interaction.completed` with usage (`total_input_tokens`, `total_output_tokens`, `total_thought_tokens`).

| Outcome | Shown | Logged as |
|---|---|---|
| Streamed to the end | The answer card | `answer.outcome = completed` |
| `one_line` replied `NEEDS_LIVE_DATA` | Web results for the query | `needsLiveData` |
| Failed after some text | What arrived, with a note | `partial(reason)` |
| Failed before any text, or no first byte in 10 s, or over 30 s in all | Web results for the query | `fellBackToWeb(reason)` |
| No Gemini key configured | Web results; Jev's pick is still logged | the decision alone |

The answer summary (model, tokens, first-token and total latency, outcome) is appended to the same `decisions.jsonl` line as the routing decision.

## After routing: Wikipedia images

An `image` pick is filled from Wikipedia, free and without a key, by `ImageSearch` in `Packages/Routing/Sources/Images`. Every request sends `User-Agent: Browser/0.1 (com.lorcancheng.browser)`.

1. `GET https://en.wikipedia.org/w/rest.php/v1/search/page?q=<query>&limit=5`: article candidates in rank order. Hits without a `thumbnail` are dropped; the first 3 remain.
2. `GET https://en.wikipedia.org/api/rest_v1/page/summary/<key>` for each, in parallel: `type` must be `standard` (disambiguation pages are dropped) and `originalimage` must exist. An SVG comes back as a PNG render of about 960 px.
3. The first remaining article's picture is downloaded and decoded before the card is shown; the others, up to two, are alternates.

No candidate with a picture, any failure, or 6 s without a reply per step falls back to web results.

| Outcome | Shown | Logged as |
|---|---|---|
| A picture decoded | The image card, with alternates when there are any | `shown(alternates:)` with the article, candidate count and latency |
| Nothing with a picture, or an error | Web results | `fellBackToWeb(reason)` |

The article's page carries the image's licence and author; the card links to it.
