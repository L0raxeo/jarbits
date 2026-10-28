# Engine contract

Generated from `EngineRequest` and the instinct registry (`InstinctSpec`) in `Packages/Engine`. Do not edit by hand; run:

```
swift run --package-path Packages/Engine report engine > ENGINE.md
```

## The request

One `POST https://api.typesafe.ai/v1/systemone` per query, model `jev-1.13.0`, timeout 2500 ms. Every question below goes in that one request and is answered in parallel: which instinct fits, whether the answer may have gone stale, how a recall ask reads, whether the query states a lasting fact about the user, which earlier exchanges the query depends on, and how much working out it needs.

State (what Jev reads):

| Field | Value |
|---|---|
| `query` | The text as typed, trimmed. |
| `locale` | The device locale identifier, e.g. `en_US`. |
| `exchanges` | Only after the first query of a session: the newest 20 earlier exchanges, oldest first, each the query and what it got. Every exchange has `query` and `kind` (`answer`, `page`, `search`, `picture`, `recall`, `site`); an answer carries its `text` whole, a page its `title`, `host` and `address`, a search the `text` in its box, a picture the `text` of its subject. The format question then reads differently and one more question is asked per exchange; see "When earlier exchanges are in the state". |
| `opened_site_name`, `opened_site_host` | Only while a site this app opened by name is on screen: the name asked for and the host opened. One more question is asked; see "When a site is on screen". |

Before any request: text that parses as an address (`example.com`, `https://…`) loads as typed, with no reading and no Jev. Nothing else decides a query before Jev: no word list, no rule. Every other query goes to Jev, with the reading beside it (see "The reading beside Jev"), and the instinct Jev picked does the rest.

## The questions

The pick (`instinct`), then the questions the instincts add (`recent` from the two answered ones, the `recall_*` questions from recall, `remember` from remember), then the reasoning score. With earlier exchanges in the state the relevance questions come between.

### `instinct` — type `choice`

Pick one option from the list. Instructions sent with the question:

> Which response format best answers this web search query? Judge the query as typed. If several formats could work, prefer web_results.

Options, in the order Jev sees them (it leans toward the first when unsure):

| # | Option | What it is for | Not for | Queries meant to trigger it |
|---|---|---|---|---|
| 1 | `web_results` | A standard page of web search results. The default for broad, vague or multi-part queries, for a search for something on a site, for browsing many pictures, and for anything the other formats do not clearly fit. A bare topic with no ask, such as "chocolate milk" or "quantum computing", is one of these: the user wants the general spread, not one answer. So is a query that asks for the search itself, such as "google steve jobs" or "look up flights to lima", whatever the topic. | A question that asks why or how something happened, a single short fact, a specific place to find, a ticker, a request to open a website by its name, the bare name of one specific thing with a definitive look, which wants a picture, or videos to watch, which want video results. | "best laptops 2026", "news", "chocolate milk", "google steve jobs", "python tutorial reddit", "zillow homes in austin", "quantum computing", "golden retriever puppies" |
| 2 | `narrative` | A written explanation. The query asks why or how something happened or works, what something is or means (a definition, or the expansion of an acronym or term within a field, which needs the full name and a sentence or two of context), for the story behind something, where a phrase, slogan, name or meme came from, or for a judgement that needs context, such as whether somewhere is safe. Also any question handed to the AI by name ("ask AI what GDP means", "ask the AI about Dyson alternatives"): the person wants the model's own answer, whatever the question. | Questions answered by one line, such as a time, a date, a number or a yes/no, and queries that only want a price chart. | "at the end of attack on titan why is levi in a wheelchair", "ask ai about dyson alternatives", "how did simon cowell get famous", "why are highschool students protesting france?", "how is gingivitis healed", "Why is INTR so low?", "Is south africa safe right now", "where did the phrase ok boomer come from", "whats isi in ipe", "what does gdp mean", "define hegemony" |
| 3 | `map` | A map with a pin. The query names a physical place to locate or get to: an address, a shop, a city, a landmark, directions, or something near me. | Places mentioned only as the subject of a question or a fact, such as whether a country is safe or what time it is there. | "coffee near me", "directions to austin airport", "where is machu picchu", "blue bottle coffee san francisco" |
| 4 | `stock` | A price chart for a security. The query names a ticker, a public company's stock or share price, a market index, or a cryptocurrency price, and wants the price. | Questions about why a price moved or company news, which want an explanation, and currency conversion. | "nasdaq", "AAPL", "tesla stock", "bitcoin price", "s&p 500 today" |
| 5 | `one_line` | A single short answer that fits on one line: a time, a date, a number, a duration, a yes/no, a conversion, or a quick fact that is itself a name, number or date, including live ones like the weather. | The time or date right now, here or somewhere, which is time; questions that ask why or how and need a few paragraphs; definitions and what-is questions, which need the full name and some context rather than one value; and anything that wants a price chart. | "will it rain today", "how long do cold sores last", "capital of peru", "100 usd to eur" |
| 6 | `recall` | Something the user saw in this app before and wants back: a page they were on, an answer they got, a list they made. The query points at the past ("that", "again", "my", "remember", "pull up", "where's", "go back to") instead of asking something new. | A new question or search that merely contains such a word, like a film title or a package delivery; opening a website by its name with no pointer at the past ("pull up zillow"), which is site; anything the user has not seen in this app. | "where's my grocery list", "remember that convo on the dyson pencilvac", "pull up that youtube page from earlier", "pull up the video I was watching about muse", "that thing about gingivitis again", "go back to the reddit thread" |
| 7 | `image` | A single picture of one specific, named thing with a definitive look: a flag, a logo or emblem, a landmark or monument, a painting, a person, a product, a species, a chemical structure. The bare name of such a thing, with no other words, means the user wants to see it, not read about it. | Browsing many pictures of a category, mood or idea, which wants web results; and questions about why something looks the way it does, which want an explanation. | "dominican flag", "eiffel tower", "starry night painting", "nvidia logo", "what does a capybara look like", "mona lisa", "aston martin db5" |
| 8 | `site` | Open a website or app by its name. The query is a go-to, open, pull-up or take-me-to verb and a site's name, or the bare name of a well-known site with nothing else; the user wants the site itself, not results about it. Over a site this app opened by name, a complaint that it is the wrong one is a request for the same name again. | A search for something on a site ("zillow homes in austin"), a question about a site, and a page the user saw in this app before ("that youtube page from earlier", which is recall). | "go to youtube", "pull up zillow", "open insta", "take me to airbnb", "launch netflix", "reddit" |
| 9 | `video` | A page of videos to watch. The query asks for videos, clips, highlights, a trailer, a music video, a performance, a tutorial to watch, or to watch or play something: the user wants to press play, not read. | A video the user saw in this app before ("the video I was watching"), which is recall; a website or app by its name ("open youtube"), which is site; one still picture of a thing, which is image; and a topic that merely has videos about it, with no ask to watch, which is web results. | "videos of pele", "pele highlights", "dune part 3 trailer", "watch the super bowl halftime show", "show me cat videos", "how to tie a tie video", "lofi music video" |
| 10 | `remember` | The user asks the app to keep something in mind about them for later, or tells it something lasting about themselves with nothing else asked: a preference, an allergy, a name, where they live. The words are a remember, a keep-in-mind, a don't-forget, a note-that, or a plain statement about the user; nothing is wanted back but the keeping. | Bringing back something seen in this app before ("remember that convo on the dyson pencilvac", "remember that page"), which is recall; a question that mentions a fact on the way to asking something ("I'm allergic to peanuts, what can I snack on" wants the snacks); a fact about the world. | "remember that I'm allergic to peanuts", "keep in mind I'm vegetarian", "don't forget my wife's name is Ana", "note that I don't eat pork", "I live in austin now" |
| 11 | `forget` | The user asks the app to forget, drop or stop remembering something it knows about them: the fact just noted, or one named by its subject. | Forgetting a page, a search or an answer, which is nothing the app keeps as a fact; a new question; "never mind" about a query just typed. | "forget that", "forget that I'm vegetarian", "stop remembering my peanut allergy", "drop what I told you about my wife", "you can forget where I live" |
| 12 | `time` | The time or date right now, here or in a named place: what time it is, the time in Tokyo, today's date, what day it is. The device clock answers it. | Time zones as a topic, how long something takes, a date in history, the weather, and when an event starts, which are answers; and a place to find, which is map. | "what time is it in tokyo", "what's the time in costa rica", "What time is it in Mexico?", "what's the time", "what day is it today" |

