# Browser

An iOS browser where a query goes through a router that decides what kind of
card to show. The router is TypeSafe's Jev, a System One model: it picks one of
nine response formats and reports how sure it is. Five providers exist
behind it: a Google results web view (`web_results`), Gemini answers for
`narrative` and `one_line`, a Wikipedia (or Brave) picture for `image`, the phone's
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
replaced (see "How a query is routed"). The capsule itself
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

## How a query is routed

`BrowserSession.submit` → `Engine.route` → `RouteResult { plan, decision }`.
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
of everything the app can do for a query, one per `ResponseFormat`, in the
order Jev sees the options: each one's criterion, the questions it adds to
the request, the grammar that recognises it on the device when it has one,
and, for later, the values it takes and its side effects. The app binds each
spec to an `Instinct` (`Browser/Engine/Instincts.swift`) that turns the
engine's decision into a `CardPlan`. Adding an instinct is one
`ResponseFormat` case, one branch in `InstinctSpec.init(format:)` and one
conformer.

The device's rules go first and cost nothing (`DeviceRouting.decide`, each
one an instinct's own grammar, tried in `InstinctSpec.deviceRuleOrder`; the
report CLI and the eval run the same code, so a query routes the same way
in all three):
- A request to open a site whose name the book knows ("go to youtube",
  "pull up zillow") opens it at once, with no model and no network: a fixed
  grammar (`SiteQuery`: leads, one opener, articles, the name, trailers)
  and the site book (`SiteBook`, see "Sites"). A bare name ("youtube") or
  a name the book does not know goes on to Jev. Logged as `local("site")`.
