# Modules

Generated from `ResponseFormat` in `Packages/Routing`. Do not edit by hand; run:

```
swift run --package-path Packages/Routing report modules > MODULES.md
```

| Module | Jev option | Stage | Renders today | Needs |
|---|---|---|---|---|
| Web results | `web_results` | verified | its own card |  |
| Summary | `summary` | routed | web results (fallback) | Opus 5.5 streamed prose card |
| Images | `images` | routed | web results (fallback) | Image provider (Serper images) and a grid card |
| Map | `map` | routed | web results (fallback) | MapKit card with an MKLocalSearch pin |
| Flights | `flights` | routed | web results (fallback) | Route and date extraction (Haiku), Amadeus lookup, list card |
| Stock | `stock` | routed | web results (fallback) | Ticker resolution, a market-data provider, Swift Charts card |
| One-word answer | `one_word` | routed | web results (fallback) | Answer source (Haiku or Serper answer box) and a single-line card |
| Presentation | `presentation` | routed | web results (fallback) | Opus 5.5 sectioned output and a paged card |
| Videos | `videos` | routed | web results (fallback) | YouTube Data API search and a list card |
| Links | `links` | routed | web results (fallback) | Resolve the named site and open it directly |

1 of 10 verified, 0 built, 9 routed.

## Stages

- **routed**: Jev can pick it; the app shows web results in its place.
- **built**: a real card renders for it.
- **verified**: used on a device and accepted.

A module moves stage in `ResponseFormat.stage`, in the same change that adds its card. `JevRouter.plan(for:query:)` asserts the stage and the card agree, and the `ModulesTests` suite fails until this file is regenerated.
