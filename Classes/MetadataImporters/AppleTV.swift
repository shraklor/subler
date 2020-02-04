//
//  iTunesStore.swift
//  iTunes Artwork
//
//  Created by Damiano Galassi on 15/10/2019.
//  Copyright © 2019 Damiano Galassi. All rights reserved.
//

import Foundation

private let formatter = { () -> DateFormatter in
    let gmt =  TimeZone(secondsFromGMT: 0)
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.timeZone = gmt
    return formatter
}()

private extension MetadataResult {
    convenience init(item: AppleTV.Item, store: iTunesStore.Store) {
        self.init()

        self.mediaKind = .movie

        self[.name]            = item.title
        self[.releaseDate]     = item.formattedDate
        self[.longDescription] = item.description

        self[.cast]            = item.rolesSummary?.cast?.joined(separator: ", ")
        self[.director]        = item.rolesSummary?.directors?.joined(separator: ", ")

        self[.iTunesURL]       = item.url.absoluteString
        self[.serviceSeriesID] = item.id

        self.remoteArtworks = [item.images.coverArt16X9, item.images.coverArt].compactMap { $0?.artwork(type: .poster) }
    }

    convenience init(item: AppleTV.Item, episode: AppleTV.Episode, store: iTunesStore.Store) {
        self.init()

        self.mediaKind = .tvShow

        self[.serviceSeriesID] = item.id

        self[.seriesName]        = item.title
        self[.seriesDescription] = item.description

        self[.serviceEpisodeID] = episode.id
        self[.name]             = episode.title
        self[.releaseDate]      = episode.formattedDate
        self[.longDescription]  = episode.episodeDescription

        self[.season]          = episode.seasonNumber
        self[.episodeID]       = String(format: "%d%02d", episode.seasonNumber , episode.episodeNumber)
        self[.episodeNumber]   = episode.episodeNumber
        self[.trackNumber]     = episode.episodeNumber

        if let ratingCode = episode.rating?.displayName {
            self[.rating] = Ratings.shared.rating(storeCode: store.storeCode, media: "TV", code: ratingCode)?.iTunesCode
        }

        self[.iTunesURL]       = episode.showURL
        self[.serviceSeriesID] = episode.showID

        if let releaseDate = item.releaseDate {
            self[.releaseDate] = Date(timeIntervalSince1970: releaseDate / 1000)
        }

        self.remoteArtworks = [item.images.coverArt16X9, item.images.coverArt].compactMap { $0?.artwork(type: .poster) }
        self.remoteArtworks += [episode.seasonImages.coverArt16X9, episode.seasonImages.coverArt].compactMap { $0?.artwork(type: .season) }
        self.remoteArtworks += [episode.images.previewFrame].compactMap { $0?.artwork(type: .episode) }
    }
}

public struct AppleTV: MetadataService {

    public var languages: [String] {
        get {
            return iTunesStore().languages
        }
    }

    public var languageType: LanguageType {
        get {
            return .custom
        }
    }

    public var defaultLanguage: String {
        return "USA (English)"
    }

    public var name: String {
        return "Apple TV"
    }

    private let searchURL = "https://tv.apple.com/api/uts/v2/uts/v2/search/incremental?"
    private let detailsURL = "https://tv.apple.com/api/uts/v2/view/product/"
    private let episodesURL = "https://tv.apple.com/api/uts/v2/view/show/"
    private let seasonsURL = "https://tv.apple.com/api/uts/v2/show/"
    private let options = "&utsk=0&caller=wta&v=36&pfm=web"

    private func normalize(_ term: String) -> String {
        return term.replacingOccurrences(of: " (Dubbed)", with: "")
            .replacingOccurrences(of: " (Subtitled)", with: "")
            .replacingOccurrences(of: " (Ex-tended Edition)", with: "")
    }

    enum MediaType {
        case movie
        case tvShow(season: Int?)

        var description: String {
            get {
                switch self {
                case .movie:
                    return "Movie"
                case .tvShow:
                    return "Show"
                }
            }
        }
    }

    // MARK: - TV Series search

    public func search(tvShow: String, language: String) -> [String] {
        guard let store = iTunesStore.Store(language: language) else { return [] }

        let items = search(term: tvShow, store: store)
        return items.compactMap { $0.title }
    }

