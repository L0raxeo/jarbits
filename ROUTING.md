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
| `previous_queries`, `previous_answer` | Only while a narrative or one-line answer is on screen and the query was typed over it: every query of that conversation, oldest first, and the last answer cut to 1500 characters. The format question then reads differently and one more question is asked; see "When an answer is on screen". |
| `opened_site_name`, `opened_site_host` | Only while a site this app opened by name is on screen: the name asked for and the host opened. One more question is asked; see "When a site is on screen". |

Before any request: text that parses as an address (`example.com`, `https://…`) loads directly, and a query the device can decide itself becomes a card at once, opens a site the device already knows, or searches the term after a search verb; Jev is not asked in any of these cases.

## Decided on the device

The time in a named place needs no model. A query that is exactly one opener, a place and at most one trailer (case, accents and punctuation aside) is answered from the device clock when the place is a country, a US state or a city in the device's zone database; otherwise it goes on to Jev like any other query. English only.

- Openers before a place: "what time is it in", "what's the time in", "what is the time in", "what time is in", "what time in", "current time in", "local time in", "the time in", "time now in", "time in"
- Whole queries meaning the time here: "what time is it", "what's the time", "what is the time", "current time", "local time", "the time", "time now"
- Trailers, at the end or between "is it" and "in": "at the moment", "right now", "currently", "now", "today"

Shown as `==7:56 PM==`, with `tomorrow` or `yesterday` when the date there differs, and `in Mexico City` when the place spans zones. Logged as `local("time")` with none of the Jev fields.

A question handed to the model by name is the model's: "ask AI what are some alternatives to Dyson" is a narrative answer to "what are some alternatives to Dyson", with no format question asked and no recency gate, since the user asked for the model's answer knowing what it is. `AnswerQuery` reads the query as leads, one opener, at most one connective, the question and trailers; the question is kept as typed. Logged as `local("ask")`. Without a Gemini key the rule is skipped and the query goes on to Jev.

- Leads, any number, before the opener: "can you", "could you", "would you", "hey siri", "please", "hey", "ok", "okay", "just", "yo", "youll", "hi", "hello", "um", "uh", "alright", "yeah", "siri"
- Openers: "ask artificial intelligence", "ask the ai", "ask an ai", "ask your ai", "ask ai", "ask chatgpt"
- Connectives after the opener, at most one: "to tell me", "to explain", "about"
- Trailers, any number, at the end: "thank you", "for me", "please", "thanks"

A website the device already knows opens the same way. `SiteQuery` reads a query as leads, one opener, articles, a name and trailers; when an opener is present and the site book knows the name (37 seeded sites under 53 names, plus every name learned from a tap), the site opens with no model asked, logged as `local("site")`. A bare name, or a name the book does not know, goes on to Jev; a `site` pick then looks the name up or searches it (see "After routing: sites").

- Leads, any number, before the opener: "can you", "could you", "would you", "hey siri", "please", "hey", "ok", "okay", "just", "yo", "youll", "hi", "hello", "um", "uh", "alright", "yeah", "siri"
- Openers: "take me to", "navigate to", "go to", "goto", "head to", "pull up", "bring up", "open up", "open", "launch", "load", "visit", "show me"
- Articles after the opener: "the", "my"
- Trailers, any number, at the end: "home page", "web site", "dot com", "for me", "please", "now", "app", "website", "site", "page", "homepage", "com"

A query led by a verb that only ever means "search" is web results for what follows it, with no model asked, logged as `local("search")`. `SearchQuery` reads it as leads, one opener, the term and trailers; the term is kept as typed (case, apostrophes and punctuation included) because it goes into the search box. "google" is a verb too ("google steve jobs") but also a company, so it is not a command here: the query goes to Jev, and only a `web_results` pick drops it, and never when one of the product words below follows it ("google maps", "google stock").

