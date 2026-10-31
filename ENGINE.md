# Engine contract

Generated from `EngineRequest` and the instinct registry (`InstinctSpec`) in `Packages/Engine`. Do not edit by hand; run:

```
swift run --package-path Packages/Engine report engine > ENGINE.md
```

## The request

One `POST https://api.typesafe.ai/v1/systemone` per query, model `jev-1.13.0`, timeout 20000 ms. Every question below goes in that one request and is answered in parallel: which instinct fits, whether the answer may have gone stale, how a recall ask reads, whether the query states a lasting fact about the user, which earlier exchanges the query depends on, and how much working out it needs.

State (what Jev reads):

| Field | Value |
|---|---|
| `query` | The text as typed, trimmed. |
| `locale` | The device locale identifier, e.g. `en_US`. |
| `exchanges` | Only after the first query of a session: the newest 20 earlier exchanges, oldest first, each the query and what it got. Every exchange has `query` and `kind` (`answer`, `page`, `search`, `picture`, `recall`, `site`); an answer carries its `text` whole, a page its `title`, `host` and `address`, a search the `text` in its box, a picture the `text` of its subject. A page or search Jarbits read on its own screen while planning carries `own: true` in the app, which is stripped before the state is sent, so Jev reads it as any other. The format question then reads differently and one more question is asked per exchange; see "When earlier exchanges are in the state". |
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
| 1 | `web_results` | A standard page of web search results. The default for broad, vague or multi-part queries, for a search for something on a site, for browsing many pictures, and for anything the other formats do not clearly fit. A bare topic with no ask, such as "chocolate milk" or "quantum computing", is one of these: the user wants the general spread, not one answer. So is a query that asks for the search itself, such as "google steve jobs" or "look up flights to lima", whatever the topic. | A question that asks why or how something happened, a single short fact, a question about the user's own life, people, preferences or situation, which the assistant answers from what it was told, a specific place to find, a ticker, a request to open a website by its name, the bare name of one specific thing with a definitive look, which wants a picture, or videos to watch, which want video results. | "best laptops 2026", "news", "chocolate milk", "google steve jobs", "python tutorial reddit", "zillow homes in austin", "quantum computing", "golden retriever puppies" |
| 2 | `narrative` | A written explanation. The query asks why or how something happened or works, what something is or means (a definition, or the expansion of an acronym or term within a field, which needs the full name and a sentence or two of context), for the story behind something, where a phrase, slogan, name or meme came from, or for a judgement that needs context, such as whether somewhere is safe. Also any question handed to the AI by name ("ask AI what GDP means", "ask the AI about Dyson alternatives"): the person wants the model's own answer, whatever the question. A longer question about the user's own life, people, preferences or situation, such as what the assistant knows about them, is one of these too: answered from what it was told. | Questions answered by one line, such as a time, a date, a number or a yes/no, and queries that only want a price chart. | "at the end of attack on titan why is levi in a wheelchair", "ask ai about dyson alternatives", "how did simon cowell get famous", "why are highschool students protesting france?", "how is gingivitis healed", "Why is INTR so low?", "Is south africa safe right now", "where did the phrase ok boomer come from", "whats isi in ipe", "what does gdp mean", "define hegemony", "what do you know about me" |
| 3 | `map` | A map with a pin. The query names a physical place to locate or get to: an address, a shop, a city, a landmark, directions, or something near me. | Places mentioned only as the subject of a question or a fact, such as whether a country is safe or what time it is there. | "coffee near me", "directions to austin airport", "where is machu picchu", "blue bottle coffee san francisco" |
| 4 | `stock` | A price chart for a security. The query names a ticker, a public company's stock or share price, a market index, or a cryptocurrency price, and wants the price. | Questions about why a price moved or company news, which want an explanation, and currency conversion. | "nasdaq", "AAPL", "tesla stock", "bitcoin price", "s&p 500 today" |
| 5 | `one_line` | A single short answer that fits on one line: a time, a date, a number, a duration, a yes/no, a conversion, or a quick fact that is itself a name, number or date, including live ones like the weather. A short question about the user's own life, people, preferences or situation, such as what they are allergic to or whether they have a vegan friend, is one of these: the assistant answers it from what it was told. | The time or date right now, here or somewhere, which is time; questions that ask why or how and need a few paragraphs; definitions and what-is questions, which need the full name and some context rather than one value; and anything that wants a price chart. | "will it rain today", "how long do cold sores last", "capital of peru", "100 usd to eur", "what am I allergic to", "do I have any vegan friends" |
| 6 | `recall` | Something the user saw in this app before and wants back: a page they were on, an answer they got, a list they made. The query points at the past ("that", "again", "my", "remember", "pull up", "where's", "go back to") instead of asking something new. | A new question or search that merely contains such a word, like a film title or a package delivery; opening a website by its name with no pointer at the past ("pull up zillow"), which is site; anything the user has not seen in this app. | "where's my grocery list", "remember that convo on the dyson pencilvac", "pull up that youtube page from earlier", "pull up the video I was watching about muse", "that thing about gingivitis again", "go back to the reddit thread" |
| 7 | `image` | A single picture of one specific, named thing with a definitive look: a flag, a logo or emblem, a landmark or monument, a painting, a person, a product, a species, a chemical structure. The bare name of such a thing, with no other words, means the user wants to see it, not read about it. | Browsing many pictures of a category, mood or idea, which wants web results; and questions about why something looks the way it does, which want an explanation. | "dominican flag", "eiffel tower", "starry night painting", "nvidia logo", "what does a capybara look like", "mona lisa", "aston martin db5" |
| 8 | `site` | Open a website or app by its name. The query is a go-to, open, pull-up or take-me-to verb and a site's name, or the bare name of a well-known site with nothing else; the user wants the site itself, not results about it. Over a site this app opened by name, a complaint that it is the wrong one is a request for the same name again. | A search for something on a site ("zillow homes in austin"), a question about a site, and a page the user saw in this app before ("that youtube page from earlier", which is recall). | "go to youtube", "pull up zillow", "open insta", "take me to airbnb", "launch netflix", "reddit" |
| 9 | `video` | A page of videos to watch. The query asks for videos, clips, highlights, a trailer, a music video, a performance, a tutorial to watch, or to watch or play something: the user wants to press play, not read. | A video the user saw in this app before ("the video I was watching"), which is recall; a website or app by its name ("open youtube"), which is site; one still picture of a thing, which is image; and a topic that merely has videos about it, with no ask to watch, which is web results. | "videos of pele", "pele highlights", "dune part 3 trailer", "watch the super bowl halftime show", "show me cat videos", "how to tie a tie video", "lofi music video" |
| 10 | `remember` | The user asks the app to keep something in mind about them for later, or tells it something lasting about themselves with nothing else asked: a preference, an allergy, a name, where they live. The words are a remember, a keep-in-mind, a don't-forget, a note-that, or a plain statement about the user; nothing is wanted back but the keeping. | Bringing back something seen in this app before ("remember that convo on the dyson pencilvac", "remember that page"), which is recall; writing the user wants kept as a note or a list ("make a note that…", "add milk to my shopping list"), which is notebook; a question that mentions a fact on the way to asking something ("I'm allergic to peanuts, what can I snack on" wants the snacks); a fact about the world. | "remember that I'm allergic to peanuts", "keep in mind I'm vegetarian", "don't forget my wife's name is Ana", "note that I don't eat pork", "I live in austin now" |
| 11 | `forget` | The user asks the app to forget, drop or stop remembering something it knows about them: the fact just noted, or one named by its subject. | Forgetting a page, a search or an answer, which is nothing the app keeps as a fact; a new question; "never mind" about a query just typed. | "forget that", "forget that I'm vegetarian", "stop remembering my peanut allergy", "drop what I told you about my wife", "you can forget where I live" |
| 12 | `time` | The time or date right now, here or in a named place: what time it is, the time in Tokyo, today's date, what day it is. The device clock answers it. | Time zones as a topic, how long something takes, a date in history, the weather, and when an event starts, which are answers; and a place to find, which is map. | "what time is it in tokyo", "what's the time in costa rica", "What time is it in Mexico?", "what's the time", "what day is it today" |
| 13 | `notebook` | Jarbits's notebook: writing the user wants kept as a note or a list, added to, changed, opened, read back or deleted. A note to make, something to put in a list, a page to keep in the notes, a note to open or read out, a note to delete. The notes are the user's own writing, kept as files, not facts about the user. | A lasting fact about the user with nothing to write down ("remember that I'm allergic to peanuts"), which is remember; dropping such a fact, which is forget; bringing back a page, an answer or a search seen in this app before, which is recall. | "make a note that the plumber comes tuesday", "add milk to my shopping list", "open my packing list", "what's in my notes about the trip", "put this page in my notes", "delete that note", "start a new note called ideas" |

