# Browser

An iOS browser where a query goes through a router that decides what kind of
card to show. Today there is one card type, a Google results web view. Every
future response format (summary, map, stock, images, …) is a new `CardPlan`
case, a new SwiftUI card view, and a new provider behind the router.

## Run

Open `Browser.xcodeproj` in Xcode 26, pick your team under
Signing & Capabilities once, and run on a device or simulator. Minimum iOS 26.

## Where things live

| Path | Role |
|---|---|
| `Browser/Router/CardPlan.swift` | The response formats. One enum case per format. |
| `Browser/Router/Router.swift` | The seam: query in, `CardPlan` out. |
| `Browser/Router/LocalRouter.swift` | Hardcoded router: URL-looking input loads directly, anything else is a Google search. Replaced by the HTTP/Jev router when format two arrives. |
| `Browser/Session/BrowserSession.swift` | Owns the single `WebPage`, runs queries through the router, applies the plan. |
| `Browser/Cards/` | One view per card type. `CardStackView` picks the view for each plan. |
| `Browser/Shell/` | Custom chrome: bottom address bar and navigation buttons. No system toolbars, so no Liquid Glass. |

## Deliberately absent

Tabs, history, bookmarks, content blocking, reader mode, backend, tests.