- Corrections, any number, at the front, with or without an opener (a bare "no" is not one: "no man's sky"): "no not that one", "no not that", "no not this", "no i said", "no i meant", "not that one", "not that", "i said", "i meant", "i told you", "like i said"
- Leads, any number, before the opener: "can you", "could you", "would you", "hey siri", "please", "hey", "ok", "okay", "just", "yo", "youll", "hi", "hello", "um", "uh", "alright", "yeah", "siri"
- Openers that route on the device: "search google for", "search the web for", "search the internet for", "do a google search for", "do a web search for", "do a search for", "google search for", "web search for", "web search", "search for", "search up", "look up", "lookup"
- Dropped only after a web pick: "google", unless followed by "maps", "docs", "drive", "translate", "photos", "calendar", "flights", "sheets", "slides", "meet", "play", "pixel", "chrome", "gemini", "cloud", "home", "nest", "pay", "wallet", "ads", "analytics", "news", "scholar", "classroom", "keep", "fi", "one", "store", "stock", "shares", "earnings", "account", "assistant", "lens", "tv", "fiber", "workspace", "search", "io", "glass", "voice"
- Trailers, any number, at the end, with or without an opener ("steve jobs, I said"): "is what i said", "is what i meant", "like i said", "i said", "i meant", "i told you", "on google", "for me", "please"

The term is what is left with the punctuation that closed or opened the stripped phrases gone: "Dominican flag, I said." leaves "Dominican flag".

## The questions

### `format` — type `choice`

Pick one option from the list. Instructions sent with the question:

> Which response format best answers this web search query? Judge the query as typed. If several formats could work, prefer web_results.

Options, in the order Jev sees them (it leans toward the first when unsure):

| # | Option | What it is for | Not for | Queries meant to trigger it |
|---|---|---|---|---|
| 1 | `web_results` | A standard page of web search results. The default for broad, vague or multi-part queries, for a search for something on a site, for browsing many pictures, and for anything the other formats do not clearly fit. A bare topic with no ask, such as "chocolate milk" or "quantum computing", is one of these: the user wants the general spread, not one answer. So is a query that asks for the search itself, such as "google steve jobs" or "look up flights to lima", whatever the topic. | A question that asks why or how something happened, a single short fact, a specific place to find, a ticker, a request to open a website by its name, the bare name of one specific thing with a definitive look, which wants a picture, or videos to watch, which want video results. | "best laptops 2026", "news", "chocolate milk", "google steve jobs", "python tutorial reddit", "zillow homes in austin", "quantum computing", "golden retriever puppies" |
| 2 | `narrative` | A written explanation. The query asks why or how something happened or works, what something is or means (a definition, or the expansion of an acronym or term within a field, which needs the full name and a sentence or two of context), for the story behind something, where a phrase, slogan, name or meme came from, or for a judgement that needs context, such as whether somewhere is safe. | Questions answered by one line, such as a time, a date, a number or a yes/no, and queries that only want a price chart. | "at the end of attack on titan why is levi in a wheelchair", "how did simon cowell get famous", "why are highschool students protesting france?", "how is gingivitis healed", "Why is INTR so low?", "Is south africa safe right now", "where did the phrase ok boomer come from", "whats isi in ipe", "what does gdp mean", "define hegemony" |
| 3 | `map` | A map with a pin. The query names a physical place to locate or get to: an address, a shop, a city, a landmark, directions, or something near me. | Places mentioned only as the subject of a question or a fact, such as whether a country is safe or what time it is there. | "coffee near me", "directions to austin airport", "where is machu picchu", "blue bottle coffee san francisco" |
| 4 | `stock` | A price chart for a security. The query names a ticker, a public company's stock or share price, a market index, or a cryptocurrency price, and wants the price. | Questions about why a price moved or company news, which want an explanation, and currency conversion. | "nasdaq", "AAPL", "tesla stock", "bitcoin price", "s&p 500 today" |
| 5 | `one_line` | A single short answer that fits on one line: a time, a date, a number, a duration, a yes/no, a conversion, or a quick fact that is itself a name, number or date, including live ones like the weather. | Questions that ask why or how and need a few paragraphs; definitions and what-is questions, which need the full name and some context rather than one value; and anything that wants a price chart. | "what's the time in costa rica", "will it rain today", "how long do cold sores last", "capital of peru", "100 usd to eur" |
| 6 | `recall` | Something the user saw in this app before and wants back: a page they were on, an answer they got, a list they made. The query points at the past ("that", "again", "my", "remember", "pull up", "where's", "go back to") instead of asking something new. | A new question or search that merely contains such a word, like a film title or a package delivery; opening a website by its name with no pointer at the past ("pull up zillow"), which is site; anything the user has not seen in this app. | "where's my grocery list", "remember that convo on the dyson pencilvac", "pull up that youtube page from earlier", "pull up the video I was watching about muse", "that thing about gingivitis again", "go back to the reddit thread" |
| 7 | `image` | A single picture of one specific, named thing with a definitive look: a flag, a logo or emblem, a landmark or monument, a painting, a person, a product, a species, a chemical structure. The bare name of such a thing, with no other words, means the user wants to see it, not read about it. | Browsing many pictures of a category, mood or idea, which wants web results; and questions about why something looks the way it does, which want an explanation. | "dominican flag", "eiffel tower", "starry night painting", "nvidia logo", "what does a capybara look like", "mona lisa", "aston martin db5" |
| 8 | `site` | Open a website or app by its name. The query is a go-to, open, pull-up or take-me-to verb and a site's name, or the bare name of a well-known site with nothing else; the user wants the site itself, not results about it. | A search for something on a site ("zillow homes in austin"), a question about a site, a page the user saw in this app before ("that youtube page from earlier", which is recall), and an address, which loads directly. | "go to youtube", "pull up zillow", "open insta", "take me to airbnb", "launch netflix", "reddit" |
| 9 | `video` | A page of videos to watch. The query asks for videos, clips, highlights, a trailer, a music video, a performance, a tutorial to watch, or to watch or play something: the user wants to press play, not read. | A video the user saw in this app before ("the video I was watching"), which is recall; a website or app by its name ("open youtube"), which is site; one still picture of a thing, which is image; and a topic that merely has videos about it, with no ask to watch, which is web results. | "videos of pele", "pele highlights", "dune part 3 trailer", "watch the super bowl halftime show", "show me cat videos", "how to tie a tie video", "lofi music video" |