- A question handed to the model by name ("ask AI what are some
  alternatives to Dyson", "can you ask the AI what GDP means") is a
  narrative answer to the question after the ask, with no format question
  and no recency gate: the user asked for the model's answer knowing what
  it is (`AnswerQuery`: leads, one opener, at most one connective, the
  question, trailers). The card keeps the words as typed; Gemini gets the
  question alone. Skipped without a Gemini key. Logged as `local("ask")`.
- A query led by a verb that only ever means "search" ("search for steve
  jobs", "look up flights to lima") is web results for the term, with no
  model asked (`SearchQuery`). Logged as `local("search")`. "google steve
  jobs" is not a command here, since "google stock" and "google maps" are
  nouns: it goes to Jev, and only a `web_results` pick drops the "google"
  (never before a Google product name). Either way the search box gets
  the term as typed; the capsule reads it off the results page, the search
  memory keeps it, and the log keeps the spoken words.
- A query the device can answer itself is a card at once, with no model and
  no network: today, the time in a named place ("what time is it in Mexico?").
  `LocalAnswers` in the package holds the rules: a fixed grammar
  (`TimeQuery`), a place resolver over the device's own zone database plus
  hand tables for countries, US states and common aliases (`PlaceTimeZones`),
  and the clock arithmetic (`LocalTimeAnswer`). A place the tables do not
  know, or any other phrasing, goes on to Jev unchanged. Logged as
  `local("time")`; an older `report` build cannot decode a log that holds it.

Then one Jev request (`EngineRouting.request`, when a key is configured):
- An address (`example.com`, `https://…`) loads directly; Jev is not asked.
- Anything else is sent as `{ query, locale, exchanges?, opened_site_name?,
  opened_site_host? }` with every question below in that one request,
  answered in parallel:
  - the `format` Choice over the registry, options in registry order with
    `web_results` first, because Jev leans toward the first option when
    unsure. With exchanges in the state its instructions say to judge the
    query as the exchanges it depends on make it, and a standalone query as
    typed (`EngineRouting.contextInstructions`);
  - the questions the instincts add: `recent` (would the right answer depend
    on something that may have changed in the last two years?), the seven
    `recall_*` questions (Jev's reading of a recall ask; see "Recall"), and
    `rejects` while a site this app opened by name is on screen (below);
  - one yes/no question per exchange, `x0` for the oldest sent: does the
    query depend on it to be understood or acted on? The newest 20 exchanges
    go (`EngineRouting.maxExchanges`); older things are recall's job;
  - the `reasoning` score, three levels: direct, a value must be read out of
    the words first, several steps or a condition or a schedule. Logged for
    now (`reasoning`, `reasoningConfidence`); advanced reasoning acts on it
    once built. An unsure pick that leans to the top level is still web
    results, marked `reasoningWanted` in the log.
- **Values.** An instinct may declare the values it takes (`ArgumentSchema`
  on its spec; none does yet). A closed-set value, a choice or a yes/no, is
  two more Jev questions in this request for every instinct that declares
  one, read only for the pick: whether the words say anything about the
  field, and which value (`<instinct>.<field>?` and `<instinct>.<field>`,
  TypeSafe's own function-calling recipe; the decision's `arguments`). A
  free-form value, a number or words, is one small Gemini call after the
  decision (`ValueExtractor`: Flash-Lite, a JSON schema of the fields
  still missing, 2 s; the first real call took about a second), made only
  when the pick declares such a field that
  its own grammar did not read and the field is required or the reasoning
  score leans to a value. Nothing usable, or a required value still
  missing, shows web results for the words; the call's outcome rides on the
  decision's line as `extraction`. See "Values read by Gemini" in
  ROUTING.md, and try one with `report extract`.
- Confidence below `EngineRouting.confidenceFloor` (0.5) falls back to
  `web_results`. Any error or a 2.5 s timeout does the same. One
  exception: an unsure `one_line` or `narrative` pick whose two answer
  options together reach `EngineRouting.answerMassFloor` (0.6) is shown as
  picked, logged as `answerSplit`, since Jev was torn between a short and
  a long answer rather than between an answer and a page ("can I use mr
  clean with clorox"). The recency gate still applies.
- A `narrative` or `one_line` pick with `recent` at or above
  `EngineRouting.recencyThreshold` (0.5) is shown as web results and logged
  as `recencyFallback`, because the model's knowledge is months old.
- **The chain.** The device walks back from the newest exchange and stops
  at the first one Jev marked irrelevant (below
  `EngineRouting.relevanceThreshold`, 0.5): those are the exchanges the
  query depends on (`chain` in the decision; every answer is logged as
  `relevance`, oldest first, so a yes behind a no stays visible). A chain
  that ends on an answer exchange (a narrative, a one-liner, the device's
  own time answer, a replayed conversation) means the query continues that
  answer: a card format picked with confidence
  (`ResponseFormat.outranksConversation`: `image`, `map`, `stock`, `recall`,
  `site`, `video`) shows that card; `one_line` picked with confidence grows
  the thread with a one-line turn; any other pick, sure or not, grows it
  with a narrative, which is never wrong inside a thread, only longer; both
  logged as `continuation` with the pick kept as `suggested`. A chain that
  ends on a page, a search or a picture keeps the pick, and the chained
  exchanges reach the instinct as context: a narrative or one-line answer
  lists them under Gemini's context block ("Earlier in this session:
  Searched …, Read …"; see "Answer cards"), web results search what the
  words say. So "wait no I meant brazil" after a search is web results
  read with the correction, "how big is it" after reading a page is an
  answer that knows the page, "and chile?" after "capital of peru" answers
  in one line, "why?" after it answers in a paragraph, and "pictures of it"
  becomes a picture. With no chain the rules above apply unchanged,
  including prefer-web-when-unsure.
- A follow-up typed over a site this app opened by name sends the name and
  host along in the state (`opened_site_name`, `opened_site_host`) and the
  site instinct adds a yes/no question (`rejects`): does the query say that
  was the wrong site? At or above `EngineRouting.rejectionThreshold` (0.5)
  the query is a site request for the same name again, whatever the pick:
  the name is forgotten and the choices shown (see "Sites"), logged as
  `rejection` with the pick kept as `suggested`. So "no not this one" and
  "I'm looking for a different website" bring the list back, while "open
  youtube" over zillow is a new site request and "why is zillow so popular"
  a narrative.
- The chosen instinct makes the plan (`Browser/Engine/Instincts.swift`):
  `web_results`, `map` and `stock` load a Google results page; `narrative`
  and `one_line` become `.answer(format:query:history:earlier:)`, the
  device's own time answer `.localAnswer`; `image` becomes
  `.image(query:)`; `video` loads Google's video results for the term;
  `recall` becomes `.recall(query:)`, which the session resolves from the
  memories (see "Recall"); `site` becomes `.site(name:)`, which the session
  resolves from the site book or a search (see "Sites").
- Each decision is appended to `Application Support/Browser/decisions.jsonl`
  (query, format, confidence, every option's probability, the relevance
  answers and the chain, the reasoning score, model, latency, tokens; for
  answer plans, the answer summary too; for recalls, how many memories
  matched; for sites, whether the name was known, searched or rejected).
  Nothing leaves the phone unless you export it.

A result that comes back for a query the user has moved on from lands
nowhere: every query, reset, swipe and tap on a card gives out a new
request token, and every wait in the engine's path checks it still stands.

Model is pinned to `jev-1.13.0`. A routing request is roughly 1,200 input
tokens at $0.042 per million with no exchanges, and each exchange adds its
text (an answer whole), so a long session's request runs to a few thousand;
a few hundred searches a month still cost under a cent. To see what Jev
makes of one query from the Mac (one real call):

```
TYPESAFE_API_KEY=… swift run --package-path Packages/Routing report route "some query"
```

It prints the pick, the confidence and every option's probability; with
`--after <query> <answer>`, `--page <query> <title> <url>` or `--search
<query> <term>` for the session's earlier exchanges, oldest first, it also
prints the relevance of each, the chain and the reasoning score.

To run the whole golden set, `Packages/Routing/Evals/routing.jsonl` (one
labelled query per line: the query, the exchanges and the opened site that
were on screen, the format the app should act on, and optionally the chain
expected, Jev's pick, the path, the search term, the image subject or the
site name):

```
TYPESAFE_API_KEY=… swift run --package-path Packages/Routing report eval --out before.jsonl
```

Every case goes through the device rules, the address check and then Jev,
as in the app. It prints the misses with the gate that decided and the
probability spread, then a pass count per format. Jev's answers are cached
under `Packages/Routing/.evalcache/` by a hash of the request body, so a
threshold or word-list change re-runs instantly and keyless (`--floor 0.6`,
`--recency 0.4`, `--no-network`), and only an edited criterion or
instruction asks again. `--baseline before.jsonl` lists what flipped
pass→fail and fail→pass since that run and exits 1 on a regression;
`--only image` runs one format. A query that routed wrongly on the phone
becomes one more line in the file, with its intended format and a note.

The golden set only catches what it already knows. To stress the router
with queries nobody has labelled, by hand and whenever you like:

```
TYPESAFE_API_KEY=… swift run --package-path Packages/Routing report sample 50
```

Fifty unlabelled queries drawn from
`Packages/Routing/Evals/pool.txt` (a few hundred plausible phone queries
across the nine formats, with the typos, casing, leads and trailers people
type) go through the same chain, and the output is a triage list rather than
pass/fail. Each row is what the app did (format, source, confidence,
recency, the runner-up format), why to doubt it, and a `{"query": …,
"format": …}` line labelled with what the app did, to paste into
`routing.jsonl` as is when that was right or with the format corrected when
it was not. Rows come most doubtful first: a confidence or recency within
0.15 of its threshold or a gate that fired (the closest call first), then
the device rules, then anything that failed or was not cached, then the
sure rows. The draw is fixed by the day (or `--seed`), so a repeat the same
day runs from the cache; `--from-log decisions.jsonl` samples the queries
of a log exported from the phone instead of the pool.

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

An answer that a follow-up continues (see "How a query is routed") is
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

## Image cards

`image` is for one specific, named thing with a definitive look: a flag, a
logo, a landmark, a painting, a person, a species. `ImageSession` runs an
`ImageLookup` over two sources in order. Wikipedia first, free and without
a key: `ImageQuery` takes the asking off the query ("show me a picture of
the eiffel tower" → "eiffel tower", "what does a capybara look like" →
"capybara"), the REST page search turns the subject into article
candidates, the page summary of the first three with a thumbnail gives each
article's lead image, and disambiguation pages and articles without an
image are skipped. When Wikipedia answers and has nothing (a 2025 product
has no article yet), and a Brave key is configured, Brave's image search is
asked for the same subject (`BraveImageSearch`, five results, strict safe
search, the same key as the site search); the first result whose full-size
image downloads and decodes is the picture. A Wikipedia error or timeout
is not a miss and does not reach Brave. Either way the first picture is
downloaded and decoded before the card fades in, so the wave line lasts
until it is on screen; the others are alternates, up to two, shown as
thumbnails under the title and description with a link to the page the
picture came from, "Wikipedia" for the article (which carries the image's
licence and author) or the site's host for a Brave result, and the usual
"Web results". Nothing from either source, or nothing within 10 s per
source, falls back to Google's image results for the subject alone, never
web results for the whole sentence. The log records the article or
result title, the source, the candidate count, the latency and the
outcome, with what each source did on a miss; if misses turn out to be
common, the upgrade is to let Gemini turn the query into an article title
before searching.

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
round trip (`RecallIntent`, the `recall_*` questions in ROUTING.md): which
kinds of memory are wanted, whether a particular thing is named, and
whether a set is wanted. When nothing is named, no word in the query is
matched against the memories at all, which is what keeps "the last 5
things we were looking at" from landing on whatever page holds the word
"were". The kind and collection words below are only the fallback when no
intent came back. Second, the count and the time words, which the device
reads itself, and in the fallback the kind words, become filters over what
each record stores (`RecallFilters`):
"video" or "watching" keeps pages on a video host (a short list in
`MemoryRecord.videoHosts`; a host's front page, as "go to youtube" opens
it, is the site and not a video) or titled as one, "answer" or "chat" keeps
answers, "picture" keeps pictures, and "yesterday", "this morning", "last
week" or "three days ago" keep what was seen then. Then the phrasing is
dropped ("remember", "that", "my", "pull up", "can") and the records left
are ranked by the words that remain, in their queries, titles, addresses
and text; a name spelt nearly right still counts ("hennessy" finds
"hennessey", as dictation spells names); records holding every word win,
then records holding any, then the rest of the filtered set newest first;
at most ten (`MemorySearch.shortlist`). With no filter and no content word
there is nothing to go on, and the words go to the web. Last, the
shortlist goes to Jev in one request, a yes/no question per memory naming
its kind, when, its host and its title (`RecallRouting`, see ROUTING.md).
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
not one thing (`RecallFilters.collection`). The kind words are dropped, the
shortlist is every memory holding any of the content words (the time words
still hold), and Jev is asked, per memory, whether it is about the topic
rather than whether it is the one. Everything at or above 0.5 is shown,
newest first, in the grid titled "Everything about <topic>"; one alone
opens; none searches the topic words. The log's `recall` carries
`collection: true`.

A query that asks for a count ("my last five searches", "the last 5
things I asked you, including Google searches and AI stuff", "my recent
pictures", "the last few pages"; "recent" or "latest" alone means five, and
twenty is the most) wants the newest so many, not a thing
(`RecallFilters.count`). The kind and time words filter as usual, a topic
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
`swift run --package-path Packages/Routing report recall <memories.jsonl>
"<query>"` runs the filters, the shortlist and, with `TYPESAFE_API_KEY`,
Jev's judgement from the Mac, so a recall phrasing can be tried against an
exported memories file. Debug builds show a "Clear memory" link at the top of the idle
screen that deletes the file and every picture; there is no user-facing
control yet.

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
keyed by their words, articles and trailers dropped, so "the Zillow
website" and "zillow.com" are one entry.

A query with an opener and a known name never reaches Jev: the site
instinct's grammar opens the site on the device, logged as `local("site")`. Everything else is Jev's call
between `site`, `recall` ("pull up that youtube page from earlier" points at
the past), `web_results` ("zillow homes in austin" is a search on a site)
and the rest; a `site` pick is then looked up the same way. An unknown name
goes to Brave's web search (`SiteSearch` in `Packages/Routing/Sources/Sites`,
key `BRAVE_API_KEY`; one request, the first five results one per host, each
with its icon) and the choices card lists them where the clay was: "Which
hacker news?", then the sites, then a "Web results" link. A tap learns the
site under the name and opens it. Without a key, with nothing found, or on
any failure the Google results page for the name stands in, and the first
site tapped off it (Google's own click redirects and AMP pages aside) is
learned the same way.

While a site opened by name is on screen, a follow-up is read with it in
view: "no not this one", "not this zillow", "I'm looking for a different
website" forget the name and show the choices again, so the next tap
replaces the entry; "open youtube" is a new site request and anything
else routes as usual (see "How a query is routed"). The results page a
site request falls through to is not memorised as a search, so "go to
lobsters" never becomes a search memory. Debug builds' "Clear memory"
resets the book to the seed.

`swift run --package-path Packages/Routing report sites "<query>"` prints
what `SiteQuery` makes of a query, what the seeded book says, and with
`BRAVE_API_KEY` the candidates; `report route "<query>" --opened <name>
<host>` shows the rejection judgement.

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
| `Packages/Routing/` | Foundation-only Swift package with four libraries. `Routing`: the formats and their Jev criteria, the instinct registry (`InstinctSpec`), the exchanges Jev reads (`Exchange`), the System One client, the engine's request and decision (`EngineRouting`: the pick, the relevance chain, the reasoning score, the confidence, recency and rejection gates), `QueryParser`, the on-device rules (`LocalAnswers`, `TimeQuery`, `PlaceTimeZones`, `LocalTimeAnswer`, `SiteQuery`, `SiteBook`, `SearchQuery`), the command grammars the routes apply at the edge (`SearchQuery`, `ImageQuery`, over `QueryTokens`), the log record and reports. `Answers`: the Gemini client (streamed for an answer, whole for a value or a plan), SSE parsing, the per-format prompts, the emphasis markup and the value extractor. `Images`: the Wikipedia search and summary client, the Brave image search client and the lookup that runs them in order. `Sites`: the Brave web search client. Tests run on macOS. |
| `Browser/Engine/Engine.swift` | The cognitive engine's first stage: the device's rules (each instinct's grammar), then one Jev request over the registry carrying the session's exchanges, then the chosen instinct's plan; the chain decides whether a follow-up grows the answer on screen or gets the exchanges as context. Also `BrowserSession.makeEngine()`, `makeAnswerClient()`, `makeRecallResolver()` and `makeSiteSearch()`. |
| `Browser/Engine/Instinct.swift`, `Instincts.swift` | The `Instinct` protocol (a spec from the registry and a `plan` for a decision), the registry of conformers in order, and the nine instincts the app has today. |
| `Browser/Engine/SessionExchange.swift` | A layer's thread and its exchanges: what each layer got, as the engine sends it to Jev. |
| `Browser/Answers/AnswerSession.swift` | Streams one Gemini answer: the text, the live-data marker check, and the summary for the log. |
| `Browser/Images/ImageSession.swift` | Loads one picture (and its alternates) for an image plan, Wikipedia first and Brave behind it, and the summary for the log. |
| `Browser/Memory/MemoryStore.swift` | The memories file: load once, append as results appear, refresh a repeat within a day, drop the oldest past the cap, search by words (`MemorySearch` in the package). |
| `Browser/Memory/SiteStore.swift` | The site book on disk: seeded on first load, written whole on each learn, touch, forget or clear. |
| `Browser/Engine/DecisionLog.swift` | JSON Lines log of every decision and answer. |
| `Browser/Engine/Secrets.swift` | Reads the keys from Info.plist (`TypeSafeAPIKey`, `GeminiAPIKey`, `BraveAPIKey`). |
| `Browser/Engine/CardPlan.swift` | The renderable plans. One enum case per card type. |
| `Browser/Session/BrowserSession.swift` | Owns the layers (one per query, the current one on screen; see "Layers"), runs queries through the engine, applies the plan (a recall through the memories, a site through the book or the search), opens, swipes between, unloads and reloads layers under the live cap, memorises what each layer shows, writes the log. |
| `Browser/Session/Layer.swift` | One query's result: its plan, its live page (`PageHost`) or the notes left by an unload, its own answer stream and pictures, the page it ended on (for the engine's exchanges), its opened site and memory chain, when it was last shown. |
| `Browser/Web/PageHost.swift` | One live web page: the `WebPage` with its watcher, what it pins to its edges, whether it loads or plays or is in use, the navigation watch and the document bookkeeping behind the chrome, the notes read as it goes and the restore when it comes back. |
| `Browser/Web/` | `PageChrome.js`, the watcher installed in every page (hit tests along both edges, bar or floating or none, the bar's colour composited until opaque or flagged as a guess for the app to sample, a `MutationObserver` so overlays and in-page changes report too, rules that keep a bar's verdict while its element lives, pinned itself or inside a pinned box, and hold every look until the scroll has rested, so nothing resizes under the finger or between two Shorts); `PageChrome.swift`, the state the app keeps, the message handler (chrome reports, address changes for the memories, audio, and whether the page is in use), the page's notes for an unload, the edge sampler (a 64-point-wide export of a three-point strip just inside the page's edge, accepted when near-uniform) and the page configuration that installs the script and lets video play inline (the iPhone default sends every playing `<video>`, YouTube's feed previews included, into the system full-screen player). Debug builds print each page's chrome verdict to Xcode's console. The page is never made inspectable: an inspectable page under SwiftUI's `WebView` crashes UIKit's touch delivery on the first tap (iOS 26 and 27). |
| `Browser/Home/` | The screen: `HomeView` (white background, focus state, the stage-driven cross-fade), `Clay` (the mesh-gradient circle that morphs into the capsule field and the wave line), `KeyboardHint` (the nodding chevron over a keyboard icon), `ResultView` (the web page or the answer text with its "Web results" link, under a frosted status bar; the page bounces sideways only when it is wider than the screen, since the web view's default rubber-bands sideways on every page and a vertical drag with a little drift wobbles it) `ClayCapsule` (Safari's minimised bar: the query at the foot of a result, which becomes the follow-up field above the keyboard, and swipes between layers) and `QueryField` (the text field the clay and the capsule share). No system toolbars, so no Liquid Glass. |
| `Browser/Info.plist` | Merged into the generated Info.plist. Holds what Xcode will not take as `INFOPLIST_KEY_` settings: the three API keys and `UIDesignRequiresCompatibility`. Light mode is forced by `INFOPLIST_KEY_UIUserInterfaceStyle` in the project and `preferredColorScheme(.light)` at the root. |
| `Config/` | xcconfigs. `Debug`/`Release` optionally include the untracked `Secrets.xcconfig`. |

## Modules

Each response format is a module with a stage recorded in code
(`ResponseFormat.stage` in `Packages/Routing`): `routed` (Jev can pick it,
web results stand in), `built` (a real card renders), `verified` (used on a
device and accepted). Today: `web_results` verified; `narrative`,
`one_line`, `recall`, `image` and `site` built; `map` and `stock` routed. A routed pick shows web
results and is logged as the pick it was, and each instinct asserts the
stage and its plan agree. Flip the stage in the same change that adds the card.

## How it routes

[ROUTING.md](ROUTING.md) is the routing contract, generated from the same
code the app runs: the state Jev reads, every question with its type and
options, the queries each option is meant to catch, the answer shape, what
the app does with each outcome, and then the exact Gemini system
instructions and input block for the answer formats. Regenerate it with:

```
swift run --package-path Packages/Routing report routing > ROUTING.md
```

For what real queries triggered, copy `decisions.jsonl` off the phone (the
app's container, through Xcode's device window or `xcrun devicectl`) and run:

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
order (the exchanges in the state, a relevance question per exchange, the
reasoning score), decoding of their example response, the confidence gate,
the chain and what it grows or hands on, every failure path falling back to
web results, and the address bypass; the on-device time
rule (its grammar, every alias and country row resolving to a real zone, and
the day shift and clock format against a fixed instant); the site grammar,
the seed, learning and forgetting, the `rejects` question's shape and gate,
and the Brave client against canned results; and for Gemini, the
request body and key order (and that no tool is sent), the per-format prompts
and budgets, the context block, SSE parsing, a canned stream end to end,
error frames, timeouts, and old log lines without answers. Nothing here needs
a simulator.

## Deliberately absent

Dark mode, Markdown in answers, the Debug ribbon (the log still records every decision; summarise
it with the report CLI), tabs, history, bookmarks, content blocking, reader
mode, the map and stock cards, live search behind answers (see
"Answer cards" for why Google's grounding was removed), location, the
backend (the Jev and Gemini requests move behind it later, taking the keys
with them).
