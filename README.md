# Browser

An iOS browser where a query goes through a router that decides what kind of
card to show. The router is TypeSafe's Jev, a System One model: it picks one of
nine response formats and reports how sure it is. Five providers exist
behind it: a Google results web view (`web_results`), Gemini answers for
`narrative` and `one_line`, Google's image results for `image`, the phone's
own memories for `recall` (something seen before, brought back), and the
phone's site book for `site` (a website asked for by name, "go to youtube").

The screen is white with a purple gradient clay above the middle that
breathes, and a keyboard hint at the bottom. Tapping the clay or the hint, or
swiping up on the hint, raises the keyboard and stretches the clay into a
capsule you type in. Return sends the query and the clay becomes a short line
with one wave sliding along it, for as long as the query is being processed:
routing, then either the Google page committing or Gemini's first text. Then
the line fades out as the result fades in: a web page filling the screen, or
the answer in dark text where the line was, growing as it streams.

The two safe-area zones follow what the page pins to its edges, as Safari's
do. The top zone (status bar, Dynamic Island) is a fading frost over the
page; when the page pins a full-width banner there (YouTube's header, a
tabs bar) it is a solid block in the banner's colour instead, with the page
below it. The bottom zone is a reserve the page ends above: none when
nothing is pinned, so the page runs under the clay (Google results); the
bar's colour when a tab bar, checkout bar or cookie bar is pinned, the
clay inside it, growing and shrinking with the clay; a frost strip under a
floating button. A watcher script inside the page finds pinned elements
at both edges, works out each bar's paint, and reports whenever that
changes, so links, pages opened from results and in-page overlays (the
expanded AI overview, with its "Ask anything" field) all follow; a results
page keeps its frost whatever it pins at the top. The top zone's colour is
painted over the page, which the web view insets under the status bar by
itself; a page that asks for the whole screen (`viewport-fit=cover`) is
opted out by the watcher, because this web view gives it no safe-area
insets to pad with and it would sit under the clock. A bar's colour is
what the page declares: its opaque paint, else its theme colour. A bar
that declares nothing (a gradient over a video, as on YouTube Shorts) is
sampled by the app from the page's rendered edge, as Safari does, and the
sample counts only when the strip is one colour; otherwise white. The
clock stays dark over a dark banner for now. Over a result a capsule at the foot
shows the query, shrinks while you scroll down and grows on the way up;
tapping it raises the keyboard and the capsule rises with it, morphing into
the field, with the result still behind; on a web result the field holds
the page's query, selected, so typing replaces it. Return sends the
follow-up as a new query, routed like any other; over an answer, a
narrative or a one-liner, Jev is also asked whether it continues that
answer, and if so the card grows into a conversation instead of being
replaced (see "How a query runs"). The capsule itself
becomes the wave line, small, at the foot, until the new result is ready; a
link tapped inside a page shows the same line while the page loads. Tapping
the line while it waves returns to the circle. Pulling down at the top of
a page reloads it, with the system's spinner. Over a result the microphone
listens too, but only while you do nothing: no finger on the screen, no
keyboard; a fling still moving after the finger lifts does not count. A video or music playing is not a reason to
stop: the audio session is set once, at launch, to record and play while
mixing, and never touched again, so the microphone cannot pause anything;
voice processing cancels the phone's own output from what it hears, so a
video talking does not read as you talking.
Whenever it is not open the clay turns a soft red. Once a word is heard
the capsule rounds into a small circle at the left with "Disregard" and
"I'm done talking" beside it; any touch turns it back and forgets the words.

The page is SwiftUI's `WebView`. A site's tab bar is kept above the capsule
by laying the page out to end there, and it follows the capsule as fast as
WebKit lays the page out again for each frame, which is not Safari's
frame-smooth motion: Safari tells WebKit how much of the page its bars
obscure through private API that only an app-owned `WKWebView` can reach.
That route was built and removed: on iOS 26, inside this view hierarchy,
UIKit aborted touch delivery whenever such a page was scrolled far.

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
   results and the ribbon says "no Gemini key". A third key is optional: a
   Brave Search key from https://api-dashboard.search.brave.com ($5 per
   1,000 requests, $5 of credit a month) gives "go to hacker news" a list of
   the sites the name might mean the first time; without it the Google
   results page stands in (see "Sites").
3. Run on a device.

## How a query runs

`BrowserSession.submit` → `Engine.route` → `EngineResult { instinct, context, decision }` → `instinct.run`.
`BrowserSession.stage` (`idle`, `routing`, `loading`, `ready`) is what the
home screen reads to show the line or the result; a page counts as ready
when WebKit commits its first content (or after 8 s), an answer when its
first text arrives.

The engine (`Browser/Engine/Engine.swift`) is the cognitive engine's first
stage: it knows the session's **exchanges**, every earlier query up to the
layer on screen and what it got (an answer's text whole, a page's title and
address, a search's term, a picture's subject, a grid's titles, a choice of
sites), oldest first, read off the layers (`Layer.exchanges`). The layers
ahead of the current one are history a new query drops, so they are not
sent. An answer still streaming has no exchange yet.

**The instinct registry** (`InstinctSpec.all` in the package) is the list
of everything the app can do for a query, one per `Instinct` case, in the
order Jev sees the options: each one's criterion, the questions it adds to
the request, the values it takes, which of those the reading's subject
fills, and its side effects. The app binds each spec to an
`InstinctRunner` (`Browser/Engine/Instincts.swift`, `SiteInstinct.swift`,
`RecallInstinct.swift`, `FactInstincts.swift`) that runs the query it was
picked for: a showing instinct opens its layer, an acting one works the
session's stores and sheet. Adding an instinct is one `Instinct` case, one
branch in `InstinctSpec.init(instinct:)` and one runner.