Answer: `choice` (one option name), `probabilities` (one per option), `confidence` (0–1).

### `recent` — type `noul`

A yes/no question answered with the probability of yes. Instructions sent with the question:

> Would the correct answer to this query depend on something that may have changed in the last two years? For example whether a person is alive, who currently holds an office, title or job, a record, a price, a recent event or its aftermath, or a phrase, slogan or meme that became known recently.

| Means | Description |
|---|---|
| yes | The right answer could have changed since early 2025: it depends on someone's current status, the current holder of a position, a recent or ongoing event, or a new phrase. |
| no | A settled fact, history, how something works, a definition, a conversion, a place, a date or time, or anything else that does not go stale. |

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

## When an answer is on screen

A follow-up typed over a narrative or one-line answer, Gemini's or the device's, is read as the conversation makes it. The `format` question's instructions become:

> Which response format best answers this web search query? The state carries the conversation so far: the earlier queries and the answer on screen. Judge the query as that conversation makes it, not as typed on its own. A reply, a reaction or a question that leans on the answer, however short, wants narrative; or one_line when the reply is itself a single short fact, a number, a name, a date, a yes/no, as "and chile?" after a capital is. Pick another format only when the query asks for the kind of thing that format shows: map, stock, recall, image, site, video, each described below; or web_results for a page to browse.

and one more question is asked:

### `continues` — type `noul`

A yes/no question answered with the probability of yes. Instructions sent with the question:

> The state carries the previous query and the answer the user is looking at. Is this query a continuation of that exchange: a reply, a reaction, a request to go on or to clarify, or a question that only makes sense given that answer?

| Means | Description |
|---|---|
| yes | The query answers, reacts to, questions or builds on the previous answer, or would be incomplete without it, however short: "why?", "can I use water", "and with oat milk", "tell me more", "is that true for cats too". |
| no | A new question that stands on its own, even about a nearby topic: it would mean the same thing with no previous answer. |

Answer: `noul`, the probability of yes (0–1). No confidence field.

## When a site is on screen