    public func search(tvShow: String, language: String, season: Int?, episode: Int?) -> [MetadataResult] {
        guard let store = iTunesStore.Store(language: language) else { return [] }

        let tvShows = search(term: tvShow, store: store, type: .tvShow(season: nil))

        if let tvShow = tvShows.first {
            let seasons = fetchSeasons(id: tvShow.id, store: store)
            let seasonNumber = season ?? 1
            if seasons.count >= seasonNumber {
                let startIndex = seasons[0 ..< seasonNumber - 1].map { $0.episodeCount }.reduce(0, +)
                let length = seasons[seasonNumber - 1].episodeCount
                let episodes = fetchEpisodes(id: tvShow.id, store: store, range: (startIndex, length))
                    .filter { episode != nil ? $0.episodeNumber == episode : true }
                let results = episodes.map { MetadataResult(item: tvShow, episode: $0, store: store) }
                return results
            }
        }

        return []
    }

    public func loadTVMetadata(_ metadata: MetadataResult, language: String) -> MetadataResult {
        guard let store = iTunesStore.Store(language: language),
            let id = metadata[.serviceSeriesID] as? String,
            let details = fetchMovieDetails(id: id, store: store) else { return metadata }

        let content = details.content
        metadata[.seriesDescription]  = content.contentDescription
        metadata[.genre] = content.genres.map { $0.name }.joined(separator: ", ")
        metadata[.studio] = content.studio

        if metadata[.rating] == nil {
            metadata[.rating] = Ratings.shared.rating(storeCode: store.storeCode, media: "TV", code: content.rating.displayName)?.iTunesCode
        }
        metadata[.cast] = details.roles.filter { $0.type == "Actor" }.map { $0.personName }.joined(separator: ", ") +
                          details.roles.filter { $0.type == "Voice" }.map { $0.personName }.joined(separator: ", ")
        metadata[.screenwriters] = details.roles.filter { $0.type == "Writer" }.map { $0.personName }.joined(separator: ", ")
        metadata[.producers] = details.roles.filter { $0.type == "Producer" }.map { $0.personName }.joined(separator: ", ")
        metadata[.director] = details.roles.first { $0.type == "Director" }.map { $0.personName }
        metadata[.composer] = details.roles.first { $0.type == "Music" }.map { $0.personName }

        if let season = metadata[.season] as? Int {
            let index = metadata.remoteArtworks.count > 1 ? 1 : 0
            metadata.remoteArtworks.insert(contentsOf: searchSeasons(id: id, season: season, store: store), at: index)
        }

        return metadata
    }

    // MARK: - Movie search

    public func search(movie: String, language: String) -> [MetadataResult] {
        guard let store = iTunesStore.Store(language: language) else { return [] }

        let items = search(term: movie, store: store)
        let results = items.map { MetadataResult(item: $0, store: store) }
        return results
    }

    public func loadMovieMetadata(_ metadata: MetadataResult, language: String) -> MetadataResult {
        guard let store = iTunesStore.Store(language: language),
            let id = metadata[.serviceSeriesID] as? String,
            let details = fetchMovieDetails(id: id, store: store) else { return metadata }

        let content = details.content

        metadata[.genre] = content.genres.map { $0.name }.joined(separator: ", ")
        metadata[.studio] = content.studio

        metadata[.rating] = Ratings.shared.rating(storeCode: store.storeCode, media: "movie", code: content.rating.displayName)?.iTunesCode

        metadata[.cast] = details.roles.filter { $0.type == "Actor" }.map { $0.personName }.joined(separator: ", ")  +
                          details.roles.filter { $0.type == "Voice" }.map { $0.personName }.joined(separator: ", ")
        metadata[.screenwriters] = details.roles.filter { $0.type == "Writer" }.map { $0.personName }.joined(separator: ", ")
        metadata[.producers] = details.roles.filter { $0.type == "Producer" }.map { $0.personName }.joined(separator: ", ")
        metadata[.director] = details.roles.first { $0.type == "Director" }.map { $0.personName }
        metadata[.composer] = details.roles.first { $0.type == "Music" }.map { $0.personName }

        return metadata
    }

    // MARK: - Artworks search

    private func searchSeasons(id: String,  season: Int, store: iTunesStore.Store) -> [Artwork] {
        let urlString = "\(seasonsURL)\(id)/itunesSeasons?sf=\(store.storeCode)&locale=\(store.language2)\(options)"
        if let url = URL(string: urlString), let results = sendJSONRequest(url: url, type: Wrapper<Seasons>.self) {

            let filteredResults =  results.data.seasons.values.joined().filter { $0.seasonNumber == season }
            return filteredResults.compactMap { $0.images }.compactMap { $0.coverArt16X9 }.compactMap { $0.artwork(type: .season) }
        }
        return []
    }