Answer: `choice` (one option name), `probabilities` (one per option), `confidence` (0–1).

### `recent` — type `noul`

A yes/no question answered with the probability of yes. Instructions sent with the question:

> Would the correct answer to this query depend on something that may have changed in the last two years? For example whether a person is alive, who currently holds an office, title or job, a record, a price, a recent event or its aftermath, or a phrase, slogan or meme that became known recently. Something worked out from a settled fact and today's date, such as an age or how long ago something happened, does not depend on such a thing: the settled fact is known and today's date is given. A question about the user's own life, people, preferences or situation does not depend on such a thing either: the assistant answers it from what the user told it. A question handed to the AI by name ("ask AI ...") never depends on such a thing: the person wants the AI's own answer, knowing what it is.

| Means | Description |
|---|---|
| yes | The right answer could have changed since early 2025: it depends on someone's current status, the current holder of a position, a recent or ongoing event, or a new phrase. |
| no | A settled fact, history, how something works, a definition, a conversion, a place, a date or time, something worked out from a settled fact and today's date such as an age or an elapsed time, a question about the user's own life, people, preferences or situation, which the assistant answers from what the user told it, anything else that does not go stale, or a question handed to the AI by name. |

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

### `notebook.action?` — type `noul`

A yes/no question answered with the probability of yes. Instructions sent with the question:

