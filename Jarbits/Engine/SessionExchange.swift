import Foundation
import Engine

/// One exchange of this session as the engine sends it to Jev, with the
/// layer it came from and, for an answer, the turn it was.
struct SessionExchange {
    let exchange: Exchange
    let turn: AnswerTurn?
    let layerID: UUID
}

extension Layer {
    /// The conversation this layer shows, oldest first: an answer card,
    /// narrative or one-line, whose answer is in (or stopped with some
    /// text), the time from the clock, or a remembered
    /// conversation. What a follow-up typed over it may continue. Empty for
    /// anything else, including an answer still streaming.
    var thread: [AnswerTurn] {
        switch plan {
        case let .answer(format, query, history, _) where format.isAnswered:
            guard let answer, answer.query == query, !answer.text.isEmpty else { return [] }
            switch answer.phase {
            case .done, .failed: return history + [AnswerTurn(query: query, answer: answer.text, format: format)]
            case .idle, .waiting, .streaming: return []
            }
        case let .time(query, text):
            return [AnswerTurn(query: query, answer: text, format: .oneLine)]
        case let .said(query, text):
            return [AnswerTurn(query: query, answer: text, format: .narrative)]
        case let .memory(record) where record.kind == .narrative || record.turns != nil:
            let kind: Instinct = record.kind == .oneLine ? .oneLine : .narrative
            return record.turns ?? record.text.map { [AnswerTurn(query: record.query, answer: $0, format: kind)] } ?? []
        default:
            return []
        }
    }

    /// What this layer got, as exchanges for Jev: one per turn of an
    /// answer, one for the page it ended on (or the results page it shows),
    /// one for a picture, a grid of memories or a choice of sites. Nothing
    /// for an answer still streaming.
    var exchanges: [SessionExchange] {
        switch plan {
        case let .web(url):
            let address = pageAddress ?? notes?.address ?? url
            if QueryParser.isSearchResults(address) {
                let term = QueryParser.searchTerm(in: address)?.trimmingCharacters(in: .whitespacesAndNewlines)
                return [SessionExchange(exchange: .search(query: query, term: term?.isEmpty == false ? term! : query, own: desk ? true : nil), turn: nil, layerID: id)]
            }
            let title = pageTitle ?? QueryParser.displayText(for: address)
            // A page on Jarbits's own screen is marked as its: the user never saw it.
            return [SessionExchange(exchange: .page(query: query, title: title, address: address, own: desk ? true : nil), turn: nil, layerID: id)]
        case .answer, .time, .said, .memory:
            return thread.map { SessionExchange(exchange: .answer(query: $0.query, text: $0.answer), turn: $0, layerID: id) }
        case let .recallPicker(records, title):
            return [SessionExchange(exchange: .recall(query: query, title: title, titles: records.map(\.title)), turn: nil, layerID: id)]
        case let .siteChoices(name, candidates):
            return [SessionExchange(exchange: .site(query: query, name: name, hosts: candidates.map(\.host)), turn: nil, layerID: id)]
        case let .note(note):
            return [SessionExchange(exchange: .note(query: query, title: note.title, excerpt: note.excerpt), turn: nil, layerID: id)]
        case let .notes(notes, title):
            return [SessionExchange(exchange: .note(query: query, title: title ?? "my notes", excerpt: notes.map(\.title).joined(separator: "; ")), turn: nil, layerID: id)]
        }
    }
}