A query typed over a site this app opened by name (from the book, or learned from a tap) carries the name and host in the state and asks one more question:

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
{ "model": "jev-1.13.0", "answers": { "format": { "type": "choice", "choice": "stock", "confidence": 0.91, "probabilities": { "web_results": 0.05, "stock": 0.92, … } } }, "usage": { "input_tokens": 512, "output_tokens": 9 } }
```

- `choice`: the option with the highest probability.
- `probabilities`: one per option, summing to 1.
- `confidence`: `(p_max − 1/n) / (1 − 1/n)`; 0 for a flat spread, 1 for a single peak. Only the top probability matters.

## What the app does with it

| Outcome | Shown | Logged as |
|---|---|---|
| The time in a named place (see above) | A one-line card computed on the device | `local("time")` |
| A question handed to the model by name (see above) | A narrative answer to the question, with no recency gate | `local("ask")` |
| An opener and a site name the book knows (see above) | That site | `local("site")` |
| A search verb and a term (see above) | Web results for the term | `local("search")` |
| Address typed | That page | `directURL` |
| No API key configured | Web results | `noKey` |
| Request failed or timed out | Web results | `error(reason)` |
| `confidence` below 0.5 | Web results | `confidenceFallback` (the pick is kept as `suggested`) |
| `confidence` at or above 0.5 and `recent` below 0.5 | The chosen format's card; web results while that module is only `routed` (today: `map`, `stock`) | `jev` |
| `narrative` or `one_line` picked with confidence, but `recent` at or above 0.5 | Web results (the model's knowledge is months old; see the answer prompts) | `recencyFallback` (the pick is kept as `suggested`) |
| Over an answer on screen, `continues` at or above 0.5 and a card format (`map`, `stock`, `recall`, `image`, `site`, `video`) picked with confidence | That card | `jev` |
| Over an answer on screen, `continues` at or above 0.5 and any other pick, sure or not, with `recent` below 0.5 | The answer on screen grows into a transcript: the query as a line, then a reply written with the earlier turns in view, as one line when `one_line` was picked with confidence and as a narrative otherwise | `continuation` (the pick is kept as `suggested`) |
| `site` picked with confidence | The site, when the book knows the name; otherwise the choices card (see "After routing: sites") | `jev` |
| Over a site opened by name, `rejects` at or above 0.5, whatever the pick | The name is forgotten and the choices card shown again | `rejection` (the pick is kept as `suggested`) |

Web results, however reached, are for the query with its search verb gone: "google steve jobs" searches "steve jobs" (`SearchQuery`, see "Decided on the device"); the log keeps the spoken words. An `image` pick searches the subject alone (`ImageQuery`, see "After routing: Wikipedia images"). A `video` pick loads Google's video results for the term with the asking gone (`VideoQuery`, see "After routing: videos").

Every outcome is appended to `decisions.jsonl` on the device with the query, the pick, every option's probability, confidence, the recency probability, model, latency and input tokens. Summarise an exported log with `swift run --package-path Packages/Routing report decisions <file>`.

## After routing: recall

A `recall` pick is resolved in this order. First, Jev's reading of the ask, answered in the routing request itself (the `recall_*` questions above, so a recall costs no second round trip): which kinds of memory are wanted (`recall_pages`, `recall_answers`, `recall_pictures`, `recall_searches`, `recall_videos`), whether a particular thing is named (`recall_named`) and whether a set is wanted (`recall_all`), each a yes at or above 0.5. The intent is read only when `recall` was the pick, and logged with the decision. Second, the count ("last five", "recent") and the time words ("yesterday", "this morning", "three days ago") from the query itself, since a number and a day are not judgments. Third, the shortlist (`RecallFilters`, `MemorySearch.shortlist`): the kinds, the time and the video flag filter the memories; when a thing is named, the records are ranked by the words that remain, then the rest of the filtered set newest first, at most 10, with the kind a preference, not a wall; when nothing is named, no word is matched at all and the newest of the filtered set are taken. Without an intent (no key, a failed request, an older log) the kind words in the query ("video", "answer", "picture") and the collection words stand in, and with no filter and no content word there is nothing to go on, so the words go to web results. Last, unless a count or a set of a kind with nothing named was asked for (those are listed as they are, no judge needed), the shortlist goes to Jev in one request, a yes/no question per memory:

> Is this the memory the query asks for? A web page from yesterday (m.youtube.com): "Rick Steves' Europe: Lisbon".

| Means | Description |
|---|---|
| yes | The query describes this memory: by what it is, when it was seen, what it was about, or a word of its title. |
| no | A different thing, even if it shares a word with the query or is of the same kind. |

A memory at or above 0.5 is the one asked for and is shown alone. Otherwise every memory at or above 0.3 is plausible and is shown in Jev's order, so an unsure Jev leaves the choice to the user. Nothing ever opens straight away: even a single memory is shown in the grid before it takes the screen; none goes to web results for the query's content words ("that thing about gingivitis again" searches "gingivitis"). A failed or slow request, or no key, shows the shortlist in word order. The record's `recall` logs the shortlist size, how many were plausible, the path (`jev`, `words`, or the error) and the latency.

### Everything about something

A query that asks for everything ("all", "anything", "every", "everything") wants a collection, not one thing: "pull up everything we talked about with the dyson pencilvac". With an intent, `recall_all` says so, and a collection needs a named thing (`recall_named`): the per-memory question below is about that thing. The kind words are dropped (every memory about it is wanted; the time words still hold), the shortlist is the word matches, and each memory is asked a different question:

> Is this memory about what the query asks for everything about? A web page from yesterday (m.youtube.com): "Rick Steves' Europe: Lisbon".

| Means | Description |
|---|---|
| yes | This memory is about the thing, topic or name the query asks for everything about: its title, its query, its address or its text concerns it, whatever kind of memory it is. |
| no | About something else, even of the same kind, from the same day, or sharing an unrelated word with the query. |

Every memory at or above 0.5 is shown, newest first, in a picker titled by the topic; one alone opens; none goes to web results for the topic words. The record's `recall` carries `collection: true`. A set of a kind with nothing named ("all the videos from yesterday") is listed as it is, newest first up to 10, titled "All videos", with no judge asked, logged with the path `all`.

### The last so many

A query that asks for a count ("my last five searches", "the last 5 things I asked you", "latest three pictures", "last few", "a couple of", or "recent" and "latest" alone for 5; at most 20) wants the newest so many, not a thing: the kinds and time words still filter, the word matches narrow when the query names something too, and the newest so many are shown as a picker titled "Last 5 searches and answers", even when only one was found, with no judge asked, since there is nothing to judge. The record's `recall` carries `count` and the path `count`.

## After routing: videos

A `video` pick loads Google's video results (`QueryParser.videoSearchURL`, the results page with `tbm=vid`) for the term alone: `VideoQuery` takes the asking off the query ("You'll pull up some videos of Pele." → "videos of Pele", "watch the dune part 3 trailer" → "dune part 3 trailer"), as typed, and leaves a bare term as it is. There is no card: the page is the result, so the module is `built` from the start. The capsule reads the term off the page and the log keeps the spoken words.

- Corrections, any number, at the front: "no not that one", "no not that", "no not this", "no i said", "no i meant", "not that one", "not that", "i said", "i meant", "i told you", "like i said"
- Leads, any number, before the opener: "can you", "could you", "would you", "hey siri", "please", "hey", "ok", "okay", "just", "yo", "youll", "hi", "hello", "um", "uh", "alright", "yeah", "siri"
- Openers: "i want to watch", "let me watch", "can i watch", "show me", "pull up", "bring up", "find me", "get me", "give me", "put on", "play me", "watch", "play", "find"
- Quantifiers after the opener, at most one: "a couple of", "a few", "some", "the", "a", "an"
- Trailers, any number, at the end: "is what i said", "is what i meant", "like i said", "i said", "i meant", "i told you", "on google", "for me", "please"

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
- Earlier turns of this conversation may come before the query, oldest first; the query may lean on them ("and chile?", "in km?"): resolve it against your last answer and answer only the new question, still in one line.
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

An `image` pick is filled by `ImageLookup` in `Packages/Routing/Sources/Images` from two sources in order: Wikipedia (`ImageSearch`), free and without a key, whose article carries the picture's licence; then, only when Wikipedia answered and had nothing, Brave's image search (`BraveImageSearch`) with the same key as the site search (`BRAVE_API_KEY`, $5 per 1,000 requests), for a subject Wikipedia has no article on (a product from this year, say). Every Wikipedia request sends `User-Agent: Browser/0.1 (com.lorcancheng.browser)`.

What is searched is the subject alone: `ImageQuery` takes the asking off the query ("show me a picture of the eiffel tower" → "eiffel tower", "what does a capybara look like" → "capybara", "Dominican flag, I said." → "Dominican flag"), as typed, and leaves a bare subject as it is. Wikipedia's ranking turns on every word: "Dominican flag, I said" puts the flag of Panama first. The card, the memory and the log keep the spoken words.

- Corrections, any number, at the front: "no not that one", "no not that", "no not this", "no i said", "no i meant", "not that one", "not that", "i said", "i meant", "i told you", "like i said"
- Leads, any number, before the opener: "can you", "could you", "would you", "hey siri", "please", "hey", "ok", "okay", "just", "yo", "youll", "hi", "hello", "um", "uh", "alright", "yeah", "siri"
- Openers: "show me", "pull up", "bring up", "find me", "find", "get me", "give me", "display", "what does", "what do", "how does", "how do"
- Articles, before and after the picture phrase: "a", "an", "the", "some"
- The picture phrase: "picture of", "photo of", "image of", "pic of", "photograph of", "pictures of", "photos of", "images of", "pics of"
- Trailers, any number, at the end: "look like", "looks like", "look", "is what i said", "is what i meant", "like i said", "i said", "i meant", "i told you", "please", "for me"

1. `GET https://en.wikipedia.org/w/rest.php/v1/search/page?q=<subject>&limit=5`: article candidates in rank order. Hits without a `thumbnail` are dropped; the first 3 remain.
2. `GET https://en.wikipedia.org/api/rest_v1/page/summary/<key>` for each, in parallel: `type` must be `standard` (disambiguation pages are dropped) and `originalimage` must exist. An SVG comes back as a PNG render of about 960 px.
3. The first remaining article's picture is downloaded and decoded before the card is shown; the others, up to two, are alternates.