Answer: `choice` (one option name), `probabilities` (one per option), `confidence` (0–1).

### `recent` — type `noul`

A yes/no question answered with the probability of yes. Instructions sent with the question:

> Would the correct answer to this query depend on something that may have changed in the last two years? For example whether a person is alive, who currently holds an office, title or job, a record, a price, a recent event or its aftermath, or a phrase, slogan or meme that became known recently. Something worked out from a settled fact and today's date, such as an age or how long ago something happened, does not depend on such a thing: the settled fact is known and today's date is given. A question handed to the AI by name ("ask AI ...") never depends on such a thing: the person wants the AI's own answer, knowing what it is.

| Means | Description |
|---|---|
| yes | The right answer could have changed since early 2025: it depends on someone's current status, the current holder of a position, a recent or ongoing event, or a new phrase. |
| no | A settled fact, history, how something works, a definition, a conversion, a place, a date or time, something worked out from a settled fact and today's date such as an age or an elapsed time, anything else that does not go stale, or a question handed to the AI by name. |

Answer: `noul`, the probability of yes (0–1). No confidence field.

### `recall_pages` — type `noul`

A yes/no question answered with the probability of yes. Instructions sent with the question:

> Read the query as a request to bring back something the user saw earlier in this app: a web page, a written answer, a picture, a search, or a video. Does it ask for a web page: an article, a post, a site, a link, a thread, or something read or visited?

| Means | Description |
|---|---|
| yes | The query names a page, article, post, site, link or thread, or something the user was reading or visited: "that article on reddit", "the site I was looking at about hennessy", "pull up that youtube page from earlier". |
| no | It names an answer, a picture, a search or a video instead; or it names no kind at all ("the last 5 things we were looking at", "that thing about gingivitis"), which is a no for every kind. |

Answer: `noul`, the probability of yes (0–1). No confidence field.

### `recall_answers` — type `noul`

A yes/no question answered with the probability of yes. Instructions sent with the question:

> Read the query as a request to bring back something the user saw earlier in this app: a web page, a written answer, a picture, a search, or a video. Does it ask for an answer this app wrote: a chat, a conversation, a question it answered, something it told or said?

| Means | Description |
|---|---|
| yes | The query names an answer, a chat, a conversation, a question asked of the app, or what the app said or told the user: "that answer about hot chocolate", "remember that convo on the dyson pencilvac", "what you told me about gingivitis". |
| no | It names a page, a picture, a search or a video; or it names no kind. "Talked about", "looked at" or "things" say what the user did, not that an answer is wanted: "everything we talked about with the dyson" is a no. |

Answer: `noul`, the probability of yes (0–1). No confidence field.

### `recall_pictures` — type `noul`

A yes/no question answered with the probability of yes. Instructions sent with the question:

> Read the query as a request to bring back something the user saw earlier in this app: a web page, a written answer, a picture, a search, or a video. Does it ask for a picture: a photo or an image the user saw?

| Means | Description |
|---|---|
| yes | The query names a picture, photo or image: "the picture of the pencilvac", "that photo from yesterday", "my recent pictures". |
| no | It names another kind, or no kind. "Show me" or "looked at" alone is not a picture. |

Answer: `noul`, the probability of yes (0–1). No confidence field.

### `recall_searches` — type `noul`

A yes/no question answered with the probability of yes. Instructions sent with the question:

> Read the query as a request to bring back something the user saw earlier in this app: a web page, a written answer, a picture, a search, or a video. Does it ask for a search: a results page, or what was searched or googled?

| Means | Description |
|---|---|
| yes | The query names a search, a results page, or what was searched or googled: "my last five searches", "what I googled yesterday", "the last 5 things I asked you, including google searches". |
| no | It names another kind, or no kind. "Looking at" or "pull up" alone is not a search. |

Answer: `noul`, the probability of yes (0–1). No confidence field.

### `recall_videos` — type `noul`

A yes/no question answered with the probability of yes. Instructions sent with the question:

> Read the query as a request to bring back something the user saw earlier in this app: a web page, a written answer, a picture, a search, or a video. Does it ask for a video: a clip, or something watched?