Nothing decides a query before Jev except an address: text that parses as
one (`example.com`, `https://…`) loads as typed, with no reading and no
Jev (`QueryParser.directURL`). No word list, no rule, no grammar decides
anything else. Until 2026-10-27 version 1's router did: four device rules
in front of Jev, three gates that overruled its pick, and seven word-list
grammars that read values before a model could. They were never part of
the architecture and are gone; old log lines that carry their sources no
longer decode, and `report decisions` skips them and says how many.

**One request, one reading, at the same moment.** Every other query goes
to Jev (`EngineRequest.request`, when a key is configured) and to the
reading (see "The reading") in parallel:
- The request is `{ query, locale, exchanges?, opened_site_name?,
  opened_site_host? }` with every question below in it, answered in parallel:
  - the `instinct` Choice over the registry, options in registry order with
    `web_results` first, because Jev leans toward the first option when
    unsure. With exchanges in the state its instructions say to judge the
    query as the exchanges it depends on make it, and a standalone query as
    typed (`EngineRequest.contextInstructions`);
  - the questions the instincts add: `recent` (would the right answer depend
    on something that may have changed in the last two years?), the seven
    `recall_*` questions (Jev's reading of a recall ask; see "Recall"),
    `remember` (does the query state a lasting fact about the user? see
    "Facts"), and `rejects` while a site this app opened by name is on
    screen (see "Sites");
  - one yes/no question per exchange, `x0` for the oldest sent: does the
    query depend on it to be understood or acted on? The newest 20 exchanges
    go (`EngineRequest.maxExchanges`); older things are recall's job;
  - the `reasoning` score, three levels: direct, a value must be read out of
    the words first, several steps or a condition or a schedule (see
    "Advanced reasoning").
- When the reading rewrote the words (dictation noise, a false start), Jev
  is asked again on the read words and that pick wins; the read words are
  what everything after receives, and the log keeps both.
- **The pick stands.** The one fallback is an unsure pick: confidence below
  `EngineRequest.confidenceFloor` (0.5) runs `web_results`, logged as
  `confidenceFallback` with the pick kept as `suggested`. Any error or a
  2.5 s timeout does the same. Nothing overrules a sure pick: Jev's
  `recent` answer is the answer instincts' to act on (a reply that may have
  gone stale is web results instead, logged as `recency` on the pick's
  line), and its `rejects` answer is the site instinct's.
- **Values.** The reading's subject fills the picked instinct's object
  field (`InstinctSpec.subjectField`: `web_results.term`, `image.subject`,
  `video.term`, `site.name`, `remember.fact`, `forget.about`,
  `time.place`), so no grammar reads the words. A closed-set value, a
  choice or a yes/no, is two more Jev questions in the request for every
  instinct that declares one, read only for the pick (`<instinct>.<field>?`
  and `<instinct>.<field>`; the decision's `arguments`). A free-form value
  beyond the subject is one small Gemini call after the pick
  (`ValueExtractor`: Flash-Lite, a JSON schema of the fields still missing,
  2 s), made when the field is required, the instinct always reads
  (`recall`: a count and a span), the query is chained, or the reasoning
  score leans to a value. Nothing usable, or a required value still
  missing, runs web results for the words; the call's outcome rides on the
  decision's line as `extraction`. See "Values read by Gemini" in
  ENGINE.md, and try one with `report extract`.
- **The chain.** The device walks back from the newest exchange and stops
  at the first one Jev marked irrelevant (below
  `EngineRequest.relevanceThreshold`, 0.5): those are the exchanges the
  query depends on (`chain` in the decision; every answer is logged as
  `relevance`, oldest first, so a yes behind a no stays visible). A chain
  that ends on an answer exchange (a narrative, a one-liner, the time
  card, a replayed conversation) with an answer picked means the query
  continues that answer: the thread grows with a turn of the picked kind
  (`continues` on the line). Any other pick with a chain runs with the
  chained exchanges as context: a narrative or one-line answer lists them
  under Gemini's context block ("Earlier in this session: Searched …,
  Read …"; see "Answer cards"), and the reading folds them into the
  subject, so "wait no I meant brazil" after a search is a search for
  Brazil, "how big is it" after reading a page is an answer that knows the
  page, "and chile?" after "capital of peru" answers in one line, "why?"
  after it answers in a paragraph, and "pictures of it" is a picture of
  the thing.
- **The instinct runs** (`Browser/Engine/Instincts.swift` and the files
  beside it): `web_results`, `map` and `stock` load a Google results page
  for the term; `narrative` and `one_line` stream an answer, or show web
  results when Jev's `recent` says the reply may have gone stale; `time`
  answers from the device clock for the place the reading named, here when
  it named none; `image` loads a picture of the subject; `video` loads
  Google's video results for the term; `recall` works the memories (see
  "Recall"); `site` works the site book and the search (see "Sites");
  `remember` and `forget` work the facts (see "Facts"). A query whose
  reasoning score says it needs several steps goes to the executor instead
  (see "Advanced reasoning").
- Each decision is appended to `Application Support/Browser/decisions.jsonl`
  (query, instinct, confidence, every option's probability, the relevance
  answers and the chain, the reasoning score, model, latency, tokens, the
  reading; for answer plans, the answer summary too; for recalls, how many
  memories matched; for sites, whether the name was known, searched or
  rejected). Nothing leaves the phone unless you export it.

A result that comes back for a query the user has moved on from lands
nowhere: every query, reset, swipe and tap on a card gives out a new
request token, and every wait in the engine's path checks it still stands.

