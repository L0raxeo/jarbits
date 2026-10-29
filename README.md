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
the request, the values it takes, and its side effects. The app binds each spec to an
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
- **The pick is a shortcut.** A pick at or above
  `EngineRequest.confidenceFloor` (0.9) runs straight. Below it the query
  is planned (see "Advanced reasoning"): the planner reads the request
  with every instinct as a tool and calls what fits; logged as
  `confidenceFallback` with the pick kept as `suggested`. Google is never
  the engine's own fallback; the planner may choose `web_results`. Without
  a Gemini key, or on an error or the 20 s timeout, web results stand in.
  Nothing overrules a sure pick: Jev's
  `recent` answer is the answer instincts' to act on (a reply that may have
  gone stale is web results instead, logged as `recency` on the pick's
  line), and its `rejects` answer is the site instinct's.
- **Values.** A closed-set value, a choice or a yes/no, is two more Jev
  questions in the request for every instinct that declares one, read only
  for the pick (`<instinct>.<field>?` and `<instinct>.<field>`; the
  decision's `arguments`). Every free-form value the picked instinct
  declares (`InstinctSpec.arguments`: `site.name`, `time.place`,
  `forget.about`, recall's count and span) is one small Gemini call after
  the pick (`ValueExtractor`: Flash-Lite, a JSON schema of the fields,
  2 s) reading them out of the read words; `remember.fact` is the fact
  reader's (see "Facts"); no grammar reads the words. `web_results`, `image` and `video` declare none and search
  the read words as they are. Nothing usable, or a required value still
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
  request, so "wait no I meant brazil" after a search is a search for
  Brazil, "how big is it" after reading a page is an answer that knows the
  page, "and chile?" after "capital of peru" answers in one line, "why?"
  after it answers in a paragraph, and "pictures of it" is a picture of
  the thing.
- **Only an instinct whose whole input is in the words runs straight.**
  A search, a question, a picture, videos, a site name, a place, a fact
  to keep or drop, something to recall: those earned the shortcut
  (`InstinctSpec.shortcut`). Everything else is reasoned, however sure
  Jev was: the planner runs it with the screen, the stores and every tool
  in view and fills its values itself, told "The classifier picked
  notebook with confidence; you run it, because it acts on things". A
  new instinct is reasoned unless it earns the shortcut, so the next
  module lands on the planner with nothing to anticipate. The notebook is
  reasoned.
- **An instinct that cannot do the thing hands the query to the planner.**
  Nothing found to recall, no note the words mean, no site found for a
  name, a place the clock does not know, no fact to forget: the instinct
  returns why, in Jarvits's words (`InstinctOutcome.failed`), shows
  nothing, and the session plans the query under the wave line with
  "Tried first, and could not: …" as the planner's first line, so it
  does what the request needs another way, or says so. Without a planner,
  web results. In a plan, a failed step's result reads "could not: …".
- **The instinct runs** (`Browser/Engine/Instincts.swift` and the files
  beside it): `web_results`, `map` and `stock` load a Google results page
  for the words; `narrative` and `one_line` stream an answer, or show web
  results when Jev's `recent` says the reply may have gone stale; `time`
  answers from the device clock for the place the extractor read, here
  when it read none; `image` loads Google's image results for the words;
  `video` loads Google's video results for them; `recall` works the memories (see
  "Recall"); `site` works the site book and the search (see "Sites");
  `remember` and `forget` work the facts (see "Facts"); `notebook` works
  Jarvits's notes (see "Notebook"). A query whose
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
A case whose `instinct` is `planned` expects an unsure pick, which the
engine plans; `pick` can pin what Jev leaned to. The set is 121 of 121
after the floor rose to 0.9 (2026-10-29): fifteen cases under it became
`planned`, and five long dictated stories joined it.

The planner has its own set, `Packages/Engine/Evals/plans.jsonl`: a
request with the exchanges, facts and memories around it, and the calls
the first round should make, by name in order, with any argument that
matters pinned (a handle, say). `swift run --package-path Packages/Engine
report plans` runs them with the Gemini key, caches each first round by
its request bytes (`.evalcache/plans/`), and prints passes, misses with
what was called instead, and a count per first call. The first round is
where the choice of tool and handle is made; what follows depends on
what the device did and is the phone's to check.

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
"instinct": …}` line labelled with what the app did (`planned` for an
unsure pick), to paste into `engine.jsonl` as is when that was right or
with the instinct corrected when it was not. Rows come most doubtful first: a confidence or recency within
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
exchanges, today's date and what is on the screen (the selection and the
visible text; see "Screen awareness"), and a one-field schema: `query`, the request
standing on its own (dictation noise, interjections, fillers and false
starts dropped, every word that carries meaning kept, in the person's own
wording and language, and anything the words point back at folded in:
"pictures of it" after a Brazil page → "pictures of Brazil"). When the substance
differs from the typed words (`Substance.differs`: case, diacritics,
punctuation and spacing aside), Jev is asked again on the read words and
that pick wins, and they are what the instinct, the planner, the exchange,
the layer, the extractor and the label on screen receive. The same
substance, a miss, or a reply slower than `QueryReader.timeout` (4 s; the
Mac sees 1.0 to 1.4 s, and a miss sends a chained search out unresolved)
leaves the first pick standing on the typed words. The trade is
latency: a query waits for the slower of the two calls, Jev's few hundred
milliseconds or the reading's (the first real calls took 0.97 and 1.38 s,
about five thousandths of a cent each), and a rewritten query pays one
more Jev request. The typed words stay on the decision's line as
`reading.original`; its `query` is what ran. The console prints
`reading "typed" -> "ran"`. Try one with `report read`.
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

## The bubble

A reply that does not need the whole screen is shown in the bubble
(`ReplyBubble`, `BrowserSession.reply`): one view in the page's own
layout, never a sheet, grown upward from the clay. Over a result it sits
directly above the query capsule in the keyboard-aware layer of
`HomeView`, the capsule's width, and rides the keyboard with it; on the
idle screen it sits above the clay's circle, mid-screen, and the capsule
at the foot appears only once a layer is shown. The page stays live and
tappable around it. Three sizes, picked on the device from the content
(layout, not interpretation):

- a line: a one-liner, the time, a mark ("Remembered: I'm vegetarian",
  quiet, gone after three seconds), a limit the planner states;
- a card: a narrative, what the planner said (`say`), or a question with
  its one to three buttons or a line to type (`ask`, "What's your
  name?", "Delete my note …?", "Forget which?"); it grows to at most 40%
  of the screen, and past that the text is cut at the foot with "Read
  on";
- the full view: the answer layer as before, reached by "Read on", by a
  drag up on the card, or by a follow-up that continues the reply ("why?"
  after a narrative): the same layer object is put into the stack
  (`promoteReply`), its text and turns carried over, and from then on it
  swipes like any other.

The one idea underneath: a reply is a `Layer` held in `reply` instead of
pushed onto the stack. So its thread and exchanges reach Jev, the reader
and the planner as the newest exchange ("Asked X and got Y"; `focus` is
the reply when one is up, else the current layer), an `AnswerSession`
streams into it, its memory is written against it, and its record is
kept. A drag down puts it away; a new layer opening, a swipe between
layers, or the circle clears it; a question put away answers nil, as the
sheet's swipe did. A fresh one-line or narrative answer goes to the
bubble (the clay or the capsule waves until the first text, then the
screen goes back to where it stood and the bubble shows); a follow-up
that continues a conversation already in the full view grows that layer
as before. A narrative that needs live data still becomes web results,
in the stack.

A plan or an answer that brings nothing no longer becomes a web search
for the words, which read as a mishearing on "add this to my wishlist":
the bubble says so ("I couldn't get through that one.", "That took too
long to work out.", "Nothing came back.") with "Try again" and "Search
instead" under it, and the screen stays as it stood
(`BrowserSession.offerRetry`). Without a planner at all, web results
still stand in.

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
word list reads the query. The thing to bring back is the extractor's
`topic` ("that thing about gingivitis again" → "gingivitis"; null when
the words name nothing), and the records left are ranked by its words, in
their queries, titles, addresses and text; a name spelt nearly right
still counts ("hennessy" finds "hennessey", as dictation spells names);
records holding every word win, then records holding any, then the rest
of the filtered set newest first; at most ten (`MemorySearch.shortlist`).
When the meaning index can say (below), the records nearest the topic in
meaning lead, taking turns with the word matches, so "that car page"
reaches a page titled "Hennessey Performance" with no word in common;
a count or nothing named stays by recency whatever the index says.
With no filter and no topic there is nothing to go on, and the words go
to the web. Last, the
shortlist goes to Jev in one request, a yes/no question per memory naming
its kind, when, its host and its title (`RecallRouting`, see ENGINE.md).
A memory at or above 0.5 is the one asked for and is shown alone;
otherwise everything at or above 0.3 is plausible and is shown in Jev's
order. Nothing ever opens straight away: even a single memory is shown in
the grid, so the user sees what was found before it takes the screen; nothing
plausible falls through to a Google search for the topic ("that thing
about gingivitis again" searches "gingivitis"), or for the words as they
ran when none was named, so a wrong
judgement costs nothing visible. A failed or slow Jev request, or no key,
shows the shortlist in word order instead. The kind words are a preference,
not a wall: "what you told me about the dyson" prefers an answer, but when
no answer holds those words and pages or searches do, those are shortlisted.

A query that asks for everything ("pull up everything we talked about with
the Dyson PencilVac", "all the videos from yesterday") wants a collection,
not one thing (`RecallAsk.collection`). The kinds become no bar, the
shortlist is every memory holding any of the topic's words (a span still
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

## Jarvits and the user

The app is an assistant, Jarvits, assisting the person holding the phone;
he is not that person. Every Gemini instruction he sends opens with one
of two lines (`Persona` in the Answers library). Where he writes or
answers (the fact reader, both answer formats, the planner):
"You are Jarvits, the assistant in Lorcan's phone browser. Lorcan is the
person speaking to you; you are not Lorcan. Speak of Lorcan by name and of
yourself as Jarvits." Where he only reads (the reading, the value reader)
the last sentence is instead "What you hand back is Lorcan's request in
Lorcan's own words, not your words about it", so a search or a pick never
sees the user's words recast in his. A question about the user's own life
("do I have any vegan friends") is answered from the facts: Jev's recency
question says such a question does not go stale, and the answer prompts
say to answer it from the facts block alone, or to say in a line that
Jarvits does not know that yet. For that he needs the user's name: with none known,
the home screen puts "What's your name?" in the bubble as soon as the
circle is idle (`BrowserSession.askNameIfNeeded`), once per launch; a
swipe away asks again at the next launch, and until a name is given the
prompts say "the person you assist". The name lives in
`facts.profile.json` beside the facts (`FactStore.userName`) and goes with
"Clear memory", which asks it again at once. Jev never sees any of this.

## Notebook

Jarvits keeps a notebook: notes the user types into, with bold, italic,
headings, bullets, numbered lists and checkboxes, kept as Markdown files
on the device (`Application Support/Browser/Notebook/<id>.md`: the first
line `# Title`, a blank line, the body), permanent, not memories. There
are no folders and no tags: the user asks for a note and Jarvits finds
it. He speaks of "my notebook" and "my notes": it is his way of keeping
things for the user.