Wikipedia found nothing with a picture (not an error, not a timeout: those keep the fallback below without asking Brave), and a Brave key is configured:

4. `GET https://api.search.brave.com/res/v1/images/search?q=<subject>&count=5&safesearch=strict` with `X-Subscription-Token`: the same subject, in Brave's order. A result without an original image URL (`properties.url`) is dropped.
5. Each result's full-size image is downloaded from its site, in order, until one decodes: that is the picture; up to two of the results after it are alternates. The card's link goes to the page the picture sits on, named by its host ("dyson.com") where the Wikipedia link says "Wikipedia".

Each request has 6 s to reply, and each source 10 s for its search and the first download. Nothing from either source, no key, any failure, or a timeout falls back to Google's image results for the subject (`QueryParser.imageSearchURL`), so a request for a picture still ends in pictures.

| Outcome | Shown | Logged as |
|---|---|---|
| A Wikipedia picture decoded | The image card, with alternates when there are any, linked to the article | `shown(alternates:)` with the article, candidate count and latency, `source: wikipedia` |
| Wikipedia had nothing, a Brave picture decoded | The image card, with up to two alternates, linked to the page | `shown(alternates:)` with the result's title, `source: brave` |
| Wikipedia had nothing, no Brave key | Google Images for the subject | `fellBackToWeb("Wikipedia: no image; Brave: no key")` |
| Wikipedia had nothing, Brave had nothing or failed | Google Images for the subject | `fellBackToWeb("Wikipedia: no image; Brave: …")` with what Brave did |
| Wikipedia failed or timed out | Google Images for the subject | `fellBackToWeb(reason)`; Brave is not asked |