Model is pinned to `jev-1.13.0`. A request is roughly 1,200 input tokens at
$0.042 per million with no exchanges, and each exchange adds its text (an
answer whole), so a long session's request runs to a few thousand; a few
hundred queries a month still cost under a cent. To see what Jev makes of
one query from the Mac (one real call):

```
TYPESAFE_API_KEY=… swift run --package-path Packages/Engine report route "some query"
```

It prints the pick, the confidence and every option's probability; with
`--after <query> <answer>`, `--page <query> <title> <url>` or `--search
<query> <term>` for the session's earlier exchanges, oldest first, it also
prints the relevance of each, the chain and the reasoning score.

To run the whole golden set, `Packages/Engine/Evals/engine.jsonl` (one
labelled query per line: the query, the exchanges and the opened site that
were on screen, the instinct the app should run, and optionally the chain
expected, Jev's pick and the path):

```
TYPESAFE_API_KEY=… swift run --package-path Packages/Engine report eval --out before.jsonl
```

Every case goes through the address check and then Jev, as in the app
(the eval does not read: it grades the pick on the typed words). It
prints the misses with the threshold that decided and the probability
spread, then a pass count per instinct. Jev's answers are cached under
`Packages/Engine/.evalcache/` by a hash of the request body, so a
threshold change re-runs instantly and keyless (`--floor 0.6`,
`--recency 0.4`, `--no-network`), and only an edited criterion or
instruction asks again. `--baseline before.jsonl` lists what flipped
pass→fail and fail→pass since that run and exits 1 on a regression;
`--only image` runs one instinct. A query that routed wrongly on the phone
becomes one more line in the file, with its intended instinct and a note.
The set is 108 of 111 after the cut (2026-10-27): the three misses are
unsure picks the architecture sends to web, each with a note.

The golden set only catches what it already knows. To stress Jev with
queries nobody has labelled, by hand and whenever you like:

```
TYPESAFE_API_KEY=… swift run --package-path Packages/Engine report sample 50
```

Fifty unlabelled queries drawn from
`Packages/Engine/Evals/pool.txt` (a few hundred plausible phone queries
across the instincts, with the typos, casing, leads and trailers people
type) go through the same chain, and the output is a triage list rather than
pass/fail. Each row is what the app did (instinct, source, confidence,
recency, the runner-up), why to doubt it, and a `{"query": …,
"instinct": …}` line labelled with what the app did, to paste into
`engine.jsonl` as is when that was right or with the instinct corrected when
it was not. Rows come most doubtful first: a confidence or recency within
0.15 of its threshold or an unsure pick (the closest call first), then
anything that failed or was not cached, then the sure rows. The draw is
fixed by the day (or `--seed`), so a repeat the same day runs from the
cache; `--from-log decisions.jsonl` samples the queries of a log exported
from the phone instead of the pool.

## The reading

Dictation puts noise in front of a request, and the words rarely name
their object cleanly. "Which oh can you pull up youtube?" went to web
results on the literal words under version 1; the same request without
the grunt opened YouTube. So every query that is not an address goes to
`gemini-3.1-flash-lite` at minimal thinking (`QueryReader` in the Answers
library) at the same moment it goes to Jev, with the newest three
exchanges and today's date, and a two-field schema: `query`, the request
with its substance isolated (dictation noise, interjections, fillers and
false starts dropped, every word that carries meaning kept, in the
person's own wording and language), and `subject`, what the request is
about, in the words used, with anything the words point back at folded in
("pictures of it" after a Brazil page → "Brazil"). When the substance
differs from the typed words (`Substance.differs`: case, diacritics,
punctuation and spacing aside), Jev is asked again on the read words and
that pick wins, and they are what the instinct, the planner, the exchange,
the layer and the label on screen receive. The subject fills the picked
instinct's object field. The same substance, a miss, or a reply slower
than `QueryReader.timeout` (2 s) leaves the first pick standing with no
subject: the instinct then takes the words as they are. The trade is
latency: a query waits for the slower of the two calls, Jev's few hundred
milliseconds or the reading's (the first real calls took 0.97 and 1.38 s,
about five thousandths of a cent each), and a rewritten query pays one
more Jev request. The typed words stay on the decision's line as
`reading.original`; its `query` is what ran. The console prints
`reading "typed" -> "ran"; subject "…"`. Try one with `report read`.
Spoken queries go through the same reading: there is no cleaner in front
of it.

## Answer cards

`AnswerSession` streams one answer at a time from Gemini `gemini-3.1-flash-lite`
(Interactions API, thinking `minimal`, `store: false`, no tools). The system
instruction is the per-format rule set in `AnswerPrompt`
(`Packages/Engine/Sources/Answers`): narrative opens with the immediate
answer and keeps to the scope the query's wording implies, with no target
length; one-line gives the answer itself in at most twelve words, never a
sentence restating the question. The input carries the
query plus the device date, time and zone and the locale, so "today", "now"
and "the time in X" work without any lookup, and the model's knowledge
cutoff (January 2025, pinned in `AnswerPrompt.knowledgeCutoff`) with the
number of months since, so it knows what may have changed.

An answer that a follow-up continues (see "How a query runs") is
sent as a conversation: `input` becomes Google's stateless list of
`user_input` and `model_output` steps, the earlier queries bare, the earlier
answers with their markup as shown, and the new query last with the context
block; every earlier turn goes, however long the conversation. Both
sets of rules tell the model to read the query as a reply to its last
answer and not to repeat itself; the one-line rules add that the reply
stays one line. The card shows the thread as a transcript, each query a
quiet line over its answer, a narrative turn as prose and a one-line turn
as a short bold line (each turn records its format in `AnswerTurn.format`;
turns kept before that read as narrative), and scrolls the newest query up
as its answer streams. A turn that brings nothing back, or that needs
live data, keeps the thread and says so in its place rather than jumping
to web results for "why?" alone. One memory holds the whole conversation
under its first query and of its first turn's kind (`MemoryRecord.turns`),
so recalling it brings the thread back, a one-line conversation included,
and a follow-up on the recall continues it.

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
- a narrative question is answered with what the model knew, stated as
  plain fact, with no sentence about the cutoff: the Web results link under
  every answer is the way to check. Most queries that could have gone stale
  never reach the model anyway: the `recent` question at
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

## Images

`image` is for one specific, named thing with a definitive look: a flag, a
logo, a landmark, a painting, a person, a species, a game item. The
instinct loads Google's image results (`QueryParser.imageSearchURL`, the
results page with `tbm=isch`) for the words as they ran, so the search
engine reads the whole question ("what does green jelly look like in
Stardew Valley" finds the game item, not the band) and nothing in the app
has to name the subject. It is a page like any other to the capsule and
the log, and the memory keeps it as a picture, so "my pictures" and "that
picture of the pencilvac" bring it back. There is no card: a card needed a
picture source of its own (Wikipedia, then Brave) and a subject to search
it for, and the subject was the one place a query could still go wrong
after Jev; both came out on 2026-10-28.

## Recall

`recall` is for something the user saw in this app before and wants back:
"where's my grocery list", "remember that convo on the dyson pencilvac",
"pull up that youtube page from earlier". Jev picks it like any other
format, through the same confidence floor, so there is no phrase list in
the app and no extra request.

A memory is an ordered list of parts, each one thing of one format: a
page (address and title), a search (its words), one exchange of an answer
(question, text, format), a picture, and later a note or a reminder
attached to one of those. The first part is the head: it decides the
kind, the tile, the title's default, what a tap opens and what counts as
the same thing. A memory may point, by id, at the memory that was on
screen when it was made (`cameFrom`): the results page after a query
points at nothing, the first page after it at the search, every page
after at the page before, a search opened from an answer's "Web results"
at the answer, a page opened from a recalled memory at that memory. A new
query starts a run with no predecessor. Every memory is short-term and
goes a week after it was last touched; one flag (`kept`) marks a
long-term memory that stays until forgotten, shown with a bookmark on its
tile. Nothing promotes a memory yet; that comes with notes and "remember
this". Lines in the flat shape from before parts read as parts and are
rewritten in the current shape as records are refreshed.

Every result the user sees is written to `Application Support/Browser/memories.jsonl`
as it appears: a page (its address and title, reported by the watcher at
its first look, again when the page changes its address without a load,
as the next video on YouTube does, and again when the title settles; when
the document title is empty or only the site's own name, as mobile YouTube
leaves it on every watch page, the name in the page's `og:title` or meta
title is the title instead, and failing those, since a tap in YouTube's
feed leaves no metadata either, the page's first heading, which is the
video's name), a
narrative answer (its text), a one-line answer, a picture or a results
page (the query only). Error pages, redirects and untitled documents are
skipped. The search that led to a page is attached to the first page
after it only; pages browsed on from there answer to their own titles and
addresses, so browsing on from "rick steves" does not make the next video
answer to "rick steves". Seeing the same thing again within a day refreshes
its record (date, title and parts; never where it came from or whether it
is kept); expired short-term memories go on first load and then once a
day; past 5 000 records the oldest go, which keeps the file in the tens
of megabytes at most. Nothing in it leaves the phone, and Google's
interaction storage stays off.

A recall is resolved in four steps. First, Jev's reading of the ask,
answered inside the routing request itself so a recall costs no second
round trip (`RecallIntent`, the `recall_*` questions in ENGINE.md): which
kinds of memory are wanted, whether a particular thing is named, and
whether a set is wanted. When nothing is named, no word in the query is
matched against the memories at all, which is what keeps "the last 5
things we were looking at" from landing on whatever page holds the word
"were". Second, a count and a span, which the extractor reads out of the
words on every recall pick against today's date (`count`, `from`, `to`;
"my last five searches", "yesterday", "three days ago"), and Jev's kinds,
become the ask over what each record stores (`RecallAsk`): videos are
pages on a video host (a short list in `MemoryRecord.videoHosts`; a host's
front page, as "go to youtube" opens it, is the site and not a video) or
titled as one, answers are answers, a span keeps what was seen then. No
word list reads the query. Then the phrasing is
dropped ("remember", "that", "my", "pull up", "can") and the records left
are ranked by the words that remain, in their queries, titles, addresses
and text; a name spelt nearly right still counts ("hennessy" finds
"hennessey", as dictation spells names); records holding every word win,
then records holding any, then the rest of the filtered set newest first;
at most ten (`MemorySearch.shortlist`). With no filter and no content word
there is nothing to go on, and the words go to the web. Last, the
shortlist goes to Jev in one request, a yes/no question per memory naming
its kind, when, its host and its title (`RecallRouting`, see ENGINE.md).
A memory at or above 0.5 is the one asked for and is shown alone;
otherwise everything at or above 0.3 is plausible and is shown in Jev's
order. Nothing ever opens straight away: even a single memory is shown in
the grid, so the user sees what was found before it takes the screen; nothing
plausible falls through to a Google search for the query's content words
("that thing about gingivitis again" searches "gingivitis"), so a wrong
judgement costs nothing visible. A failed or slow Jev request, or no key,
shows the shortlist in word order instead. The kind words are a preference,
not a wall: "what you told me about the dyson" prefers an answer, but when
no answer holds those words and pages or searches do, those are shortlisted.

A query that asks for everything ("pull up everything we talked about with
the Dyson PencilVac", "all the videos from yesterday") wants a collection,
not one thing (`RecallAsk.collection`). The kinds become no bar, the
shortlist is every memory holding any of the content words (a span still
holds), and Jev is asked, per memory, whether it is about the topic
rather than whether it is the one. Everything at or above 0.5 is shown,
newest first, in the grid titled "Everything about <topic>"; one alone
opens; none searches the topic words. The log's `recall` carries
`collection: true`.

A query that asks for a count ("my last five searches", "the last 5
things I asked you, including Google searches and AI stuff", "the last few
pages"; the extractor reads the number, and twenty is the most) wants the
newest so many, not a thing (`RecallAsk.count`). The kinds and the span
filter as usual, a topic
narrows the pool when the query names one, and the newest so many are shown
in the grid titled "Last 5 searches and answers", even when only one was
found, with no judge asked, since there is nothing to judge. The log's `recall` carries `count` and the
path `count`. A set of a kind with nothing named ("all the videos from
yesterday") is listed the same way, titled "All videos", with the path
`all`. Try either offline with `report recall <memories.jsonl>
"everything about the dyson"`, which prints the filters, the shortlist and
Jev's verdict per memory.
A page's address is kept without Google's click code or `utm_` tags, so
the same page tapped twice from results is one memory. The picker is a
two-wide grid of tiles, like Safari's tab overview: a page shows its
picture, a screenshot of the page area as the user last saw it (taken
when the page is left, by a new query, a swipe, a tapped link, the idle
screen or the app going to the background, and as a backup once the page
has settled and whenever a scroll rests, a few seconds apart; a 360-px
JPEG of about 30 KB in `Application Support/Browser/memories/`; a YouTube
watch or Shorts page gets the video's own thumbnail from `i.ytimg.com`
instead, framed in black, since no capture can see the video layer; kept for
the newest 1 000 pages and deleted with its record), a narrative its
opening lines, the rest a
symbol; the kind, the title and when sit under each tile. Opening a memory
reuses the ordinary plans: a page loads its address; a results page loads
its query's results, no router asked; a narrative shows its saved text
with its date, no model asked; a one-line answer or a picture asks its
query again, since those are cheap and may have gone stale, and Jev may
not answer `recall` for that asking. The results page a recall falls
through to is not memorised, so the recall phrase never becomes a memory
that the next recall of the same words would find and loop on; and a
look through the memories that has not resolved in 3 s goes to the web.

The decision log notes each recall's shortlist size, how many Jev picked,
which path answered (`jev`, `words`, or the error) and Jev's latency.
`swift run --package-path Packages/Engine report recall <memories.jsonl>
"<query>"` runs the filters, the shortlist and, with `TYPESAFE_API_KEY`,
Jev's judgement from the Mac, so a recall phrasing can be tried against an
exported memories file. Debug builds show a "Clear memory" link at the top of the idle
screen that deletes the file and every picture; there is no user-facing
control yet.

## Facts

A fact is one thing the app knows about the user, in their own words: a
preference, an allergy, a name, where they live. Facts are the second
memory store, beside the memories of things seen: few, short, and never
expiring on their own. Every fact goes into every answer (`AnswerPrompt`'s
"What you know about the user" block, after the context and the earlier
exchanges; the prompts say to let them shape the answer when they bear on
it and never to repeat them), and later into every plan. Nothing in the
file leaves the phone except inside a Gemini request, which keeps nothing
(`store: false`).

A fact comes to be known three ways (`Fact.source`):
- **told**: "remember that I'm allergic to peanuts", "keep in mind I'm
  vegetarian", "note that I don't eat pork". Jev picks the `remember`
  instinct; the fact is the reading's subject, in the user's own words,
  or what the extractor reads out of the words when the reading gave none.
  A plain statement with nothing asked ("I live in austin now") is a
  remember too.
- **inferred**: the query states something lasting on the way to asking
  something else ("I'm allergic to peanuts, what can I snack on"). Every
  request carries a `remember` question (ENGINE.md); at or above
  `EngineRequest.rememberThreshold` (0.5) on any other pick, the pick runs
  as usual and the same small call distils the fact into one sentence in
  the user's voice, which is kept quietly. The query waits for that call
  (about a second) before the pick runs.
- **chosen**: the answer to a question a plan put on the sheet, when the
  plan keeps it (a `remember` step right after an `ask`; see "Advanced
  reasoning").

Keeping a fact shows one quiet line for three seconds, "Remembered: I'm
vegetarian", above the capsule over a result or under the clay on the idle
screen (`RememberedMark`): the only sign that something was kept, so a
wrong note can be seen and undone. The same words again (case and
punctuation aside) refresh the fact rather than repeat it.

"Forget that", "forget that I'm vegetarian", "stop remembering my peanut
allergy" is the `forget` instinct, the first destructive one: the facts
the words point at are shortlisted on the device (`FactSearch`: the ones
holding any of the content words first, then the newest, so a bare
"forget that" offers what was just kept), judged by Jev one yes/no each as
a recall's candidates are (`FactRouting`), and put to the user on the
sheet: "Forget “I'm vegetarian”?" with Forget and Keep when one is sure,
"Forget which?" with up to three when several are plausible. A tap
forgets it and the mark says so; a swipe down keeps it. Nothing is ever
forgotten unasked.

Neither instinct shows a layer: the screen stays where it was (the idle
clay, or the result under the capsule), and the sheet rises over it when
one is needed. The decision log carries `fact` on the query's line
(remembered by source, forgotten, declined, or none), and `report
decisions` summarises them. The facts live in
`Application Support/Browser/facts.jsonl` (`FactStore`, in the package so
it is tested against a file of its own); Debug builds' "Clear memory"
empties it with the rest.

## Advanced reasoning

A query that needs several steps, a condition, or a value no instinct has
on its own ("remember I'm vegetarian, then suggest a dinner", "find that
car page again and tell me where the nearest dealer is") is planned
instead of run. Every request carries a reasoning `score`
(ENGINE.md: direct, needs a value, needs sequencing); at or above
`ReasoningPolicy.threshold` (1.2; the two-step "remember I'm vegetarian,
then suggest a dinner recipe" measured 1.46 and a plain remember 0.82),
whatever Jev picked, or at or above
`leanThreshold` (1.0) when the pick was unsure, the engine hands the query
to the executor (`Browser/Engine/Executor.swift`) rather than to the pick.
Without a Gemini key the pick runs as it would.

The planner (`Planner` in the Answers library) asks `gemini-3.1-flash-lite`,
the extractor's model at its minimal thinking (`store: false`; well under
a cent a plan at the prices in `GeminiPricing`), with every instinct as a tool,
each taking a `query` and its own fields, plus two the executor answers
itself: `ask` puts one question on the sheet (up to three options, or a
line to type) and `done` ends the plan. The model's text is never shown:
the system instruction says it acts only by calling tools and speaks
through `narrative` or `one_line` with a query it writes, folding in what
earlier steps returned. The first turn carries the request, the exchanges
it depends on (the chain) and up to five memories the words point at (the
recall shortlist, judged by Jev when it can); every fact goes in the
system instruction, as it does for an answer.

The executor runs each call in order through the same paths a single
query takes: a showing instinct through the session, waiting until its
layer is ready; an acting one through its `act`. A paid or destructive
step is put to the user first ("Go ahead: …?") unless the instinct asks
for itself, as `forget` does; the same call twice runs once; a second
thing to show is refused, since a new layer would replace the first; an
answer on the sheet goes back to the model as the step's result, and a
`remember` right after it keeps the fact as **chosen**. Each result goes
back as a `function_result`, with every model step replayed verbatim, for
at most four rounds within twenty seconds, each round within eight. The
plan ends on `done`; when nothing was shown or done, web results for the
words; on a no on the sheet; when the rounds or the time run out; or when
a newer query takes the screen, where it stands and never after a step
with a side effect. The wave line stays up while the plan runs; a plan
that only did something hands the screen back to where it stood, as
`remember` does.

Every step a plan did with no screen of its own (a fact kept; later, a
call made) is a memory of kind `action`, chained from what was on screen,
so "what did you just do" can find it. The decision log carries `engine`
on the query's line (model, rounds, each step with its outcome and
latency, tokens, the facts and memories given, the outcome); each step the
plan showed is a line of its own with source `plan`; `report decisions`
summarises the plans. `report plan "<query>" --dry-run` prints the first
request with every tool; with the key it makes one round and prints the
calls the model asked for, the tokens and the cost.

`gemini-3.8-flash` was the first choice and was measured on 2026-10-27
before being set aside: it refuses minimal thinking, and at low its first
round on "remember I'm vegetarian, then suggest a dinner recipe" took
eleven seconds and a thousand thought tokens, half a cent, for one right
call. A plan is sequencing under explicit rules, so the Lite model does it
at the Lite price; `Planner.model` is the one constant to raise if the
log shows poor plans.

## Sites

`site` is for a website asked for by name: "go to youtube", "pull up
zillow", "open insta", "take me to airbnb", or just "reddit". It behaves
like a browser's address bar: a name it knows opens at once; a name it
does not know shows the sites it might mean, and the one tapped is what
the name opens from then on.

The site book (`SiteBook` in the package, `Application Support/Browser/sites.json`
on the phone, `SiteStore`) maps each name to a site's origin (scheme and
host, never the page the user happened to land on). It starts seeded with
about thirty well-known sites and their short names (youtube/yt,
instagram/insta/ig, facebook/fb, x/twitter, reddit, tiktok, amazon, zillow,
airbnb, netflix, gmail, github…; the list is `SiteBook.seed`). Names are
keyed by their words (`Words.key`: case, accents and punctuation aside),
so "Zillow" and "zillow.com" are one entry; the name itself is the subject
the reading gave ("which can u pull up youtube" → "youtube"), or the
words as typed when it gave none.

Every site request is Jev's call
between `site`, `recall` ("pull up that youtube page from earlier" points at
the past), `web_results` ("zillow homes in austin" is a search on a site)
and the rest; a `site` pick is then looked up by its name. An unknown name
goes to Brave's web search (`SiteSearch` in `Packages/Engine/Sources/Sites`,
key `BRAVE_API_KEY`; one request, the first five results one per host, each
with its icon) and the choices card lists them where the clay was: "Which
hacker news?", then the sites, then a "Web results" link. A tap learns the
site under the name and opens it. Without a key, with nothing found, or on
any failure the Google results page for the name stands in, and the first
site tapped off it (Google's own click redirects and AMP pages aside) is
learned the same way.

While a site opened by name is on screen, a follow-up is read with it in
view: the site instinct asks Jev `rejects`, and on a site pick at or above
`EngineRequest.rejectionThreshold` (0.5) "no not this one", "not this
zillow", "I'm looking for a different website" forget the name and show
the choices again, so the next tap replaces the entry; "open youtube" is a
new site request and anything else runs as picked (see "How a query
runs"). Nothing overrules the pick: an unsure one is web results. The results page a
site request falls through to is not memorised as a search, so "go to
lobsters" never becomes a search memory. Debug builds' "Clear memory"
resets the book to the seed.

`swift run --package-path Packages/Engine report sites "<name>"` prints
what the seeded book says of a name and, with `BRAVE_API_KEY`, the
candidates; `report route "<query>" --opened <name> <host>` shows the
rejection judgement.

## Layers

Results are kept the way Safari keeps tabs. Every query opens a layer; a
follow-up that continues the conversation on screen grows the current
layer instead. A layer that shows a page keeps that page live when the
user moves on, so coming back finds a video where it was and a form as
filled; its "last page" is whatever was on screen when it was left (web
results, then three sites ending on YouTube, is one layer, ending on
YouTube). A tap that turns a card into a page (an answer's "Web results",
a picture's site, a site choice, a tile in the recall grid) opens a new
layer, so the card stays one swipe back. Asking for a page again is a
fresh load, never the old layer.

A swipe across the clay capsule at the foot of a result goes back a layer
(left to right) and forward again (right to left); the result cross-fades,
the capsule contracts from the side the swipe started on and its text
fades, and the microphone is off while the finger moves. Swiping
inside a page stays the page's own back and forward. A new query from the
middle of the stack drops the layers ahead, like browser history. Recall,
the grid and tile taps are unchanged; there is no spoken "back".

The current layer and the newest three others stay live
(`BrowserSession.maxLive`); past that the oldest shown go, pages in use
last (a video part way through, a form typed into, which the watcher
reports as `pageUse`). A background page idle for thirty minutes goes
too, and a memory warning takes every background page not in use, the
rest on a second warning within a minute. Leaving a layer pauses its
media. An unloaded layer keeps notes (`PageNotes`: address, scroll, how
far into its video) read from the watcher as the page goes, and a swipe
back to it reloads to that spot (a YouTube watch page takes the time in
its address). Each layer keeps its own answer stream, pictures, opened
site and memory chain, so a follow-up over a layer swiped back to
continues that conversation and a page opened from it is memorised as
coming from it. Nothing of this outlives the app.

## Where things live

| Path | Role |
|---|---|
| `Packages/Engine/` | Foundation-only Swift package with three libraries. `Engine`: the instincts and their Jev criteria (`Instinct`), the instinct registry (`InstinctSpec`: questions, values, the subject field), the exchanges Jev reads (`Exchange`), the System One client, the engine's request and pick (`EngineRequest`: the pick, the relevance chain, the reasoning score, the confidence floor; `Pick`), `QueryParser` (an address as typed, the results pages), `Words` (the one tokenizer the stores key by), the time instinct's clock and zone tables (`LocalTimeAnswer`, `PlaceTimeZones`), the memories (`Memory`, `MemorySearch`, `RecallAsk`), the facts (`Fact`, `FactStore`, `FactSearch`, `FactRouting`), the gate into advanced reasoning and a plan's bounds and summary (`ReasoningPolicy`, `EngineSummary`), the reading's summary, the log record and reports. `Answers`: the Gemini client (streamed for an answer, whole for a reading, a value or a plan), SSE parsing, the per-format prompts, the emphasis markup, the reader (`QueryReader`), the value extractor and the planner (`Planner`: every instinct as a tool, the plan's system instruction and first turn, one round). `Sites`: the Brave web search client. Tests run on macOS. |
| `Browser/Engine/Engine.swift` | The cognitive engine's first stage: an address as typed, else one Jev request over the registry carrying the session's exchanges with the reading beside it, the subject into the pick's object field, the extractor for a field beyond it, and the instinct to run with what it needs; or the hand-off to the executor when the reasoning score says the query needs several steps. Also `BrowserSession.makeEngine()`, `makeAnswerClient()`, `makeRecallResolver()` and `makeSiteSearch()`. |
| `Browser/Engine/Executor.swift` | Advanced reasoning's second stage: runs a plan round by round, each call through the instincts, the sheet and the session, confirming a paid or destructive step, refusing a repeat or a second thing to show, and sending every result back to the planner until `done` or the bounds. |
| `Browser/Engine/Instinct.swift`, `Instincts.swift`, `SiteInstinct.swift`, `RecallInstinct.swift` | The `InstinctRunner` protocol (a spec from the registry and `run`, through the session), the registry of runners in order, the showing instincts, and the two that own a store: the site book and the search, the memories and Jev's judge. |
| `Browser/Engine/SessionExchange.swift` | A layer's thread and its exchanges: what each layer got, as the engine sends it to Jev. |
| `Browser/Engine/FactInstincts.swift` | The two instincts that show nothing: `remember` keeps a fact, `forget` judges which one the words mean and asks on the sheet. |
| `Browser/Engine/PendingQuestion.swift` | One question put to the user on the sheet and the wait on its answer, resumed once by a tap, a return or a cancel. |
| `Browser/Answers/AnswerSession.swift` | Streams one Gemini answer: the text, the live-data marker check, and the summary for the log. |
| `Browser/Memory/MemoryStore.swift` | The memories file: load once, append as results appear, refresh a repeat within a day, drop the oldest past the cap, search by words (`MemorySearch` in the package). |
| `Browser/Memory/SiteStore.swift` | The site book on disk: seeded on first load, written whole on each learn, touch, forget or clear. |
| `Browser/Home/AskSheet.swift`, `RememberedMark.swift` | The small sheet the app asks with (a question, then up to three buttons or a line to type; sized to its content), and the quiet line shown for a moment after a fact is kept or dropped. |
| `Browser/Engine/DecisionLog.swift` | JSON Lines log of every decision and answer. |
| `Browser/Engine/Secrets.swift` | Reads the keys from Info.plist (`TypeSafeAPIKey`, `GeminiAPIKey`, `BraveAPIKey`). |
| `Browser/Engine/CardPlan.swift` | The renderable plans. One enum case per card type. |
| `Browser/Session/BrowserSession.swift` | Owns the layers (one per query, the current one on screen; see "Layers"), runs queries through the engine, applies the plan (a recall through the memories, a site through the book or the search) or runs an instinct that shows nothing, keeps the facts and the mark, puts a question on the sheet and waits for it, opens, swipes between, unloads and reloads layers under the live cap, memorises what each layer shows, writes the log. |
| `Browser/Session/Layer.swift` | One query's result: its plan, its live page (`PageHost`) or the notes left by an unload, its own answer stream and pictures, the page it ended on (for the engine's exchanges), its opened site and memory chain, when it was last shown. |
| `Browser/Web/PageHost.swift` | One live web page: the `WebPage` with its watcher, what it pins to its edges, whether it loads or plays or is in use, the navigation watch and the document bookkeeping behind the chrome, the notes read as it goes and the restore when it comes back. |
| `Browser/Web/` | `PageChrome.js`, the watcher installed in every page (hit tests along both edges, bar or floating or none, the bar's colour composited until opaque or flagged as a guess for the app to sample, a `MutationObserver` so overlays and in-page changes report too, rules that keep a bar's verdict while its element lives, pinned itself or inside a pinned box, and hold every look until the scroll has rested, so nothing resizes under the finger or between two Shorts); `PageChrome.swift`, the state the app keeps, the message handler (chrome reports, address changes for the memories, audio, and whether the page is in use), the page's notes for an unload, the edge sampler (a 64-point-wide export of a three-point strip just inside the page's edge, accepted when near-uniform) and the page configuration that installs the script and lets video play inline (the iPhone default sends every playing `<video>`, YouTube's feed previews included, into the system full-screen player). Debug builds print each page's chrome verdict to Xcode's console. The page is never made inspectable: an inspectable page under SwiftUI's `WebView` crashes UIKit's touch delivery on the first tap (iOS 26 and 27). |
| `Browser/Home/` | The screen: `HomeView` (white background, focus state, the stage-driven cross-fade), `Clay` (the mesh-gradient circle that morphs into the capsule field and the wave line), `KeyboardHint` (the nodding chevron over a keyboard icon), `ResultView` (the web page or the answer text with its "Web results" link, under a frosted status bar; the page bounces sideways only when it is wider than the screen, since the web view's default rubber-bands sideways on every page and a vertical drag with a little drift wobbles it) `ClayCapsule` (Safari's minimised bar: the query at the foot of a result, which becomes the follow-up field above the keyboard, and swipes between layers) and `QueryField` (the text field the clay and the capsule share). No system toolbars, so no Liquid Glass. |
| `Browser/Info.plist` | Merged into the generated Info.plist. Holds what Xcode will not take as `INFOPLIST_KEY_` settings: the three API keys and `UIDesignRequiresCompatibility`. Light mode is forced by `INFOPLIST_KEY_UIUserInterfaceStyle` in the project and `preferredColorScheme(.light)` at the root. |
| `Config/` | xcconfigs. `Debug`/`Release` optionally include the untracked `Secrets.xcconfig`. |

## The engine contract

[ENGINE.md](ENGINE.md) is the engine contract, generated from the same
code the app runs: the state Jev reads, every question with its type and
options, the queries each option is meant to catch, the answer shape, what
the app does with each outcome, the reading beside Jev, and then the exact
Gemini system instructions and input block for the answers, the values and
the planner. Regenerate it with:

```
swift run --package-path Packages/Engine report engine > ENGINE.md
```

For what real queries triggered, copy `decisions.jsonl` off the phone (the
app's container, through Xcode's device window or `xcrun devicectl`) and run:

```
swift run --package-path Packages/Engine report decisions ~/Downloads/decisions.jsonl
```

That prints picks per instinct, how often each was acted on or fell back, mean
confidence, recent example queries, errors, the unsure picks with their
runner-up, the readings, and an Answers table: per format, how many completed, needed live
data, fell back or stopped early, median first-token and total latency, mean
output tokens, and the token cost for the log.

## Tests

```
swift test --package-path Packages/Engine
```

Covers the Jev request body against TypeSafe's documented shape and option
order (the exchanges in the state, a relevance question per exchange, the
reasoning score), decoding of their example response, the confidence
floor and that nothing else overrules a pick, the chain and what it grows
or hands on, every failure path falling back to web results, and the
address bypass; the time instinct's clock (every alias and country row
resolving to a real zone, and the day shift and clock format against a
fixed instant); the site book's seed, learning and forgetting, the
`rejects` question's shape, and the Brave client against canned results;
the recall ask and shortlist; the facts (the store against a file of its
own, the forget judge's request and picks, the shortlist); the reading's
request and what each kind of reply comes to; the gate into advanced reasoning, a plan's
bounds, the action memory part and the plan summary on a log line; and
for Gemini, the request body and key order (and that no tool is sent for
an answer), the per-format prompts and budgets, the context block, the
planner's tools, system instruction, first turn and request, a canned
round with its calls, SSE parsing, a canned stream end to end, error
frames, timeouts, and old log lines without answers. Nothing here needs a
simulator.

## Deliberately absent

Dark mode, Markdown in answers, the Debug ribbon (the log still records every decision; summarise
it with the report CLI), tabs, history, bookmarks, content blocking, reader
mode, the map and stock cards, live search behind answers (see
"Answer cards" for why Google's grounding was removed), location, the
backend (the Jev and Gemini requests move behind it later, taking the keys
with them).