The `notebook` instinct, the thirteenth, is reasoned: Jev picks it and
the planner runs it, with the page on screen, every note of the notebook
and the facts in view. It takes what to do as a closed-set value Jev
reads in the request (`action`: `new`, `add`, `replace`, `open`,
`delete`), whether the whole notebook is asked for (`all`, a yes/no Jev
reads too: "pull up all the notes in your notebook" shows the grid of
every note, newest first, "My notes · N", or "My notebook is empty."),
two things by handle, and `topic`, `title` and `text` as values the
extractor reads. The two things: `note` is the note to act on, `item` is
a page or answer to put into it, whose title and link go in as a link
line. "Add this to my watchlist" on a video is `notebook(add, note: n1,
item: p1)`; "add milk to my shopping list" is `notebook(add, note: n1,
text: milk)`. Which note a request means is the planner's reading of the
listing, where every note stands whole (title, when it was edited, then
every line as written, marks and all, numbered from 1, links as their
titles, cut after 60 lines or 3,000 characters), whatever words the request uses for it: "my watchlist"
reaches a note titled Watch List because the planner reads that they
mean the same, and nothing on the device re-judges its choice. (A Jev
yes/no judge once stood between the two and scored "Watch List" 0.32
against that request, under the 0.5 it acted on, so a second note named
"watchlist" was made; a classifier was asked to read.) A `topic` with no
`note` handle means no listed note was it: `add` and `new` make a note
by that name; `open` and `delete` fail ("no note of mine is "x"; the
notes I have are listed"), and the planner takes the next step, with the
listing still in view. `new` with nothing to write makes an empty titled
note and opens it for typing. The planner writes what goes in, the way
a person would after reading the note: `text` is the exact lines as they
will stand, in the marks of the lines around their place ("- milk" after
a bulleted list, "- [ ] passport" in a checklist, the next number in a
numbered list, plain words after prose; a new list in a note of prose is
a blank line, a heading and its first item; an empty note starts the way
its purpose reads), with `{item}` on its own line where a kept page or
answer goes ("- {item}" in a list), and `after` is the number of the
listed line the lines follow (0 the top, none the end), so a note with
a groceries list and a packing list gets eggs under the groceries. The
device places the lines and fills the item's title and link
(`NoteMarkdown.insert`), and decides no form; it completes two things
only: bare words directly after a list item continue that list, as a
return at the end of a list does in Notes (`NoteMarkdown.continuing`),
and a numbered run the lines land in is counted again from 1. Several notes shown at once go to the grid
(`NotesGridView`, the recall grid's layout, headed in his voice: "My
notes · 3"), by `open` with several handles or the notebook's `all`. A delete asks in the bubble ("Delete
my note 'Packing list'?") and moves the file to `.trash/`, never gone.
Every append or replace first copies the text as it was to
`.versions/<id>/`, so any edit by Jarvits can be undone. Every change
shows the note afterwards.

The note card (`NoteView`) is laid out like the iOS Notes app: one page
you write on, the first line the title (large and bold, whatever is typed
there; an empty first line titles the note from its first words), the
rest the body, in one rich editor over an attributed string, scrolling as
one, the query capsule floating over it with no bar of its own below. A
bar above the keyboard offers the six forms while the note has the
keyboard, and not while the capsule does. A page kept in the note is its
title in link colour in the text, and a tap opens the page; there is no
separate list of links. Typing saves after a pause and on leaving; the
file is the truth, and a note Jarvits changes while it is on screen is
reloaded.
`NoteMarkdown` in the Engine library turns the file's Markdown into the
editor's text and back, exactly the six forms, a paragraph attribute
carrying each line's form; the editor shows bullets, numbers and
checkboxes as marker characters at the line's start (`NoteDisplay`), and
the file never holds a marker. A page kept in a note is a link, the
seventh form: the file holds `[title](url)` and the editor shows the
title, tappable. Anything else is kept as plain
text. Opening or changing a note is an exchange (`note`), so "what
does it say" works and the planner sees it; notes are never memories and
recall never searches them. The planner's listing holds every note as
`n1, n2…`, newest first, beside the memories; nothing thins it. "Clear
memory" leaves the notebook alone.

**Finding by meaning.** `MeaningIndex` in the Engine library keeps,
beside a store, the meaning of each thing as a vector from an `Embedder`
and answers "the nearest to this request" by cosine; `NoteSearch.shortlist`
and `MemorySearch.shortlist` take its order (`ranked`) and put the nearest
first, taking turns with the word matches. The memories have one
(`Application Support/Browser/memories.index`, a compact binary file of
id and vector, rewritten a second after the last change, only ever a
cache of the memories file): every record kept is embedded from its
title, query, host and first words (`MemoryRecord.indexText`), a forget
or a flush removes it, and the first look after a load catches up on
anything kept before the index existed or while offline, a hundred at a
time. The embedder is Gemini's (`GeminiEmbedder` in the Answers library,
`gemini-embedding-001` at 768 dimensions, a record embedded as a
document and a request as a query, Google's two task types; nil on any
failure, never a throw, so the look falls back to words and recency).
The notebook has none: every note is listed and the planner reads.
Apple's on-device models were measured first (2026-10-28) and are not
it: the sentence embedding ranked "add this to my watchlist" nearer
"Ideas" and "Packing list" than "Watch List", and "shopping list" nearer
"Packing list" than "Shopping"; the word embedding did better on notes
but put "Watch List" first for "open my grocery list" and knows no names
(Hennessey, Dyson), so memories ranked wrong. `swift run --package-path
Packages/Engine report nearest "<request>" "<text>"...` prints Gemini's
ranking of a few texts for a request, from the Mac.

## Facts

A fact is one thing Jarvits knows about the user, noted from his point of
view: "Lorcan is allergic to peanuts", "Lorcan's friend Noah is vegan",
"Lorcan's mom Jasmine is 50". Facts are the second memory store, beside
the memories of things seen: few, short, and never expiring on their own.
Every fact goes into every answer (`AnswerPrompt`'s "What Jarvits knows
about Lorcan" block, after the context and the earlier exchanges; the
prompts say to let them shape the answer when they bear on it and never to
repeat them), and into every plan. Nothing in the
file leaves the phone except inside a Gemini request, which keeps nothing
(`store: false`).

A fact comes to be known three ways (`Fact.source`):
- **told**: "remember that I'm allergic to peanuts", "keep in mind I'm
  vegetarian", "note that I don't eat pork". Jev picks the `remember`
  instinct; the fact is what the fact reader (`ValueExtractor.distill`,
  the same call that notes a fact on any other pick) reads out of the
  words, as Jarvits notes it, naming the user and whoever else it is
  about ("Lorcan's friend Bob is vegan.").
  A plain statement with nothing asked ("I live in austin now") is a
  remember too.
- **inferred**: the query states something lasting on the way to asking
  something else ("I'm allergic to peanuts, what can I snack on"). Every
  request carries a `remember` question (ENGINE.md); at or above
  `EngineRequest.rememberThreshold` (0.5) on any other pick, the pick runs
  as usual and the same small call distils the fact into one sentence as
  Jarvits notes it, which is kept quietly. The query waits for that call
  (about a second) before the pick runs.
- **chosen**: the answer to a question a plan put in the bubble, when the
  plan keeps it (a `remember` step right after an `ask`; see "Advanced
  reasoning").

Keeping a fact shows one quiet line for three seconds, "Remembered: Lorcan
is vegetarian", above the capsule over a result or under the clay on the idle
screen (`RememberedMark`): the only sign that something was kept, so a
wrong note can be seen and undone. The same words again (case and
punctuation aside) refresh the fact rather than repeat it.

"Forget that", "forget that I'm vegetarian", "stop remembering my peanut
allergy" is the `forget` instinct, the first destructive one: the facts
the words point at are shortlisted on the device (`FactSearch`: the ones
holding any word of what the forget is about, the extractor's `about`,
first, then the newest, so a bare "forget that" offers what was just
kept), judged by Jev one yes/no each as
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

The pick is a shortcut for a request Jev is near-certain about.
Everything else is reasoned: a pick under `EngineRequest.confidenceFloor`
(0.9; "Remember the story about my friend Noah…" at 0.45 remember, 0.48
recall), or a sure pick that needs several steps, a condition, or a value
no instinct has on its own ("remember I'm vegetarian, then suggest a
dinner", "find that car page again and tell me where the nearest dealer
is"). Every request carries a reasoning `score` (ENGINE.md: direct, needs
a value, needs sequencing); at or above `ReasoningPolicy.threshold` (1.2;
the two-step "remember I'm vegetarian, then suggest a dinner recipe"
measured 1.46 and a plain remember 0.82) a sure pick is planned too. The
engine hands such a query to the executor
(`Browser/Engine/Executor.swift`) rather than to the pick. Without a
Gemini key the pick runs as it would, and an unsure one is web results.

## Screen awareness

Users point at the screen: "fetch the link of the video", "open the
second one", "how much is this", "add the third result to my watchlist",
"what's the blue button for". Siri answers these by reading an app's
accessibility tree; this app owns its web view, so it reads the screen
exactly, once, as a query starts (`Layer.screen()`, `Screen` in the
Engine library). A web page gives, through one call into the page's own
script (`PageChrome.js` `screen()`, bounded at 1.5 s), the text in the
viewport in full (up to 4,000 characters), the rest of the page's text
(up to 8,000), the selection, and the links in view with their text and
address (up to 40, one per address); and, through WebKit's image export
(bounded at 2 s, in parallel), a JPEG of the viewport at 1024 points
wide. A note gives its text, an answer its text, a grid its tiles. Jev
never waits for any of it: it is asked the moment the query starts, and
only the reader and the planner wait. A read that fails leaves the query
exactly as before: the title and the address, no block, no picture.

Every model that interprets then sees the screen, under one rule, the
same words for the reader and the planner (`Screen.rule`): the screen is
what the user sees now; fold it in only where the words point at it
("this", "that one", "the second", "here", "the one shown", "the price on
the page"); a request that stands on its own, or leans on an earlier
exchange, is left as it is. The reading gets the selection and the
visible text before the request, so "how much is this" reads as the
thing it is. The planner's first turn ends on the whole screen (the
visible text, the rest, the links in view) and carries the picture as a
second content part (`{"type": "image", "data": <base64>, "mime_type":
"image/jpeg"}`, Google's Interactions API shape), with one more rule:
what the picture shows that the text does not (a colour, a position, a
chart) is read from the picture; anything the text or the listing names
is named by its handle. Each link in view is a thing, `s1, s2…`, beside
`p`, `m` and `n`: "open the second video" is `open` with `s2`; "add the
third one to my watchlist" is `notebook(add, note: n1, item: s3)`; "fetch
the link of the video" is `say` with the page's own address, which the
screen's line gives in full, since the device filled it. No kind is
guessed from an address: the planner reads what an item is from its text
and host. An answer on the straight path gets the whole screen in its
context when Jev chained the layer on screen or the thing it is about is
that layer; an answer a plan asks for gets it always, since the planner
wrote the question with it in view. Jev stays blind, but its reasoning
question's top level (the one that reaches the planner) names "the words
point at something on the screen that must be looked at before any
format can act", so a sure pick like `video`, `site` or `one_line` does
not run on words alone for "open the second one" or "how much is this";
the middle level (a value to read out of the words) never reaches the
planner by itself, and no extractor can read the screen, so the clause
belongs at the top (measured 2026-10-29: in the middle level "how much
is this" scored 0.98 and went to web results for its price). The log
line and the plan record carry the screen's sizes (`screenChars`,
`screenItems`, `pictureBytes`).

Nothing on the device decides from the page's text; it only puts it in
front of the model. The eval sets keep the rule honest with pairs: each
screen case ("how much is this" over a product page, "open the second
video" over a results page) has a sibling of the same shape that leans
on the chain or on nothing ("how old is he" after an answer with a
product page open, "google chocolate milk" over any page, "what is a
venom f5" over the Hennessey page), and the pair must come out apart.
`report plan "<query>" --screen <title> <url> <visible text> --link
<text> <url>... --picture <jpeg>` prints the first turn as the app sends
it (the picture shown as `<picture>`) and, with the key, runs one round.

**The page's own data.** Most pages publish facts for search engines and
link previews that they do not draw: the canonical address, the preview
title and description, and structured blocks (a product's price and
availability, a video's duration and upload date, an article's author and
date, a recipe's ingredients). The screen read collects them in the same
call (`PageChrome.js` `pageData()`: the canonical link, a fixed set of
preview tags, and every JSON-LD block flattened to `dotted.key: value`
lines, strings and numbers only, in the page's own words, 1,500
characters at most) and they ride with the screen as `Screen.data`, in
the planner's and an answer's block under "The page's own data", not in
the reader's. "How long is this video" on a page that draws no duration
is answered from `duration: PT12M4S` in the first turn, with no look.

### Looking deeper into a page

What the eye cannot reach from the screen needs a read: "summarize this
page" when the article runs past the block's cap, "put every link in this
article in a note", "which plan is cheapest" when it sits in a table. The
planner has a `look` tool for it (`Planner.lookTool`): `what` is one of
`text` (the page's paragraphs, numbered, 4,000 characters a look, ending
"… continues at paragraph N" when cut; `from` continues it), `links`
(every link on the page in screen order, top then left, forty a look,
each minted as an `s` handle that continues the screen's series, so it
can be opened or kept), `outline` (the headings with their paragraph
numbers, so a `text` look can start at a section) and `tables` (each
table as rows, cells joined with `|`, 3,000 characters). It reads the page
on screen, or an earlier page of the session that is still open in a
live layer (`page: p2`); a link in view is not an open page and the result
says to open it first; no page is loaded unseen. The page's own script
answers (`PageChrome.js` `look()`, bounded at 3 s, `PageHost.look`), the
executor sends the result back as the step's text (`Planner.looked`), and
a look that finds nothing says so, so the planner falls back to the
picture.

When Jarvits looks, from the user's side: when the request asks for what
the screen block does not hold, the text further down, the whole set of
links, a table, a page's facts the block lacks. When he does not: when the
thing asked for is in view ("how much is this" with the price on screen,
"open the second one"), when the request stands on its own or leans on an
earlier exchange, and when it is about how the page looks, which is the
picture's job. The tool's description and one rule in the planner's prompt
say exactly this, and the eval set keeps it honest with pairs: "summarize
this page" over a cut article looks, over a short page it does not; "put
every link in this article in a note" looks at the links, "add this to my
reading list" keeps the page; "which plan is cheapest" looks at the tables
when the prices are not drawn, and answers from the block when they are.
A case may seed steps already taken (`prior` in `plans.jsonl`: the call
and the device's result, put in the transcript as the API gives them), so
the round after a look is tested too: the summary written from what was
read, the links kept by handle in one write (the notebook's `item` takes
several handles, "s3, s4, s5, s6", and `{item}` in its text becomes one
line per item).

What a look cannot read: links drawn as buttons with no address until
tapped, content inside frames from another site, and content a page only
loads as it is scrolled; the fallback for each is the picture and a tap.

**What leaves the phone with a query.** The visible text, the selection,
the links in view, the page's own data and the rest of the page (capped as
above) go to Gemini with the query, for the reading and, when the query is
planned or an answer is about the page, for those; a planned query also
sends a picture of the viewport, and a plan that looks sends what the look
read: up to 4,000 characters of the page's text, forty links, the
headings, or 3,000 characters of tables, per look. Jev gets the query and
the exchanges' titles, never the page's text or the picture. Nothing is
kept by Google (`store: false`).

The planner (`Planner` in the Answers library) asks `gemini-3.1-flash-lite`,
the extractor's model, at high thinking (accuracy over speed and cost,
Lorcan 2026-10-29; `store: false`; prices in `GeminiPricing`), with every instinct as a tool,
each taking a `query` and its own fields, plus three the executor answers
itself: `ask` puts one question in the bubble (up to three options, or a
line to type), `say` shows the planner's own text in the bubble as it is, and
`done` ends the plan. `say` is for what the planner already holds in full
(the facts, the memories shown to it, earlier steps' results), including
"I don't know that yet"; a question needing knowledge beyond that goes
through `narrative` or `one_line` with a question the planner writes,
folding in what earlier steps returned, never an answer written into a
question. A said card is styled as a narrative whatever its length, the
capsule shows the user's words, and it is kept as a narrative memory so
"that story you told me" brings it back. It is told the classifier was unsure or saw
several steps, so the request may need one tool or many; and a request
about the user's own life is served from what it knows of them (remember,
recall, answer from the facts, or say it does not know), never made up.
The first turn carries the request, the exchanges it depends on (the
chain) with the layer on screen always among them, so "this" is a thing
the planner can point at, the five memories nearest the request in
meaning (the newest, without the index; recall is its tool for anything
beyond them), every note of the notebook, a line each, and last the
screen as the user sees it, its links in view as `s` handles, with its
picture as a second content part (see "Screen awareness"); nothing in
the listing is judged or thinned by a second model, since reading what a
request means is the planner's work. Every fact
goes in the system instruction, as it does for an answer. A later showing step replaces what the step before
showed; the planner is told to end on what the user should see, and
nothing refuses a second card.

The executor runs each call in order through the same paths a single
query takes: a showing instinct through the session, waiting until its
layer is ready; an acting one through its `act`. A paid or destructive
step is put to the user first ("Go ahead: …?") unless the instinct asks
for itself, as `forget` does; the same call twice runs once; a second
thing to show is refused, since a new layer would replace the first; an
answer in the bubble goes back to the model as the step's result, and a
`remember` right after it keeps the fact as **chosen**. Each result goes
back as a `function_result`, with every model step replayed verbatim, for
at most six rounds within two minutes, each round within forty-five
seconds. The
plan ends on `done`; when nothing was shown or done, web results for the
words; on a no in the bubble; when the rounds or the time run out; or when
a newer query takes the screen, where it stands and never after a step
with a side effect. The wave line stays up while the plan runs; a plan
that only did something hands the screen back to where it stood, as
`remember` does.

**Things and handles.** The first turn tags each earlier exchange of the
session (`p1`, `p2`, oldest first), each memory shown (`m1`, `m2`), each
note (`n1`, `n2`) and each link in view on the screen (`s1`, `s2`): a
handle (`ThingTable` in the Engine library). The planner points at a
thing by its handle and never sees or writes an address; the device knows
each thing exactly (a page's address, a search's term, an answer's text, a
memory's record) and swaps the handle for it before a step runs. A tool
field of kind thing takes a handle: `open.thing`, and an answer's
optional `about`, which puts the thing in the answer's context block. In
a plan, `recall` shows nothing: its result names what it found by handle
("found m6: A page from yesterday (dyson.com): …"), minted into the
listing, so the next step can `open` one or several (several of a kind,
notes or memories, go to a grid, which the tool's description says is how
the user sees more than one at once), `say` something about it, or
answer with it in view; "find that car page again and tell me where the
nearest dealer is" is a recall, then an open or an answer, in one plan. A
handle not in the listing fails the step ("no such thing: p3; the things
are p1, p2, m1"), and two failures end the plan. On the straight pick
path, with no planner, a thing field is filled from what the query leans
on: the chain's newest page, search or answer, else the layer on screen.
Handles are for things only the device can recover exactly; a search
term, a fact, a place name stay as words.

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
so "Zillow" and "zillow.com" are one entry; the name itself is what the
extractor reads out of the words ("can you pull up youtube" → "youtube"),
or the words as they ran when it read none.

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
runs"). Nothing overrules a sure pick; an unsure one is planned. The results page a
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
| `Packages/Engine/` | Foundation-only Swift package with three libraries. `Engine`: the instincts and their Jev criteria (`Instinct`), the instinct registry (`InstinctSpec`: questions, values), the exchanges Jev reads (`Exchange`), the System One client, the engine's request and pick (`EngineRequest`: the pick, the relevance chain, the reasoning score, the confidence floor; `Pick`), `QueryParser` (an address as typed, the results pages), `Words` (the one tokenizer the stores key by), the time instinct's clock and zone tables (`LocalTimeAnswer`, `PlaceTimeZones`), the memories (`Memory`, `MemorySearch`, `RecallAsk`), the facts (`Fact`, `FactStore`, `FactSearch`, `FactRouting`), the gate into advanced reasoning and a plan's bounds and summary (`ReasoningPolicy`, `EngineSummary`), the screen as the models see it (`Screen`, `ScreenItem`: the text, the links as things, the one rule), the reading's summary, the log record and reports. `Answers`: the Gemini client (streamed for an answer, whole for a reading, a value or a plan), SSE parsing, the per-format prompts, the emphasis markup, the reader (`QueryReader`), the value extractor and the planner (`Planner`: every instinct as a tool, the plan's system instruction and first turn, one round). `Sites`: the Brave web search client. Tests run on macOS. |
| `Browser/Engine/Engine.swift` | The cognitive engine's first stage: an address as typed, else one Jev request over the registry carrying the session's exchanges with the reading beside it, the extractor for every value the pick declares, and the instinct to run with what it needs; or the hand-off to the executor when the reasoning score says the query needs several steps. Also `BrowserSession.makeEngine()`, `makeAnswerClient()`, `makeRecallResolver()` and `makeSiteSearch()`. |
| `Browser/Engine/Executor.swift` | Advanced reasoning's second stage: runs a plan round by round, each call through the instincts, the sheet and the session, confirming a paid or destructive step, refusing a repeat or a second thing to show, and sending every result back to the planner until `done` or the bounds. |
| `Browser/Engine/Instinct.swift`, `Instincts.swift`, `SiteInstinct.swift`, `RecallInstinct.swift` | The `InstinctRunner` protocol (a spec from the registry and `run`, through the session), the registry of runners in order, the showing instincts, and the two that own a store: the site book and the search, the memories and Jev's judge. |
| `Browser/Engine/SessionExchange.swift` | A layer's thread and its exchanges: what each layer got, as the engine sends it to Jev. |
| `Browser/Engine/FactInstincts.swift` | The two instincts that show nothing: `remember` keeps a fact, `forget` judges which one the words mean and asks in the bubble. |
| `Browser/Engine/PendingQuestion.swift` | One question put to the user in the bubble and the wait on its answer, resumed once by a tap, a return or a cancel. |
| `Browser/Answers/AnswerSession.swift` | Streams one Gemini answer: the text, the live-data marker check, and the summary for the log. |
| `Browser/Memory/MemoryStore.swift` | The memories file: load once, append as results appear, refresh a repeat within a day, drop the oldest past the cap, search by words (`MemorySearch` in the package). |
| `Browser/Memory/SiteStore.swift` | The site book on disk: seeded on first load, written whole on each learn, touch, forget or clear. |
| `Browser/Home/ReplyBubble.swift`, `RememberedMark.swift` | The bubble (see "The bubble"): a reply in a line or a card above the clay, a question with its buttons or a line to type, "Read on" to the full view; and the mark's type, the quiet line shown in it for a moment after a fact is kept or dropped. |
| `Browser/Engine/DecisionLog.swift` | JSON Lines log of every decision and answer. |
| `Browser/Engine/Secrets.swift` | Reads the keys from Info.plist (`TypeSafeAPIKey`, `GeminiAPIKey`, `BraveAPIKey`). |
| `Browser/Engine/CardPlan.swift` | The renderable plans. One enum case per card type. |
| `Browser/Session/BrowserSession.swift` | Owns the layers (one per query, the current one on screen; see "Layers"), runs queries through the engine, applies the plan (a recall through the memories, a site through the book or the search) or runs an instinct that shows nothing, keeps the facts and the mark, holds the reply in the bubble and puts a question there and waits for it, opens, swipes between, unloads and reloads layers under the live cap, memorises what each layer shows, writes the log. |
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