    func searchArtwork(term: String, store: iTunesStore.Store, type: MediaType = .movie) -> [Artwork] {
        let normalizedTerm = normalize(term)

        if let url = URL(string: "\(searchURL)&sf=\(store.storeCode)&locale=\(store.language2)\(options)&q=\(normalizedTerm.urlEncoded())"),
            let results = sendJSONRequest(url: url, type: Wrapper<Results>.self) {

            let filteredResults = { () -> [Item] in
                let items = results.data.canvas?.shelves
                    .flatMap { $0.items }
                    .filter { $0.type == type.description }

                if let results = items?.filter({ $0.title == normalizedTerm }), results.isEmpty == false {
                    return results
                } else if let results = items {
                    return results
                } else {
                    return []
                }
            }()

            let artworks = filteredResults.compactMap { $0.images }.compactMap { $0.coverArt16X9 }.compactMap { $0.artwork(type: .poster) }

            if case let MediaType.tvShow(season) = type, let item = filteredResults.first {
                if let season = season {
                    return artworks + searchSeasons(id: item.id, season: season, store: store)
                }
            }

            return artworks
        }
        return []
    }

    // MARK: Model

    private func sendJSONRequest<T>(url: URL, type: T.Type) -> T? where T : Decodable {
        guard let data = URLSession.data(from: url) else { return nil }

        do {
            let result = try JSONDecoder().decode(type, from: data)
            return result
        } catch {
            print("error: \(error)")
        }

        return nil
    }

    private func search(term: String, store: iTunesStore.Store, type: MediaType = .movie) -> [Item] {
        if let url = URL(string: "\(searchURL)&sf=\(store.storeCode)&locale=\(store.language2)\(options)&q=\(term.urlEncoded())"),
            let results = sendJSONRequest(url: url, type: Wrapper<Results>.self) {

            let filteredItems = results.data.canvas?.shelves
                .flatMap { $0.items }
                .filter { $0.type == type.description }

            return filteredItems ?? []
        }
        return []
    }

    private func fetchMovieDetails(id: String, store: iTunesStore.Store) -> ShowDetails? {
        if let url = URL(string: "\(detailsURL)\(id)?&sf=\(store.storeCode)&locale=\(store.language2)\(options)"),
            let results = sendJSONRequest(url: url, type: Wrapper<ShowDetails>.self) {
            return results.data
        }
        return nil
    }

    private func fetchSeasons(id: String, store: iTunesStore.Store) -> [SeasonSummary]  {
        if let url = URL(string: "\(episodesURL)\(id)/episodes?sf=\(store.storeCode)&locale=\(store.language2)\(options)"),
            let results = sendJSONRequest(url: url, type: Wrapper<Episodes>.self) {
            return results.data.seasonSummaries ?? []
        }
        return []
    }

    private func fetchEpisodes(id: String, store: iTunesStore.Store, range: (start: Int, length: Int)) -> [Episode] {
        if let url = URL(string: "\(episodesURL)\(id)/episodes?skip=\(range.start)&count=\(range.length)&sf=\(store.storeCode)&locale=\(store.language2)\(options)"),
            let results = sendJSONRequest(url: url, type: Wrapper<Episodes>.self) {
            return results.data.episodes
        }
        return []
    }

    private struct Results: Codable {
        let q: String
        let canvas: Canvas?
    }

    private struct Wrapper<T>: Codable where T : Codable  {
        let data: T
    }

    fileprivate struct Image: Codable {
        let width: UInt
        let height: UInt
        let hasAlpha: Bool?
        let joeColor: String?
        let url: String

        var size: ArtworkSize {
            get {
                if width > height {
                    return .rectangle
                } else if width == height {
                    return .square
                } else {
                    return .standard
                }
            }
        }

        var thumbSize: String {
            get {
                switch size {
                case .square:
                    return "329x329.jpg"
                case .rectangle:
                    return "329x185.jpg"
                default:
                    return "185x329.jpg"
                }
            }
        }

        var fullSize: String {
            get {
                switch size {
                case .square:
                    return "800x800.jpg"
                case .rectangle:
                    return "800x450.jpg"
                default:
                    return "600x900.jpg"
                }
            }
        }

        func artwork(type: ArtworkType) -> Artwork? {
            let baseURL = url.replacingOccurrences(of: "{w}x{h}.{f}", with: "")
            if let artworkURL = URL(string: baseURL + fullSize), let thumbURL = URL(string: baseURL + thumbSize) {
                return Artwork(url: artworkURL, thumbURL: thumbURL, service: "Apple TV", type: type, size: size)
            } else {
                return nil
            }
        }
    }