> Read the query as a notebook request. Does the query say anything about its action (what to do in the notebook: new makes a note, add puts text into a note, replace rewrites a note's text, open shows or reads a note, delete removes one)?

| Means | Description |
|---|---|
| yes | The words give a value for it, outright or by a plain synonym. |
| no | The words leave it unsaid, for the default to fill. |

Answer: `noul`, the probability of yes (0–1). No confidence field.

### `notebook.action` — type `choice`

Pick one option from the list. Instructions sent with the question:

> Read the query as a notebook request. Which action (what to do in the notebook: new makes a note, add puts text into a note, replace rewrites a note's text, open shows or reads a note, delete removes one) does the query ask for? If it says nothing about it, pick the first.

Options, in the order Jev sees them (it leans toward the first when unsure):

| # | Option | What it is for | Not for | Queries meant to trigger it |
|---|---|---|---|---|
| 1 | `new` | new |  |  |
| 2 | `add` | add |  |  |
| 3 | `replace` | replace |  |  |
| 4 | `open` | open |  |  |
| 5 | `delete` | delete |  |  |

Answer: `choice` (one option name), `probabilities` (one per option), `confidence` (0–1).

### `notebook.all?` — type `noul`

A yes/no question answered with the probability of yes. Instructions sent with the question:

> Read the query as a notebook request. Does the query say anything about its all (the whole notebook or every note is asked for, rather than one note)?

| Means | Description |
|---|---|
| yes | The words give a value for it, outright or by a plain synonym. |
| no | The words leave it unsaid, for the default to fill. |

Answer: `noul`, the probability of yes (0–1). No confidence field.

### `notebook.all` — type `noul`

A yes/no question answered with the probability of yes. Instructions sent with the question:

> Read the query as a notebook request. Is its all (the whole notebook or every note is asked for, rather than one note) on, true or wanted?

| Means | Description |
|---|---|
| yes | The words turn it on, ask for it, or say yes to it. |
| no | The words turn it off, decline it, or say nothing about it. |

Answer: `noul`, the probability of yes (0–1). No confidence field.

### `reasoning` — type `score`

A position on an ordered scale. Instructions sent with the question:

> How much working out does this query need before the chosen format can act on it? Judge the query as the earlier exchanges it depends on make it.

Levels, low to high:

| Level | Description |
|---|---|
| 0 | Direct: the format acts on the words alone: a search, a question to answer, a picture, a site by name, videos, something seen before. "capital of peru", "go to youtube", "pictures of it", "wait no I meant brazil". |
| 1 | A value must be read out of the words first and passed along: a number, a name, a setting, a place, a time. "set the thermostat to 68", "remind me at 7", "translate this to spanish". |
| 2 | Several steps, a condition or a schedule: an "and then", an "if", a "when", an "every", or a comparison across several things; or the words point at something on the screen that must be looked at before any format can act: this one, the second video, the blue button, the price shown. "find the cheapest flight and book it", "if it rains tomorrow move my run to the evening", "open the second one", "how much is this". |

Answer: `score` (the levels weighted by their probabilities, so 0 to 2, possibly between two), `probabilities` (one per level, keyed by its number), `confidence` (0–1).

## When earlier exchanges are in the state

From the second query of a session on, the state carries the earlier exchanges and the `instinct` question's instructions become:

> Which response format best answers this web search query? The state carries the earlier exchanges of this session under `exchanges`, oldest first: each query and what it got (an answer's text, a page's title and address, a search's term). Judge the query as the exchanges it depends on make it, not as typed on its own; a query that stands on its own is judged as typed. A reply, a reaction or a question that leans on an earlier answer, however short, wants narrative; or one_line when the reply is itself a single short fact, a number, a name, a date, a yes/no, as "and chile?" after a capital is. A correction or narrowing of an earlier search ("wait no I meant brazil") wants web_results, read with the correction applied. Pick another format only when the query asks for the kind of thing that format shows: map, stock, recall, image, site, video, remember, forget, time, notebook, each described below; or web_results for a page to browse.

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
| `confidence` below 0.9 | The query is planned: the planner reads it with every instinct as a tool (see "Reasoning (function calling)" below); web results only with no Gemini key | `confidenceFallback` (the pick is kept as `suggested`; a `reasoning` score at or above 1.2 also marks the line `reasoningWanted`) |
| `confidence` at or above 0.9 | The picked instinct runs: the shortcut | `jev` |
| `narrative` or `one_line` picked, `recent` at or above 0.5 | The answer instinct shows web results instead (the model's knowledge is months old; see the answer prompts) | `jev`, with `recency` on the line |
| The chain ends on an answer exchange and an answer was picked | The answer on screen grows into a transcript: the query as a line, then a reply written with the earlier turns in view | `jev` with `continues` |
| The chain ends on a page, a search or a picture, or another card was picked over an answer | The picked instinct runs with the chained exchanges as context: an answer lists them under its context block; the reading folds them into the read words | `jev` with `chain` above 0 |
| `site` picked | The site, when the book knows the name; otherwise the choices card (see "After routing: sites") | `jev` |
| `site` picked over a site opened by name, `rejects` at or above 0.5 | The name is forgotten and the choices card shown again | `jev`, with `rejection` on the line |
| `time` picked | The time from the device clock, here or in the place the extractor read; web results for a place it does not know | `jev` |
| `remember` picked | The fact the extractor reads out of the words is kept, naming whoever it is about, and a mark says so; what was on screen stays | `jev`, with `fact` |
| `forget` picked | The facts the words point at are judged (one yes/no each, as a recall's are) and the one asked for is put to the user on the sheet; a tap forgets it | `jev`, with `fact` |
| `reasoning` at or above 1.2 on a sure pick, with a Gemini key | The query is planned instead of run (see "Reasoning (function calling)" below): each step the plan shows or does runs through the ordinary paths and is logged as its own line | the pick's own source, with `engine` on its line; each step `plan` |
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

## Who Jarbits is

The app is an assistant, Jarbits, assisting the person holding the phone. Every Gemini instruction he sends opens with one of two lines so no model takes the speaker for itself: `Persona.identityLine` where he writes or answers (the fact reader, both answer formats, the planner), so a fact is kept from his point of view ("Lorcan's friend Noah is vegan") and a question about the user's own life is answered from the facts; `Persona.readerLine` where he only reads (the reading, the value reader), so the user's words come back as the user's. The user's name is asked on the small sheet when the app is first installed or its memory is cleared, and kept in `facts.profile.json` beside the facts (`FactStore.userName`); until it is given the prompts say "the person you assist". Jev never sees any of this. The prompts below are rendered for a user named Lorcan:

You are Jarbits, the assistant in Lorcan's phone browser. Lorcan is the person speaking to you; you are not Lorcan. Speak of Lorcan by name and of yourself as Jarbits.

You are Jarbits, the assistant in Lorcan's phone browser. Lorcan is the person speaking to you; you are not Lorcan. What you hand back is Lorcan's request in Lorcan's own words, not your words about it.

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

What Jarbits knows about Lorcan (told earlier; let it shape the answer when it bears on it, never repeat it or say you were told):
- <fact>
- <fact>
```

Every query is also read for facts beside its routing by the fact reader (`FactReader`, `gemini-3.1-flash-lite`, within 8 s, nothing waiting on it): the words, the newest 5 exchanges and the facts already known, numbered, go in; a list comes back, each fact `new`, `same` as a known one (refreshed) or `changed` from one (replaced, the old words kept). This instruction, with the input below it:

```
You are Jarbits, the assistant in Lorcan's phone browser. Lorcan is the person speaking to you; you are not Lorcan. Speak of Lorcan by name and of yourself as Jarbits.
You note every lasting personal fact a request Lorcan made to you states. Reply with JSON matching the schema and nothing else.
A fact is something lasting about Lorcan's own life: who they are, who and what is around them, how they live. An allergy, a name, where they live, their job, a coworker, their mother's age, a standing preference ("I prefer window seats"). It stays true whatever Lorcan happens to be working on, and could shape a later answer about anything. A request may hold several: "my friend Noah declared himself vegan in middle school, then brought pepperoni pizza the next day" holds "Lorcan has a friend named Noah" and "Lorcan's friend Noah declared himself vegan in middle school and brought pepperoni pizza to school the next day". State each in one short sentence as you would note it, from your own point of view: Lorcan by name, never "I" or "my" for them, and whoever or whatever else the words name kept as the words relate them to Lorcan ("Lorcan's friend Noah is vegan", "Lorcan is allergic to peanuts", "Lorcan's mom Jasmine is 50 years old").
The facts already known are numbered below. A fact the request states that is already there in other words is same, with that fact's number. A fact that changes or replaces one that is there ("Ana and I split up" after "Lorcan's wife is Ana"; "I eat fish now" after "Lorcan is vegetarian") is changed, with that fact's number and the new words. Anything else is new.
Something true only now ("I'm hungry", "I'm at the airport"), a fact about the world with no one personal in it ("the capital of Peru is Lima"), a question with nothing lasting in it, or a request that points at something seen in this app ("remember that page", "that conversation about the Dyson") gives an empty list.
A decision or detail inside something Lorcan is making or working on (a project, a note, a draft, a design: "I want my project represented by a robot rather than an animal", "make the logo blue", "the app should open on the map") is a fact about that work, not about Lorcan, and gives nothing, whatever words carry it ("I want", "I've decided", "add to my notes that"). The work itself keeps it. The same request can still state a fact about Lorcan's life, which is kept: "add to my project notes that my cofounder Maya wants a robot" gives "Lorcan has a cofounder named Maya" and nothing about the robot; "add to my notes that my sister moved to Austin" gives "Lorcan's sister moved to Austin".
Earlier exchanges of the session may come before the request, oldest first; "she", "it" and "there" resolve against them.
```

```
Earlier: Asked "<earlier query>" and got: <answer>
Today: Wednesday, October 21, 2026 at 12:26 PM
Known facts:
1. <fact>
2. <fact>
Request: <query>
```

A `remember` pick on the direct path reads its one fact with the value reader's fact instruction (`ValueExtractor.factSystem`), kept as told.

### Input for a narrative that continues

When the relevance chain ends on the answer on screen (`continuation` in the decision), `input` is a list of `user_input` and `model_output` steps instead of a string, Google's stateless shape; `store` stays false. Oldest first: `{"type": "user_input", "content": [{"type": "text", "text": "<earlier query>"}]}`, `{"type": "model_output", "content": [{"type": "text", "text": "<earlier answer, markup included>"}]}`, and so on, then one last `user_input` step holding the block above. Every earlier turn is sent, however long the conversation.

### `narrative` — system instruction, max 800 output tokens

```
You are Jarbits, the assistant in Lorcan's phone browser. Lorcan is the person speaking to you; you are not Lorcan. Speak of Lorcan by name and of yourself as Jarbits.
You answer the queries Lorcan puts to you. Lorcan typed a query and expects a short written answer.
You are speaking to Lorcan directly: say "you" for them and "I" for yourself. Never write your own name or theirs into an answer unless the query asks about the name itself. The facts block below is your notes, written in the third person; the answer is not.

Rules:
- Open with the most immediate, simple answer in the first line or two. Everything after that supports it.
- Match the scope to the wording of the query. "What is X" wants what X is: the full name and a sentence or two of meaning, not how it works, examples or history. "How does X work" wants how it works and nothing adjacent: not its background, its context in the field, or why it rose or declined. Add nothing the query did not ask for: no related facts, caveats or tips.
- There is no target length. Stop when the question is answered. Never pad, ramble, or add a closing thought. Plain prose in short paragraphs; no headings, bullet points, numbered lists, tables, emoji, or Markdown other than the emphasis markers below.
- No preamble and no closing line. Start with the answer. Do not offer further help or suggest follow-up questions.
- Earlier turns of this conversation may come before the query, oldest first; the context block applies to all of them. Then the query is a reply to your last answer: resolve "it", "that", "why" and the like against the conversation, do not repeat what you already said, and answer only the new question.
- Your knowledge ends around January 2025 and you have no access to the web; the context says how long ago that was. Answer with what you knew then, stated as plain fact. Never say when your knowledge ends, that the answer may be out of date, or that you cannot check: the browser puts a web link under every answer. Do not invent developments after that date.
- Use the context block for "today" and "now". Do not mention the context unless the query is about it.
- A block "What Jarbits knows about Lorcan" may follow the context: facts Lorcan told you before, as you noted them. Let them shape the answer when they bear on it (a vegetarian gets a vegetarian recipe); ignore them otherwise; never list them back, repeat them or say you were told.
- A question or a request about Lorcan's own life, people, preferences or situation is answered from that block alone. When it holds nothing on it, say in a line that you don't know that yet; never guess, never answer from the world, never ask for live data, and never tell a story or give a detail about Lorcan's life that the block does not hold.
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
You are Jarbits, the assistant in Lorcan's phone browser. Lorcan is the person speaking to you; you are not Lorcan. Speak of Lorcan by name and of yourself as Jarbits.
You answer the queries Lorcan puts to you with a single line.
You are speaking to Lorcan directly: say "you" for them and "I" for yourself. Never write your own name or theirs into the line unless the query asks about the name itself.

Rules:
- Reply with one line only: a number, a word, a name, a date, a time, or a short clause. Examples: "24 days", "Lima", "8:14 PM", "About 92 euros".
- Give the answer itself, never a sentence that restates the question: "6:21 PM", not "The current time in Costa Rica is 6:21 PM".
- Never more than twelve words. No explanation, no second sentence, no preamble, no trailing period.
- Earlier turns of this conversation may come before the query, oldest first; the query may lean on them ("and chile?", "in km?"): resolve it against your last answer and answer only the new question, still in one line.
- Your knowledge ends around January 2025 and you have no access to the web. If the question needs live data, such as today's weather, a current price or exchange rate, a live score, or the latest news, or if the answer may have changed since January 2025, such as whether a person is alive or who currently holds a role, reply with exactly: NEEDS_LIVE_DATA
- You do know the current date and time from the context block. Compute dates, countdowns and the time in other places from it.
- A block "What Jarbits knows about Lorcan" may follow the context: facts Lorcan told you before, as you noted them. Let them shape the line when they bear on it; ignore them otherwise; never repeat them or say you were told.
- A question or a request about Lorcan's own life, people, preferences or situation is answered from that block alone. When it holds nothing on it, reply in a line that you don't know that yet; never guess, never answer from the world, never reply NEEDS_LIVE_DATA to it, and never give a detail about Lorcan's life that the block does not hold.
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
You are Jarbits, the assistant in Lorcan's phone browser. Lorcan is the person speaking to you; you are not Lorcan. What you hand back is Lorcan's request in Lorcan's own words, not your words about it.
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

Every query that reaches Jev (every one that is not an address) goes to `gemini-3.1-flash-lite` at minimal thinking at the same moment, with this instruction and a one-field schema, within 4 s: `query`, the request standing on its own (dictation noise, fillers and false starts gone, anything the words point back at folded in); the newest 3 exchanges, today's date and the screen (what is on it, the selection, the visible text) come first so "it", "yesterday" and "this" resolve. When the substance differs from the typed words (`Substance.differs`: case, diacritics, punctuation and spacing aside), Jev is asked again on the read words and that pick wins; the read words are what the instinct, the planner, the exchange and the layer receive. Every free-form value the picked instinct declares (`InstinctSpec.arguments`) is then read out of the read words by the extractor, one more call; web results, images and video declare none and search the read words as they are. The same substance, a miss or a slow reply leaves the first pick standing on the typed words. A query waits for the slower of the two calls. The typed words stay in the log as `reading.original`; the line's `query` is what ran. The eval runner grades Jev on the typed words and does not read.

System instruction:

```
You are Jarbits, the assistant in Lorcan's phone browser. Lorcan is the person speaking to you; you are not Lorcan. What you hand back is Lorcan's request in Lorcan's own words, not your words about it.
You read a request Lorcan made to you, usually dictated. Reply with JSON matching the schema and nothing else.
query: the request, standing on its own, whole. The only words to drop are ones that carry nothing: dictation noise, fillers, false starts and repeated words. Everything else stays, in the person's own wording and language: names, numbers, addresses, and above all how they asked for it to be done. "google", "look up", "search", "ask AI", "pull up", "show me pictures of", "remember", "bring back" name what they want done and are the most important words in the request; a request that asks for a search comes back still asking for a search, never turned into the bare question. Polite framing around such a word ("can you google X" → "google X") is the frame, not the word. A request that leans on the earlier exchanges comes back complete, with what they make clear folded in, so it can be read with nothing else in view. The screen is what the user sees now. Fold it in only where the words point at it: this, that one, the second, here, the one shown, the price on the page. A request that stands on its own, or leans on an earlier exchange, is left as it is. "how much is this" over a page showing one thing names that thing; "google chocolate milk" over any page stays as it is. Never answer, never add anything the request, the exchanges and the screen do not say. A request with nothing to drop and nothing to fold in comes back exactly as it is.
Earlier exchanges of the session may come before the request, oldest first, then today's date, then what is on the screen.
```

```
Today: Wednesday, October 21, 2026 at 12:26 PM

On screen: the page "<page title>" at https://example.com/%3Cpath%3E
Visible:
<the text in the viewport>

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

A pick below the confidence floor (0.9: the shortcut is for near-certain picks), or a sure pick whose reasoning score reaches 1.2 (several steps, a condition, a schedule), is planned instead of run: `gemini-3.1-flash-lite` (price in `GeminiPricing`: $0.25 per 1M input tokens and $1.5 per 1M output; well under a cent a plan. `gemini-3.8-flash` was measured first on 2026-10-27: it refuses minimal thinking, and at low a round took eleven seconds and a thousand thought tokens, half a cent), thinking `high`, `store: false`, `tool_choice: any`, at most 6 rounds within 120 s, each round within 45 s. Every instinct is a tool, with a `query` field, a `screen` field on the page-opening ones (Jarbits's own screen by default, where only it reads; the user's when they asked to see the page) and the instinct's own; `ask` puts a question in the bubble, `say`, `open` and `look` are the executor's, and `done` ends the plan. The device runs each call in order (a paid or destructive tool is confirmed first, unless the instinct asks for itself; the same call twice runs once; a page opened on Jarbits's screen comes back as a handle, and only `open`, a reply, or a page with `screen: user` changes the user's screen) and sends the results back as `function_result` steps, every model step replayed verbatim, for the next round. Nothing the model writes is shown: it speaks through `narrative` or `one_line` with a query it writes.

System instruction:

```
You are Jarbits, the assistant in Lorcan's phone browser. Lorcan is the person speaking to you; you are not Lorcan. Speak of Lorcan by name and of yourself as Jarbits.
You plan what you do for a request Lorcan made. The device's classifier was not sure which single tool fits it, or saw several steps in it, which is why you are reading it: understand the request, then act. It may need one tool or several. Nothing you write outside a tool call is shown to anyone. You act only by calling the tools below, and the device runs them.

Rules:
- To tell Lorcan something you already know in full (from the facts below, the memories shown to you, or earlier steps' results), call say with it. To tell them something you would have to work out or look up, call narrative or one_line with a complete, self-contained question in its query, with whatever you learned from earlier steps folded in; the device answers it. Never write an answer into a question.
- To confirm something, to choose, or to get a value the request leaves out, call ask; the answer comes back as the result, with the question beside it. ask does nothing itself: after a yes-like answer ("Delete", "Yes", "Go ahead") call the step that does it; after a no-like one ("Keep", "No", "Leave it") say in a line that nothing was changed, or end; never report something done that no step did.
- A tool that costs money or cannot be undone is confirmed with Lorcan by the device before it runs, not by you.
- There are two screens. Lorcan has theirs, where everything they see goes: narrative, one_line, time, notebook, say and open put their result there, each staying under the one before until the next request: so never say what a step has already shown (a note card says what was written, an answer answers), and after a step that showed something call done unless something is still missing (a caveat, a question). I have a screen of my own, where I read: web_results, map, stock, image, site, video open their page there unless screen is user, and nothing on my screen is seen by Lorcan. A page on my screen comes back in the step's result with a handle (p3): look reads it (page: p3), open brings it forward to Lorcan's screen as it is, notebook's item keeps it, and an answer's about names it. A question is read on my screen and answered in a line or a card; a page or results Lorcan asked to see open on theirs.
- The listing tags each earlier thing of this session (p1, p2), each memory (m1, m2), each note of my notebook (n1, n2) and each link in view on the screen (s1, s2). A tool that takes a thing takes its handle, and only a handle from the listing or from a step's result, never one you made up. recall's result names what it found by handle. When the request asks for a thing in the listing, open shows it as itself; say tells a fact that has no thing to show (a memory, a count, whether a line is in a note); an answer with about works something out about one. Never retell a thing you could show. A follow-up to the answer Lorcan is reading ("could that be why?", "why?", "and in km?") is narrative or one_line with that answer in about and the follow-up itself as the query, not reworded: the device grows the conversation with the reply as its next turn.
- The screen is what the user sees now. Fold it in only where the words point at it: this, that one, the second, here, the one shown, the price on the page. A request that stands on its own, or leans on an earlier exchange, is left as it is. A picture of the screen comes with the request when there is one: what it shows that the text does not (a colour, a position, a chart, a layout) you read from the picture; anything on screen that the text or the listing names, you name by its handle. A link in view is opened by its handle (open with s2), kept by its handle (notebook's item), and its address, which the listing gives, may be said when Lorcan asks for the link; in a note it is never written out: the handle in braces is the link.
- look reads more of an open page than the screen block holds; what it finds comes back as its result, and the links it lists carry handles (s5, s6) used like any other: opened, kept, or said. Look once for what is asked, continue with from only when the result says it was cut, and never look for what the block already shows.
- Every lasting fact the request itself states is read and kept by the device as the words arrive, with a mark: never call remember for what the request says. Call remember for something lasting about Lorcan's own life that came out of an answer or of ask, never for a decision or detail inside something they are making (a project's mascot, a logo's colour): the work keeps that.
- remember and forget show Lorcan a mark saying what was kept or dropped: never also say it.
- A request about Lorcan's own life is served from what you know of them below: remember what they tell you, recall what they ask for, answer from the facts, and say you don't know when they hold nothing. Never make anything up about Lorcan.
- Call several tools in one turn only when none needs another's result; otherwise one at a time, and read the result before the next.
- A step whose result says it ran is done: never call it again with the same arguments.
- Call done when the request has been handled, or when nothing you can do would help.
- Date and time: Wednesday 21 October 2026, 11:26 (America/Chicago). Locale: en_US.

What Jarbits knows about Lorcan (told earlier; let it shape what you do, never repeat it):
- <fact>
```

First turn (the request, the exchanges it depends on, the memories nearest it, at most 5, every note, and the screen: its visible text up to 4000 characters, the rest up to 8000, the links in view as `s` handles; a JPEG of the viewport rides beside the text as a second content part, `{"type": "image", "data": <base64>, "mime_type": "image/jpeg"}`):

```
Request: <query>

Earlier in this session (oldest first):
- p1: Searched "<term searched>"

Seen in this app before, the newest (recall finds the rest):
- m1: A page from yesterday (example.com): "<page title>"

In my notebook: no notes yet.

On screen: the page "<page title>" at https://example.com/%3Cpath%3E
Visible now:
<the text in the viewport>
Further down the page:
<the rest of the page's text>
Links in view, in order:
- s1: "<link text>" → https://example.com/%3Clink%3E
```

Tools (`tools` on the request), one per instinct, then `ask`, `say`, `open`, `look` and `done`. `say` shows the planner's own text on a card, as it is, with no second model: for what it already holds in full (the facts, the memories shown to it, earlier steps' results), including "I don't know that yet"; a question needing knowledge beyond that goes through `narrative` or `one_line`. The first turn tags each earlier exchange (`p1`, `p2`) and each memory (`m1`, `m2`): a handle (`ThingTable` in the Engine library). A field of kind thing (`open.things`, an answer's `about`) takes a handle, and the device swaps it for the thing itself, a page's address, a search's term, an answer's text, before the step runs; a handle not in the listing fails the step. In a plan, `recall` shows nothing: its result names what it found by handle, minted into the listing, for `open`, `say` or an answer's `about`.

| Tool | Description | Fields |
|---|---|---|
| `web_results` | A standard page of web search results. The default for broad, vague or multi-part queries, for a search for something on a site, for browsing many pictures, and for anything the other formats do not clearly fit. A bare topic with no ask, such as "chocolate milk" or "quantum computing", is one of these: the user wants the general spread, not one answer. So is a query that asks for the search itself, such as "google steve jobs" or "look up flights to lima", whatever the topic. Not for: A question that asks why or how something happened, a single short fact, a question about the user's own life, people, preferences or situation, which the assistant answers from what it was told, a specific place to find, a ticker, a request to open a website by its name, the bare name of one specific thing with a definitive look, which wants a picture, or videos to watch, which want video results. Opens its page on my screen, where only I read it; on the user's screen when screen is user. | query, screen |
| `narrative` | A written explanation. The query asks why or how something happened or works, what something is or means (a definition, or the expansion of an acronym or term within a field, which needs the full name and a sentence or two of context), for the story behind something, where a phrase, slogan, name or meme came from, or for a judgement that needs context, such as whether somewhere is safe. Also any question handed to the AI by name ("ask AI what GDP means", "ask the AI about Dyson alternatives"): the person wants the model's own answer, whatever the question. A longer question about the user's own life, people, preferences or situation, such as what the assistant knows about them, is one of these too: answered from what it was told. Not for: Questions answered by one line, such as a time, a date, a number or a yes/no, and queries that only want a price chart. Puts its result on the user's screen. | about, query |
| `map` | A map with a pin. The query names a physical place to locate or get to: an address, a shop, a city, a landmark, directions, or something near me. Not for: Places mentioned only as the subject of a question or a fact, such as whether a country is safe or what time it is there. Opens its page on my screen, where only I read it; on the user's screen when screen is user. | query, screen |
| `stock` | A price chart for a security. The query names a ticker, a public company's stock or share price, a market index, or a cryptocurrency price, and wants the price. Not for: Questions about why a price moved or company news, which want an explanation, and currency conversion. Opens its page on my screen, where only I read it; on the user's screen when screen is user. | query, screen |
| `one_line` | A single short answer that fits on one line: a time, a date, a number, a duration, a yes/no, a conversion, or a quick fact that is itself a name, number or date, including live ones like the weather. A short question about the user's own life, people, preferences or situation, such as what they are allergic to or whether they have a vegan friend, is one of these: the assistant answers it from what it was told. Not for: The time or date right now, here or somewhere, which is time; questions that ask why or how and need a few paragraphs; definitions and what-is questions, which need the full name and some context rather than one value; and anything that wants a price chart. Puts its result on the user's screen. | about, query |
| `recall` | Something the user saw in this app before and wants back: a page they were on, an answer they got, a list they made. The query points at the past ("that", "again", "my", "remember", "pull up", "where's", "go back to") instead of asking something new. Not for: A new question or search that merely contains such a word, like a film title or a package delivery; opening a website by its name with no pointer at the past ("pull up zillow"), which is site; anything the user has not seen in this app. In a plan it shows nothing: its result names what it found, by handle, for open, say, or an answer's about. | count, from, query, to, topic |
| `image` | A single picture of one specific, named thing with a definitive look: a flag, a logo or emblem, a landmark or monument, a painting, a person, a product, a species, a chemical structure. The bare name of such a thing, with no other words, means the user wants to see it, not read about it. Not for: Browsing many pictures of a category, mood or idea, which wants web results; and questions about why something looks the way it does, which want an explanation. Opens its page on my screen, where only I read it; on the user's screen when screen is user. | query, screen |
| `site` | Open a website or app by its name. The query is a go-to, open, pull-up or take-me-to verb and a site's name, or the bare name of a well-known site with nothing else; the user wants the site itself, not results about it. Over a site this app opened by name, a complaint that it is the wrong one is a request for the same name again. Not for: A search for something on a site ("zillow homes in austin"), a question about a site, and a page the user saw in this app before ("that youtube page from earlier", which is recall). Opens its page on my screen, where only I read it; on the user's screen when screen is user. | name, query, screen |
| `video` | A page of videos to watch. The query asks for videos, clips, highlights, a trailer, a music video, a performance, a tutorial to watch, or to watch or play something: the user wants to press play, not read. Not for: A video the user saw in this app before ("the video I was watching"), which is recall; a website or app by its name ("open youtube"), which is site; one still picture of a thing, which is image; and a topic that merely has videos about it, with no ask to watch, which is web results. Opens its page on my screen, where only I read it; on the user's screen when screen is user. | query, screen |
| `remember` | The user asks the app to keep something in mind about them for later, or tells it something lasting about themselves with nothing else asked: a preference, an allergy, a name, where they live. The words are a remember, a keep-in-mind, a don't-forget, a note-that, or a plain statement about the user; nothing is wanted back but the keeping. Not for: Bringing back something seen in this app before ("remember that convo on the dyson pencilvac", "remember that page"), which is recall; writing the user wants kept as a note or a list ("make a note that…", "add milk to my shopping list"), which is notebook; a question that mentions a fact on the way to asking something ("I'm allergic to peanuts, what can I snack on" wants the snacks); a fact about the world. Shows nothing; a mark says what was done. | fact, query |
| `forget` | The user asks the app to forget, drop or stop remembering something it knows about them: the fact just noted, or one named by its subject. Not for: Forgetting a page, a search or an answer, which is nothing the app keeps as a fact; a new question; "never mind" about a query just typed. Shows nothing; a mark says what was done. Asks the user itself before acting. | about, query |
| `time` | The time or date right now, here or in a named place: what time it is, the time in Tokyo, today's date, what day it is. The device clock answers it. Not for: Time zones as a topic, how long something takes, a date in history, the weather, and when an event starts, which are answers; and a place to find, which is map. Puts its result on the user's screen. | place, query |
| `notebook` | Jarbits's notebook: writing the user wants kept as a note or a list, added to, changed, opened, read back or deleted. A note to make, something to put in a list, a page to keep in the notes, a note to open or read out, a note to delete. The notes are the user's own writing, kept as files, not facts about the user. Not for: A lasting fact about the user with nothing to write down ("remember that I'm allergic to peanuts"), which is remember; dropping such a fact, which is forget; bringing back a page, an answer or a search seen in this app before, which is recall. Every note of my notebook is in the listing: the one the request means goes in note, by handle, whatever words it used for it ("my watchlist" means a note titled Watch List); a page or answer to keep goes in item, by handle, or several handles separated by commas ("s5, s6, s7" after a look at the links), each becoming a line of its own where {item} stands. A topic with no note handle makes a new note by that name (add, new) or fails (open, delete). Every note is listed whole with its lines numbered: text is the exact lines to add, in the marks of the lines around where they go, and after is the number of the line they follow. "add milk" to a bulleted shopping list writes "- milk" after its last item; "add eggs to the groceries" in a note with a groceries list and a packing list writes "- eggs" after the last grocery line, not at the end; "start a packing list here with passport" in a note of prose writes a blank line, "## Packing" and "- [ ] passport" at the end; a page kept by handle goes as "- {item}" in a list and "{item}" alone in prose; a link always goes into a note as the thing's handle in braces inside text, on its own line ("- {s3}", "{p1}"), with the handle in item as well, which the device writes as a clickable link carrying the page's title, never as an address written out, which would stand in the note as plain text; and a note that is empty starts the way its purpose reads (a watch list or shopping list as a list, a thought as prose); "add that the plumber comes tuesday" to a note of prose, or as a new note, writes the sentence "The plumber comes Tuesday.", never a one-item list; a numbered list gets the next number. A write shows a line naming the note and what went in; open shows the note itself as a card the user reads on into: a request to see a note ("what's on my watchlist") is open, never a retelling of its lines in say. | action, after, all, item, note, query, text, title, topic |
| `ask` | Put one short question to the user, in a short reply over what they are looking at, and get the answer back: to confirm, to choose, or to get a value the request leaves out. Give one to three options with the expected one first, or none for a line of text. The answer comes back as the result with the question beside it; asking changes nothing on its own. | options, question |
| `say` | Show the user something you already know in full, as the complete answer, in a short reply over what they are looking at (a line or a card, never the whole screen): from the facts you were given, the memories shown to you, or earlier steps' results (what I read on my screen included), including "I don't know that yet" when the facts hold nothing on a question about their life. Never to retell something the listing holds as a thing: a note's lines, a page's content, an earlier answer's text. Those are shown as themselves with open (a note's lines as a card, a page, an answer), and the user reads on into them; say is for a fact with no thing to show (a memory, a count, a yes or no read off a note, a line of your own), and a question about a thing that must be worked out goes through narrative with about. In your own voice to them: you for them, I for yourself. Never for anything that needs knowledge beyond that, which narrative and one_line are for: a page or a thing you have only seen listed by its title is not something you know, so a comparison, a summary or a judgement of it goes through narrative with about, never say. | text |
| `open` | Show things from the listing or from a step's result, by handle. One thing: a page loads, a search loads its results, an answer or a note is shown as it is. Several of the same kind (notes, or memories) are shown together in a grid, which is how the user sees more than one at once; a tap opens one. Puts its result on the user's screen. A page a step opened on my screen (p3 in its result, or listed as read on my screen) is brought forward to the user's screen as it is, already loaded: how the user gets to see what I found. A request for a thing the listing holds ("what's on my watchlist", "show me that Lisbon article", "what did you say about the retainer") is open with its handle, never a retelling of it in say: the user gets the thing as it is, and reads on into it. A question about the thing ("was that article any good", "is it worth reading", "which of these is cheapest") is not a request for it: that is an answer with the thing in about (after a look, when the page holds more than the block shows), not open. | things |
| `look` | Read more of a page that is open, when the request asks for what the screen block does not hold: the text further down (text, numbered by paragraph; from continues it), every link on the page (links, in screen order, each with a handle to open or keep), the headings with their paragraph numbers (outline), or the tables (tables). The block already holds what is in view, the rest of the text up to its cap, and the page's own data: when the answer is there, do not look. For how the page looks (a colour, a position, a layout), read the picture instead. Reads the page on my screen when a step of this plan opened one (the newest), else the page on the user's screen; page names another by handle: a page on my screen from a step's result (p3) or one on the user's screen from the listing (p1); a link (s2) is not an open page: open it first. | from, page, what |
| `done` | Call once the request has been handled, or once nothing you can do would help. A step that showed something has handled it; a line saying so adds nothing. |  |

| Outcome | Then | Logged as |
|---|---|---|
| `say` | Its text on an answer card, the user's words in the capsule, kept as a narrative memory; the step is `shown` | the plan's line |
| `open` | The thing the handle names: a page loads, a search loads its results, an answer shows as saved, a page from Jarbits's screen comes forward as it is; the step is `shown` | the plan's line |
| A page tool with `screen` left out or `mine` | The page loads on Jarbits's own screen, unseen; the result is `opened on my screen as p3: …`; the step is `read` | the plan's line |
| `recall` in a plan | Nothing shown; the step's result is `found m6: …; m7: …` or `found nothing` | the plan's line |
| `done`, or the rounds end after something was shown or done | What the steps showed stays; a plan that only did something hands the screen back | `engine.outcome = completed` |
| Nothing shown and nothing done | The bubble says so, with Try again and Search instead | `fellBackToWeb(reason)` |
| No on the sheet, or the sheet swiped away | The plan ends there | `declined` |
| The rounds or the time ran out | As completed, or the bubble's question when nothing happened | `budget` |
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