A Wikipedia article's page carries the image's licence and author; a Brave picture is whatever its site published, which is why Wikipedia goes first.

## After routing: sites

A `site` pick names a website. The name is what `SiteQuery` leaves of the query (see "Decided on the device"). The site book on the device (`SiteBook`: 37 seeded sites under 53 names, plus whatever has been learned) answers a known name at once; an unknown name is searched by `SiteSearch` in `Packages/Routing/Sources/Sites`, with a Brave Search API key (`BRAVE_API_KEY`).

1. `GET https://api.search.brave.com/res/v1/web/search?q=<name>&count=8&result_filter=web`, header `X-Subscription-Token`. Only `web.results` is read: title, url, description, and the result's favicon when it carries one (`meta_url.favicon` or `profile.img`), else Google's public favicon service for the host.
2. One result per host (`www.` aside), in Brave's order, the first 5: the choices card.
3. The site tapped is learned under the name, as its origin (scheme and host), and opened. The next time the name is asked for it opens straight away, with no model and no search.

No key, no result, any failure, or 6 s without a reply shows the Google results page for the name instead, and the first site tapped off it is learned the same way.

| Outcome | Shown | Logged as |
|---|---|---|
| The book knows the name | That site | `site` summary `opened` with the host; the decision is `local("site")` when the query had an opener, `jev` otherwise |
| Candidates found | The choices card | `choices` with the count and latency |
| No key, nothing found, or an error | Web results for the name | `results` with the reason |
| A follow-up rejects the site on screen | The choices card again, the name forgotten | `rejected`, decision `rejection` |