    fileprivate struct Images: Codable {
        let bannerUberImage: Image?
        let contentLogo: Image?
        let coverArt: Image?
        let coverArt16X9: Image?
        let fullColorContentLogo: Image?
        let fullScreenBackground: Image?
        let previewFrame: Image?
        let keyframe: Image?
    }

    fileprivate struct Rating: Codable {
        let displayName: String
        let name: String
        let system: String
        let value: UInt
    }

    private struct Genre: Codable {
        let name, id, type: String
        let url: String
    }

    fileprivate struct Roles: Codable {
        let cast: [String]?
        let directors: [String]?
    }

    private struct Role: Codable {
        let type, roleTitle: String
        let characterName: String?
        let personName, personId: String
        let url: String
    }

    fileprivate struct Item: Codable {
        let commonSenseRecommendedAge: UInt?
        let contentAdvisories: [String]?
        let description: String?
        let duration: UInt?
        let id: String
        let images: Images
        let isEntitledToPlay: Bool?
        let rating: Rating?
        let releaseDate: TimeInterval?
        let rolesSummary: Roles?
        let title: String?
        let type: String
        let url: URL

        var formattedDate: String? {
            if let date = releaseDate {
                let date = Date(timeIntervalSince1970: date / 1000)
                return formatter.string(from: date)
            } else {
                return nil
            }
        }
    }

    private struct ItemCollection: Codable {
        let displayType: String?
        let id: String?
        let items: [Item]
        let title: String
        let url: String?
        let version: String?
    }

    private struct Canvas: Codable {
        let id: String
        let shelves: [ItemCollection]
    }

    // MARK: Movie specific

    private struct Content: Codable {
        let id: String
        let type: String
        let isEntitledToPlay: Bool?
        let title, contentDescription: String
        let releaseDate: TimeInterval?
        let genres: [Genre]
        let rating: Rating
        let contentAdvisories: [String]?
        let commonSenseRecommendedAge: Int?
        let images: Images
        let url: String
        let rolesSummary: Roles?
        let duration: Int?
        let version: String?
        let studio: String?

        enum CodingKeys: String, CodingKey {
            case id, type, isEntitledToPlay, title
            case contentDescription = "description"
            case releaseDate, genres, rating, contentAdvisories, commonSenseRecommendedAge, images, url, rolesSummary, duration, version, studio
        }
    }

    private struct ShowDetails: Codable {
        let content: Content
        let roles: [Role]
    }

    // MARK: Season specific

    private struct Season: Codable {
        let id, canonicalId, type, title: String
        let images: Images
        let url: String
        let adamId: String
        let seasonNumber: Int
        let showId, showTitle: String
        let showImages: Images
    }

    private struct Seasons: Codable {
        let seasons: [String: [Season]]
    }

    // MARK: Episode specific

    fileprivate struct Episode: Codable {
        let id: String
        let type: String
        let isEntitledToPlay: Bool
        let title, episodeDescription: String
        let releaseDate: TimeInterval?
        let ratingValue: Int?
        let ratingSystemType: String?
        let rating: Rating?
        let images: Images
        let url: String
        let duration: Int
        let seasonID: String
        let showID: String
        let showTitle: String
        let showImages: Images
        let seasonImages: Images
        let episodeNumber, seasonNumber: Int
        let seasonURL: String
        let showURL: String
        let episodeIndex: Int

        var formattedDate: String? {
            if let date = releaseDate {
                let date = Date(timeIntervalSince1970: date / 1000)
                return formatter.string(from: date)
            } else {
                return nil
            }
        }

        enum CodingKeys: String, CodingKey {
            case id, type, isEntitledToPlay, title
            case episodeDescription = "description"
            case releaseDate, ratingValue, ratingSystemType, rating, images, url, duration
            case seasonID = "seasonId"
            case showID = "showId"
            case showTitle, showImages, seasonImages, episodeNumber, seasonNumber
            case seasonURL = "seasonUrl"
            case showURL = "showUrl"
            case episodeIndex
        }
    }

    private struct SeasonSummary: Codable {
        let label: String
        let episodeCount: Int
    }

    private struct Episodes: Codable {
        let episodes: [Episode]
        let seasonSummaries: [SeasonSummary]?
    }

}