| Means | Description |
|---|---|
| yes | The query names a video or clip, or something the user was watching: "the video I was watching about muse", "all the videos from yesterday", "the last 2 videos". |
| no | It names another kind, or no kind. A wristwatch is not watching: "that watch I was looking at" is a no. |

Answer: `noul`, the probability of yes (0–1). No confidence field.

### `recall_named` — type `noul`

A yes/no question answered with the probability of yes. Instructions sent with the question:

> Read the query as a request to bring back something the user saw earlier in this app: a web page, a written answer, a picture, a search, or a video. Does it name a particular thing to find, a topic, a title, a name, a site, or a word of what it was, rather than only a kind of thing, a count or a time?

| Means | Description |
|---|---|
| yes | There is a subject to look for: "the dyson pencilvac", "that thing about gingivitis", "the reddit thread", "the video about muse", "my grocery list", "that youtube page". |
| no | Only a kind, a count, a time, or the asking itself: "the last 5 things we were looking at", "the videos from yesterday", "my recent searches", "pull up what I was looking at". Words that describe the asking ("we were looking at", "things", "stuff", "earlier") name nothing. |

Answer: `noul`, the probability of yes (0–1). No confidence field.

### `recall_all` — type `noul`

A yes/no question answered with the probability of yes. Instructions sent with the question:

> Read the query as a request to bring back something the user saw earlier in this app: a web page, a written answer, a picture, a search, or a video. Does it ask for everything, all, or several things, everything about a topic, all of a kind, or the last so many, rather than one particular thing?

| Means | Description |
|---|---|
| yes | A set is wanted: "everything we talked about with the dyson", "all the videos from yesterday", "the last 5 things", "my recent searches", "anything about lisbon". |
| no | One thing: "that answer about hot chocolate", "the video I was watching about muse", "go back to the reddit thread", "where's my grocery list". |

Answer: `noul`, the probability of yes (0–1). No confidence field.

### `remember` — type `noul`

A yes/no question answered with the probability of yes. Instructions sent with the question:

> Does the query state a lasting fact about the user, their preferences, people, places, things or situation, or ask the app to remember something for later?

| Means | Description |
|---|---|
| yes | The user tells the app something that will still be true next week and could shape a later answer, or asks it to keep something in mind: "remember that I'm allergic to peanuts", "I'm vegetarian", "my wife's name is Ana", "we moved to Austin", "I don't eat pork", "keep in mind I have a nut allergy", "I'm allergic to peanuts, what can I snack on". |
| no | A question or request with no lasting fact in it; something true only now ("I'm hungry", "I'm at the airport"); a fact about the world rather than the user ("the capital of peru is lima"); and "remember" pointing at something seen before in this app ("remember that convo on the dyson pencilvac", "remember that page"), which is recall. |

Answer: `noul`, the probability of yes (0–1). No confidence field.

### `reasoning` — type `score`

A position on an ordered scale. Instructions sent with the question:

> How much working out does this query need before the chosen format can act on it? Judge the query as the earlier exchanges it depends on make it.

Levels, low to high:

| Level | Description |
|---|---|
| 0 | Direct: the format acts on the words alone: a search, a question to answer, a picture, a site by name, videos, something seen before. "capital of peru", "go to youtube", "pictures of it", "wait no I meant brazil". |
| 1 | A value must be read out of the words first and passed along: a number, a name, a setting, a place, a time. "set the thermostat to 68", "remind me at 7", "translate this to spanish". |
| 2 | Several steps, a condition or a schedule: an "and then", an "if", a "when", an "every", or a comparison across several things. "find the cheapest flight and book it", "if it rains tomorrow move my run to the evening". |

Answer: `score` (the levels weighted by their probabilities, so 0 to 2, possibly between two), `probabilities` (one per level, keyed by its number), `confidence` (0–1).

## When earlier exchanges are in the state

From the second query of a session on, the state carries the earlier exchanges and the `instinct` question's instructions become:

> Which response format best answers this web search query? The state carries the earlier exchanges of this session under `exchanges`, oldest first: each query and what it got (an answer's text, a page's title and address, a search's term). Judge the query as the exchanges it depends on make it, not as typed on its own; a query that stands on its own is judged as typed. A reply, a reaction or a question that leans on an earlier answer, however short, wants narrative; or one_line when the reply is itself a single short fact, a number, a name, a date, a yes/no, as "and chile?" after a capital is. A correction or narrowing of an earlier search ("wait no I meant brazil") wants web_results, read with the correction applied. Pick another format only when the query asks for the kind of thing that format shows: map, stock, recall, image, site, video, remember, forget, time, each described below; or web_results for a page to browse.

and one question is asked per exchange, `x0` for the oldest sent, `x1` for the next, and so on. For the first of two exchanges:

### `x0` — type `noul`

A yes/no question answered with the probability of yes. Instructions sent with the question:

> The state lists the earlier exchanges of this session under `exchanges`, oldest first: each query and what it got. Does the current query depend on exchange 1 of 2, the query "<earlier query>", which got a written answer, to be understood or acted on?

| Means | Description |
|---|---|
| yes | The query replies to, corrects, narrows or builds on that exchange, or names something only it makes clear, however short: "why?", "wait no I meant brazil", "the second one", "pictures of it", "and chile?", "is that open on sundays". |
| no | The query stands on its own, or depends only on a different exchange: it would mean the same thing with that exchange gone. |

Answer: `noul`, the probability of yes (0–1). No confidence field.

The app walks back from the newest exchange and stops at the first one below 0.5: that is the chain, the exchanges the query depends on. Every answer is logged (`relevance`, oldest first) with the chain's length (`chain`), so a yes behind a no stays visible. A chain that ends on an answer exchange means an answer pick continues that answer; a chain that ends on a page, a search or a picture means the chosen instinct gets those exchanges as context (a narrative lists them under its context block; see "After routing: Gemini answers").

## When a site is on screen

A query typed over a site this app opened by name (from the book, or learned from a tap) carries the name and host in the state and the site instinct asks one more question:

### `rejects` — type `noul`

A yes/no question answered with the probability of yes. Instructions sent with the question:

> The user asked for a website by name and the app opened the one in the state (opened_site_name, opened_site_host). Is this query saying that was the wrong site and asking for a different one?

| Means | Description |
|---|---|
| yes | The query rejects the site on screen or asks for another one for the same name: "no not this one", "not this zillow", "I'm looking for a different website", "wrong site", "that's not it", "a different one". |
| no | Anything else: a new search or question, a request for another site by its own name ("open youtube"), or something to do on the open site. |

Answer: `noul`, the probability of yes (0–1). No confidence field.

## What comes back

```json
{ "model": "jev-1.13.0", "answers": { "instinct": { "type": "choice", "choice": "stock", "confidence": 0.91, "probabilities": { "web_results": 0.05, "stock": 0.92, … } }, "recent": { "type": "noul", "noul": 0.08 }, "x0": { "type": "noul", "noul": 0.83 }, "reasoning": { "type": "score", "score": 0.21, "confidence": 0.79, "probabilities": { "0": 0.82, "1": 0.15, "2": 0.03 } } }, "usage": { "input_tokens": 512, "output_tokens": 9 } }
```

- `choice`: the option with the highest probability.
- `probabilities`: one per option, summing to 1.
- `confidence`: `(p_max − 1/n) / (1 − 1/n)`; 0 for a flat spread, 1 for a single peak. Only the top probability matters.
- `noul`: the probability of yes, 0 to 1.
- `score`: the level numbers weighted by their probabilities, so 0 to 2 here, with a probability per level and a confidence of its own.

## What the app does with it

| Outcome | Shown | Logged as |
|---|---|---|
| Address typed | That page | `directURL` |
| No API key configured | Web results | `noKey` |
| Request failed or timed out | Web results | `error(reason)` |
| `confidence` below 0.5 | Web results | `confidenceFallback` (the pick is kept as `suggested`; with `reasoning` at or above 1.2 the line also reads as `reasoningWanted`, and the query is planned) |
| `confidence` at or above 0.5 | The picked instinct runs | `jev` |
| `narrative` or `one_line` picked, `recent` at or above 0.5 | The answer instinct shows web results instead (the model's knowledge is months old; see the answer prompts) | `jev`, with `recency` on the line |
| The chain ends on an answer exchange and an answer was picked | The answer on screen grows into a transcript: the query as a line, then a reply written with the earlier turns in view | `jev` with `continues` |
| The chain ends on a page, a search or a picture, or another card was picked over an answer | The picked instinct runs with the chained exchanges as context: an answer lists them under its context block; the reading folds them into the read words | `jev` with `chain` above 0 |
| `site` picked | The site, when the book knows the name; otherwise the choices card (see "After routing: sites") | `jev` |
| `site` picked over a site opened by name, `rejects` at or above 0.5 | The name is forgotten and the choices card shown again | `jev`, with `rejection` on the line |
| `time` picked | The time from the device clock, here or in the place the extractor read; web results for a place it does not know | `jev` |
| `remember` picked | The fact the extractor reads out of the words is kept, naming whoever it is about, and a mark says so; what was on screen stays | `jev`, with `fact` |
| `forget` picked | The facts the words point at are judged (one yes/no each, as a recall's are) and the one asked for is put to the user on the sheet; a tap forgets it | `jev`, with `fact` |
| `reasoning` at or above 1.2 on any pick, or at or above 1 on an unsure one, with a Gemini key | The query is planned instead of run (see "Reasoning (function calling)" below): each step the plan shows or does runs through the ordinary paths and is logged as its own line | the pick's own source, with `engine` on its line; each step `plan` |
| `remember` at or above 0.5 on any other pick | The pick runs as usual, and the lasting fact the words state is noted quietly, as a model distils it, with a mark | the pick's own line, with `fact` |

Web results, however reached, search the read words as they are ("which oh can you pull up youtube" → "can you pull up youtube"); the log keeps the spoken words. An `image` pick loads Google's image results for the read words. A `video` pick loads Google's video results for them (see "After routing: videos").

Every outcome is appended to `decisions.jsonl` on the device with the query, the pick, every option's probability, confidence, the recency probability, the relevance answers and the chain, the reasoning score, model, latency and input tokens. Summarise an exported log with `swift run --package-path Packages/Engine report decisions <file>`.

## After routing: recall

A `recall` pick is resolved in this order. First, Jev's reading of the ask, answered in the routing request itself (the `recall_*` questions above, so a recall costs no second round trip): which kinds of memory are wanted (`recall_pages`, `recall_answers`, `recall_pictures`, `recall_searches`, `recall_videos`), whether a particular thing is named (`recall_named`) and whether a set is wanted (`recall_all`), each a yes at or above 0.5. The intent is read only when `recall` was the pick, and logged with the decision. Second, the count ("last five", "recent") and the time words ("yesterday", "this morning", "three days ago") from the query itself, since a number and a day are not judgments. Third, the shortlist (`RecallFilters`, `MemorySearch.shortlist`): the kinds, the time and the video flag filter the memories; when a thing is named, the records are ranked by the words that remain, then the rest of the filtered set newest first, at most 10, with the kind a preference, not a wall; when nothing is named, no word is matched at all and the newest of the filtered set are taken. Without an intent (no key, a failed request, an older log) the kind words in the query ("video", "answer", "picture") and the collection words stand in, and with no filter and no content word there is nothing to go on, so the words go to web results. Last, unless a count or a set of a kind with nothing named was asked for (those are listed as they are, no judge needed), the shortlist goes to Jev in one request, a yes/no question per memory:

> Is this the memory the query asks for? A web page from yesterday (m.youtube.com): "Rick Steves' Europe: Lisbon".

| Means | Description |
|---|---|
| yes | The query describes this memory: by what it is, when it was seen, what it was about, or a word of its title. |
| no | A different thing, even if it shares a word with the query or is of the same kind. |

A memory at or above 0.5 is the one asked for and is shown alone. Otherwise every memory at or above 0.3 is plausible and is shown in Jev's order, so an unsure Jev leaves the choice to the user. Nothing ever opens straight away: even a single memory is shown in the grid before it takes the screen; none goes to web results for the query's content words ("that thing about gingivitis again" searches "gingivitis"). A failed or slow request, or no key, shows the shortlist in word order. The record's `recall` logs the shortlist size, how many were plausible, the path (`jev`, `words`, or the error) and the latency.

### Everything about something

A query that asks for everything wants a collection, not one thing: "pull up everything we talked about with the dyson pencilvac". `recall_all` says so, and a collection needs a named thing (`recall_named`): the per-memory question below is about that thing. The kinds become no bar (every memory about it is wanted; a span the extractor read still holds), the shortlist is the word matches, and each memory is asked a different question:

> Is this memory about what the query asks for everything about? A web page from yesterday (m.youtube.com): "Rick Steves' Europe: Lisbon".

| Means | Description |
|---|---|
| yes | This memory is about the thing, topic or name the query asks for everything about: its title, its query, its address or its text concerns it, whatever kind of memory it is. |
| no | About something else, even of the same kind, from the same day, or sharing an unrelated word with the query. |

Every memory at or above 0.5 is shown, newest first, in a picker titled by the topic; one alone opens; none goes to web results for the topic words. The record's `recall` carries `collection: true`. A set of a kind with nothing named ("all the videos from yesterday") is listed as it is, newest first up to 10, titled "All videos", with no judge asked, logged with the path `all`.

### The last so many

A query that asks for a count ("my last five searches", "the last 5 things I asked you", "latest three pictures"; the extractor reads the number, at most 20) wants the newest so many, not a thing: the kinds Jev read and the span the extractor read still filter, the word matches narrow when the query names something too, and the newest so many are shown as a picker titled "Last 5 searches and answers", even when only one was found, with no judge asked, since there is nothing to judge. The record's `recall` carries `count` and the path `count`. The extractor reads a recall's `count`, `from` and `to` on every recall pick, against today's date.

## After routing: videos

A `video` pick loads Google's video results (`QueryParser.videoSearchURL`, the results page with `tbm=vid`) for the read words as they are. There is no card: the page is the result. The capsule reads the term off the page and the log keeps the spoken words.

## Question types not used yet

- **box**: where something is in an image. No use in sight.

Adding a question is one entry in `EngineRequest.request`, or one line in an instinct's `questions` in `InstinctSpec`; this file and `EngineTests` pick it up.

## Who Jarvits is

The app is an assistant, Jarvits, assisting the person holding the phone. Every Gemini instruction he sends opens with an identity line (`Persona.identityLine`) so no model takes the speaker for itself, and a fact is kept from his point of view ("Lorcan's friend Noah is vegan"). The user's name is asked on the small sheet when the app is first installed or its memory is cleared, and kept in `facts.profile.json` beside the facts (`FactStore.userName`); until it is given the prompts say "the person you assist". Jev never sees any of this. The prompts below are rendered for a user named Lorcan:

You are Jarvits, the assistant in Lorcan's phone browser. Lorcan is the person speaking to you; you are not Lorcan. Speak of Lorcan by name and of yourself as Jarvits.

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

### Input with earlier exchanges

When the relevance chain says the query depends on earlier exchanges of this session from other layers than the answer's own thread (a search, a page read, a picture looked at; `chain` in the decision), they follow the context block, oldest first, one line each:

```
Query: <query>

Context (use for "today" and "now"; do not repeat it unless the query asks about it):
- Date and time: Wednesday 21 October 2026, 11:26 (America/Chicago)
- Your knowledge ends around January 2025, about 21 months before this date.
- Locale: en_US

Earlier in this session (oldest first; the query may lean on them, but answer only the query):
- Searched "<term searched>"
- Read "<page title>" (<host>)
```

### Input with facts

Everything the app knows about the user (`FactStore`: told outright, chosen on the sheet, or inferred from a query that stated something lasting on the way to its ask) goes into every answer, each in the user's own words, after the context and the earlier exchanges. The system instructions say to let them shape the answer when they bear on it and never to repeat them.

```
Query: <query>

Context (use for "today" and "now"; do not repeat it unless the query asks about it):
- Date and time: Wednesday 21 October 2026, 11:26 (America/Chicago)
- Your knowledge ends around January 2025, about 21 months before this date.
- Locale: en_US

What Jarvits knows about Lorcan (told earlier; let it shape the answer when it bears on it, never repeat it or say you were told):
- <fact>
- <fact>
```

An inferred fact is distilled by the same small call that reads values ("Values read by Gemini" below) with this instruction and a one-field schema, when Jev's `remember` question says the query states one and the pick is not `remember` itself:

```
You are Jarvits, the assistant in Lorcan's phone browser. Lorcan is the person speaking to you; you are not Lorcan. Speak of Lorcan by name and of yourself as Jarvits.
You note the personal fact a request Lorcan made to you states. Reply with JSON matching the schema and nothing else.
A fact is something lasting and personal: about Lorcan, or about anyone or anything in their life, a preference, an allergy, a name, where they live, their job, a coworker, their mother's age. It will still be true next week and could shape a later answer. State it in one short sentence as you would note it, from your own point of view: Lorcan by name, never "I" or "my" for them, and whoever or whatever else the words name kept as the words relate them to Lorcan ("Lorcan's friend Noah is vegan", "Lorcan is allergic to peanuts", "Lorcan's mom Jasmine is 50 years old"). Something true only now, a fact about the world with no one personal in it, or a question with nothing lasting in it is null.
Earlier exchanges of the session may come before the request, oldest first.
```

### Input for a narrative that continues

When the relevance chain ends on the answer on screen (`continuation` in the decision), `input` is a list of `user_input` and `model_output` steps instead of a string, Google's stateless shape; `store` stays false. Oldest first: `{"type": "user_input", "content": [{"type": "text", "text": "<earlier query>"}]}`, `{"type": "model_output", "content": [{"type": "text", "text": "<earlier answer, markup included>"}]}`, and so on, then one last `user_input` step holding the block above. Every earlier turn is sent, however long the conversation.

### `narrative` — system instruction, max 800 output tokens

```
You are Jarvits, the assistant in Lorcan's phone browser. Lorcan is the person speaking to you; you are not Lorcan. Speak of Lorcan by name and of yourself as Jarvits.
You answer the queries Lorcan puts to you. Lorcan typed a query and expects a short written answer.

Rules:
- Open with the most immediate, simple answer in the first line or two. Everything after that supports it.
- Match the scope to the wording of the query. "What is X" wants what X is: the full name and a sentence or two of meaning, not how it works, examples or history. "How does X work" wants how it works and nothing adjacent: not its background, its context in the field, or why it rose or declined. Add nothing the query did not ask for: no related facts, caveats or tips.
- There is no target length. Stop when the question is answered. Never pad, ramble, or add a closing thought. Plain prose in short paragraphs; no headings, bullet points, numbered lists, tables, emoji, or Markdown other than the emphasis markers below.
- No preamble and no closing line. Start with the answer. Do not offer further help or suggest follow-up questions.
- Earlier turns of this conversation may come before the query, oldest first; the context block applies to all of them. Then the query is a reply to your last answer: resolve "it", "that", "why" and the like against the conversation, do not repeat what you already said, and answer only the new question.
- Your knowledge ends around January 2025 and you have no access to the web; the context says how long ago that was. Answer with what you knew then, stated as plain fact. Never say when your knowledge ends, that the answer may be out of date, or that you cannot check: the browser puts a web link under every answer. Do not invent developments after that date.
- Use the context block for "today" and "now". Do not mention the context unless the query is about it.
- A block "What Jarvits knows about Lorcan" may follow the context: facts Lorcan told you before, as you noted them. Let them shape the answer when they bear on it (a vegetarian gets a vegetarian recipe); ignore them otherwise; never list them back, repeat them or say you were told.
- If the question rests on a false premise, say so in one sentence, then answer the nearest true question.
- Write in the language of the query.

Emphasis. Mark it with exactly these markers and nothing else:
- ==…== for the single most important thing Lorcan should take away, at most once in the whole answer (each answer in a conversation has its own).
- **…** for the facts that directly answer the question, a few at most.
- __…__ for a condition or caveat that changes the answer.
- _…_ for a name, title or term you are introducing.
Most sentences have no markers. Never put a marker around a whole sentence or paragraph.
```

### `one_line` — system instruction, max 160 output tokens

```
You are Jarvits, the assistant in Lorcan's phone browser. Lorcan is the person speaking to you; you are not Lorcan. Speak of Lorcan by name and of yourself as Jarvits.
You answer the queries Lorcan puts to you with a single line.

Rules:
- Reply with one line only: a number, a word, a name, a date, a time, or a short clause. Examples: "24 days", "Lima", "8:14 PM", "About 92 euros".
- Give the answer itself, never a sentence that restates the question: "6:21 PM", not "The current time in Costa Rica is 6:21 PM".
- Never more than twelve words. No explanation, no second sentence, no preamble, no trailing period.
- Earlier turns of this conversation may come before the query, oldest first; the query may lean on them ("and chile?", "in km?"): resolve it against your last answer and answer only the new question, still in one line.
- Your knowledge ends around January 2025 and you have no access to the web. If the question needs live data, such as today's weather, a current price or exchange rate, a live score, or the latest news, or if the answer may have changed since January 2025, such as whether a person is alive or who currently holds a role, reply with exactly: NEEDS_LIVE_DATA
- You do know the current date and time from the context block. Compute dates, countdowns and the time in other places from it.
- A block "What Jarvits knows about Lorcan" may follow the context: facts Lorcan told you before, as you noted them. Let them shape the line when they bear on it; ignore them otherwise; never repeat them or say you were told.
- If the honest answer is a range or depends on something, give the typical value in the line, such as "Usually 7 to 10 days".
- If the question cannot be answered in one line, answer its most direct version in one line anyway.
- Answer in the language of the query.
- You may wrap the key word or number in ==…==, as in "About ==92== euros". No other markers, no Markdown.
```

### What comes back

Server-sent events: `step.delta` text pieces, then `interaction.completed` with usage (`total_input_tokens`, `total_output_tokens`, `total_thought_tokens`).

A call that needs the whole reply at once (a value read out of the words, a plan) sends `stream: false` on the same endpoint and reads the finished Interaction instead: its `status`, its `steps` (`model_output` text, `function_call` steps with `id`, `name` and `arguments`, anything else kept verbatim so a plan's next call can replay it) and its usage. The request then may carry `tools` (`{type: function, name, description, parameters}`), `generation_config.tool_choice` and a `response_format` schema; none of those goes on the wire for an answer.

| Outcome | Shown | Logged as |
|---|---|---|
| Streamed to the end | The answer card | `answer.outcome = completed` |
| `one_line` replied `NEEDS_LIVE_DATA` | Web results for the query | `needsLiveData` |
| Failed after some text | What arrived, with a note | `partial(reason)` |
| Failed before any text, or no first byte in 10 s, or over 30 s in all | Web results for the query | `fellBackToWeb(reason)` |
| No Gemini key configured | Web results; Jev's pick is still logged | the decision alone |

The answer summary (model, tokens, first-token and total latency, outcome) is appended to the same `decisions.jsonl` line as the routing decision.

### Values read by Gemini

An instinct may declare the values it takes (`ArgumentSchema` on its `InstinctSpec`). A closed-set value, a choice or a yes/no, is two Jev questions in the routing request (ENGINE.md above: `<instinct>.<field>?` and `<instinct>.<field>`). A free-form value, a number or words, is one whole-body call to `gemini-3.1-flash-lite` within 2 s, made only when the pick declares such a field that its own grammar did not read, and the field is required or the reasoning score leans to a value (at or above 0.5). The reply must match a JSON schema of the fields still missing; nulls are dropped, "68" is read as 68, a choice is checked against its options. Nothing usable, or a required value still missing, shows web results for the words.

System instruction:

```
You are Jarvits, the assistant in Lorcan's phone browser. Lorcan is the person speaking to you; you are not Lorcan. Speak of Lorcan by name and of yourself as Jarvits.
You read values out of a request Lorcan made to you. Reply with JSON matching the schema and nothing else.
A value is what the request says: a number as a number, words as the words used. Anything the request does not state is null.
Never guess, never add fields. Earlier exchanges of the session may come before the request, oldest first; "it", "that" and the like resolve against them. Today's date may come too: a day the request names ("yesterday", "last week") is read against it.
```

Input, with the chained exchanges first, and the schema for a thermostat instinct that takes a required `temperature` and an optional `room`:

```
Earlier: Searched "<term searched>"
Request: <query>
```

```json
{"additionalProperties":false,"properties":{"room":{"description":"which room, when one is named","type":["string","null"]},"temperature":{"description":"the degrees asked for","type":"integer"}},"required":["temperature"],"type":"object"}
```

| Outcome | Then | Logged as |
|---|---|---|
| At least one value read | The instinct runs with it | `extraction.outcome = extracted` |
| The reply held no value | Web results when a required field is empty, else the instinct runs without it | `empty` |
| Failed, timed out, or not JSON | Web results when a required field is empty, else the instinct runs without it | `failed(reason)` |
| No Gemini key | Web results when a required field is empty | `failed("no key")` |

The extraction summary (model, latency, tokens, the fields read, the outcome) rides on the same `decisions.jsonl` line.

### The reading beside Jev

Every query that reaches Jev (every one that is not an address) goes to `gemini-3.1-flash-lite` at minimal thinking at the same moment, with this instruction and a one-field schema, within 4 s: `query`, the request standing on its own (dictation noise, fillers and false starts gone, anything the words point back at folded in); the newest 3 exchanges and today's date come first so "it" and "yesterday" resolve. When the substance differs from the typed words (`Substance.differs`: case, diacritics, punctuation and spacing aside), Jev is asked again on the read words and that pick wins; the read words are what the instinct, the planner, the exchange and the layer receive. Every free-form value the picked instinct declares (`InstinctSpec.arguments`) is then read out of the read words by the extractor, one more call; web results, images and video declare none and search the read words as they are. The same substance, a miss or a slow reply leaves the first pick standing on the typed words. A query waits for the slower of the two calls. The typed words stay in the log as `reading.original`; the line's `query` is what ran. The eval runner grades Jev on the typed words and does not read.

System instruction:

```
You are Jarvits, the assistant in Lorcan's phone browser. Lorcan is the person speaking to you; you are not Lorcan. Speak of Lorcan by name and of yourself as Jarvits.
You read a request Lorcan made to you, usually dictated. Reply with JSON matching the schema and nothing else.
query: the request, standing on its own. Drop dictation noise, fillers, false starts and repeated words. Keep every word that carries meaning, the person's own wording and language, names, numbers and addresses. A request that leans on the earlier exchanges comes back complete, with what they make clear folded in, so it can be read with nothing else in view. Never answer, never add anything the request and the exchanges do not say. A request with nothing to drop and nothing to fold in comes back exactly as it is.
Earlier exchanges of the session may come before the request, oldest first, and today's date.
```

```
Today: Wednesday, October 21, 2026 at 12:26 PM
Request: Which oh can you pull up youtube?
```

```json
{"additionalProperties":false,"properties":{"query":{"description":"the request standing on its own; exactly the request when there is nothing to drop and nothing to fold in","type":"string"}},"required":["query"],"type":"object"}
```

| Outcome | Then | Logged as |
|---|---|---|
| The substance differs | Jev runs again on the read words, and that pick wins; the instinct and the extractor get the read words | `reading.outcome = rewritten` |
| The same substance | The first pick stands on the typed words | `unchanged` |
| Failed, timed out, not JSON, or an empty query | The first pick stands on the typed words | `failed(reason)` |

### Reasoning (function calling)

A query whose reasoning score reaches 1.2 (several steps, a condition, a schedule), or an unsure pick whose score reaches 1, is planned instead of run: `gemini-3.1-flash-lite` (price in `GeminiPricing`: $0.25 per 1M input tokens and $1.5 per 1M output; well under a cent a plan. `gemini-3.8-flash` was measured first on 2026-10-27: it refuses minimal thinking, and at low a round took eleven seconds and a thousand thought tokens, half a cent), thinking `minimal`, `store: false`, `tool_choice: any`, at most 4 rounds within 20 s, each round within 8 s. Every instinct is a tool, with a `query` field and the instinct's own; `ask` puts a question on the sheet and `done` ends the plan. The device runs each call in order (a paid or destructive tool is confirmed on the sheet first, unless the instinct asks for itself; the same call twice runs once; a second thing to show is refused) and sends the results back as `function_result` steps, every model step replayed verbatim, for the next round. Nothing the model writes is shown: it speaks through `narrative` or `one_line` with a query it writes.

System instruction:

```
You are Jarvits, the assistant in Lorcan's phone browser. Lorcan is the person speaking to you; you are not Lorcan. Speak of Lorcan by name and of yourself as Jarvits.
You plan what you do for a request Lorcan made. You never answer in text: nothing you write is shown to anyone. You act only by calling the tools below, and the device runs them.

Rules:
- To tell Lorcan anything, call narrative or one_line with a complete, self-contained question in its query, with whatever you learned from earlier steps folded in; the device answers it. Never summarise a result yourself.
- To confirm something, to choose, or to get a value the request leaves out, call ask; the answer comes back as the result.
- A tool that costs money or cannot be undone is confirmed with Lorcan by the device before it runs, not by you.
- Show at most one thing, as the last step: web_results, narrative, map, stock, one_line, recall, image, site, video, time each put a result on screen, and a second one would replace the first.
- When an answer on the sheet is something lasting about Lorcan or their life, call remember with it next.
- Call several tools in one turn only when none needs another's result; otherwise one at a time, and read the result before the next.
- A step whose result says it ran is done: never call it again with the same arguments.
- Call done when the request has been handled, or when nothing you can do would help.
- Date and time: Wednesday 21 October 2026, 11:26 (America/Chicago). Locale: en_US.

What Jarvits knows about Lorcan (told earlier; let it shape what you do, never repeat it):
- <fact>
```

First turn (the request, the exchanges it depends on, the memories the words point at, at most 5):

```
Request: <query>

Earlier in this session (oldest first):
- Searched "<term searched>"

Seen in this app before, that the request may mean (newest first):
- A page from yesterday (example.com): "<page title>"
```

Tools (`tools` on the request), one per instinct, then `ask` and `done`:

| Tool | Description | Fields |
|---|---|---|
| `web_results` | A standard page of web search results. The default for broad, vague or multi-part queries, for a search for something on a site, for browsing many pictures, and for anything the other formats do not clearly fit. A bare topic with no ask, such as "chocolate milk" or "quantum computing", is one of these: the user wants the general spread, not one answer. So is a query that asks for the search itself, such as "google steve jobs" or "look up flights to lima", whatever the topic. Not for: A question that asks why or how something happened, a single short fact, a specific place to find, a ticker, a request to open a website by its name, the bare name of one specific thing with a definitive look, which wants a picture, or videos to watch, which want video results. Puts its result on screen. | query |
| `narrative` | A written explanation. The query asks why or how something happened or works, what something is or means (a definition, or the expansion of an acronym or term within a field, which needs the full name and a sentence or two of context), for the story behind something, where a phrase, slogan, name or meme came from, or for a judgement that needs context, such as whether somewhere is safe. Also any question handed to the AI by name ("ask AI what GDP means", "ask the AI about Dyson alternatives"): the person wants the model's own answer, whatever the question. Not for: Questions answered by one line, such as a time, a date, a number or a yes/no, and queries that only want a price chart. Puts its result on screen. | query |
| `map` | A map with a pin. The query names a physical place to locate or get to: an address, a shop, a city, a landmark, directions, or something near me. Not for: Places mentioned only as the subject of a question or a fact, such as whether a country is safe or what time it is there. Puts its result on screen. | query |
| `stock` | A price chart for a security. The query names a ticker, a public company's stock or share price, a market index, or a cryptocurrency price, and wants the price. Not for: Questions about why a price moved or company news, which want an explanation, and currency conversion. Puts its result on screen. | query |
| `one_line` | A single short answer that fits on one line: a time, a date, a number, a duration, a yes/no, a conversion, or a quick fact that is itself a name, number or date, including live ones like the weather. Not for: The time or date right now, here or somewhere, which is time; questions that ask why or how and need a few paragraphs; definitions and what-is questions, which need the full name and some context rather than one value; and anything that wants a price chart. Puts its result on screen. | query |
| `recall` | Something the user saw in this app before and wants back: a page they were on, an answer they got, a list they made. The query points at the past ("that", "again", "my", "remember", "pull up", "where's", "go back to") instead of asking something new. Not for: A new question or search that merely contains such a word, like a film title or a package delivery; opening a website by its name with no pointer at the past ("pull up zillow"), which is site; anything the user has not seen in this app. Puts its result on screen. | count, from, query, to |
| `image` | A single picture of one specific, named thing with a definitive look: a flag, a logo or emblem, a landmark or monument, a painting, a person, a product, a species, a chemical structure. The bare name of such a thing, with no other words, means the user wants to see it, not read about it. Not for: Browsing many pictures of a category, mood or idea, which wants web results; and questions about why something looks the way it does, which want an explanation. Puts its result on screen. | query |
| `site` | Open a website or app by its name. The query is a go-to, open, pull-up or take-me-to verb and a site's name, or the bare name of a well-known site with nothing else; the user wants the site itself, not results about it. Over a site this app opened by name, a complaint that it is the wrong one is a request for the same name again. Not for: A search for something on a site ("zillow homes in austin"), a question about a site, and a page the user saw in this app before ("that youtube page from earlier", which is recall). Puts its result on screen. | name, query |
| `video` | A page of videos to watch. The query asks for videos, clips, highlights, a trailer, a music video, a performance, a tutorial to watch, or to watch or play something: the user wants to press play, not read. Not for: A video the user saw in this app before ("the video I was watching"), which is recall; a website or app by its name ("open youtube"), which is site; one still picture of a thing, which is image; and a topic that merely has videos about it, with no ask to watch, which is web results. Puts its result on screen. | query |
| `remember` | The user asks the app to keep something in mind about them for later, or tells it something lasting about themselves with nothing else asked: a preference, an allergy, a name, where they live. The words are a remember, a keep-in-mind, a don't-forget, a note-that, or a plain statement about the user; nothing is wanted back but the keeping. Not for: Bringing back something seen in this app before ("remember that convo on the dyson pencilvac", "remember that page"), which is recall; a question that mentions a fact on the way to asking something ("I'm allergic to peanuts, what can I snack on" wants the snacks); a fact about the world. Shows nothing; a mark says what was done. | fact, query |
| `forget` | The user asks the app to forget, drop or stop remembering something it knows about them: the fact just noted, or one named by its subject. Not for: Forgetting a page, a search or an answer, which is nothing the app keeps as a fact; a new question; "never mind" about a query just typed. Shows nothing; a mark says what was done. Asks the user itself before acting. | about, query |
| `time` | The time or date right now, here or in a named place: what time it is, the time in Tokyo, today's date, what day it is. The device clock answers it. Not for: Time zones as a topic, how long something takes, a date in history, the weather, and when an event starts, which are answers; and a place to find, which is map. Puts its result on screen. | place, query |
| `ask` | Put one short question to the user on a small sheet and get the answer back: to confirm, to choose, or to get a value the request leaves out. Give one to three options with the expected one first, or none for a line of text. | options, question |
| `done` | Call once the request has been handled, or once nothing you can do would help. |  |

| Outcome | Then | Logged as |
|---|---|---|
| `done`, or the rounds end after something was shown or done | What the steps showed stays; a plan that only did something hands the screen back | `engine.outcome = completed` |
| Nothing shown and nothing done | Web results for the words | `fellBackToWeb(reason)` |
| No on the sheet, or the sheet swiped away | The plan ends there | `declined` |
| The rounds or the time ran out | As completed, or web results when nothing happened | `budget` |
| A newer query took the screen | Nothing more | `stale` |

The plan summary (model, rounds, every step with its outcome and latency, tokens, the facts and memories given, the outcome) rides on the same `decisions.jsonl` line; a step that did something with no screen of its own is also a memory of kind `action`, so "what did you just do" finds it.

## After routing: sites

A `site` pick names a website. The name is what the extractor reads out of the read words ("can you pull up youtube" → "youtube"; see "The reading beside Jev"), or the words as they are when it read none. The site book on the device (`SiteBook`: 37 seeded sites under 53 names, plus whatever has been learned) answers a known name at once; an unknown name is searched by `SiteSearch` in `Packages/Engine/Sources/Sites`, with a Brave Search API key (`BRAVE_API_KEY`).

1. `GET https://api.search.brave.com/res/v1/web/search?q=<name>&count=8&result_filter=web`, header `X-Subscription-Token`. Only `web.results` is read: title, url, description, and the result's favicon when it carries one (`meta_url.favicon` or `profile.img`), else Google's public favicon service for the host.
2. One result per host (`www.` aside), in Brave's order, the first 5: the choices card.
3. The site tapped is learned under the name, as its origin (scheme and host), and opened. The next time the name is asked for it opens straight away, with no model and no search.

No key, no result, any failure, or 6 s without a reply shows the Google results page for the name instead, and the first site tapped off it is learned the same way.

| Outcome | Shown | Logged as |
|---|---|---|
| The book knows the name | That site | `site` summary `opened` with the host |
| Candidates found | The choices card | `choices` with the count and latency |
| No key, nothing found, or an error | Web results for the name | `results` with the reason |
| Over a site opened by name, `rejects` at or above 0.5 on a site pick | The choices card again, the name forgotten | `rejected` |
