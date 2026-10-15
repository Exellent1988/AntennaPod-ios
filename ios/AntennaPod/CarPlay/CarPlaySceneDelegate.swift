import CarPlay
import Combine
import UIKit

/// CarPlay audio app mirroring the Android Auto browse tree (`PlaybackService.loadChildrenSynchronous`):
/// Queue (with a "Currently playing" section), Downloads, Episodes, Subscriptions → podcast episodes.
/// Lists update live (debounced) and show artwork, progress, and the playing indicator.
/// Requires the `com.apple.developer.carplay-audio` entitlement (Apple-granted) to appear in CarPlay.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate, CPNowPlayingTemplateObserver {
    private var interfaceController: CPInterfaceController?
    private var tabs: [CarPlayTab: CPListTemplate] = [:]
    private var episodeLists: [(feedId: UUID, template: CPListTemplate)] = []
    /// Pushed Now Playing → Up Next list (live-refreshed while on the stack).
    private var upNextTemplate: CPListTemplate?
    private var rendered: [ObjectIdentifier: [[CarPlayRow]]] = [:]
    private var cancellables = Set<AnyCancellable>()

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        Task { @MainActor in
            AppServices.isCarPlayConnected = true
            var ordered: [CPListTemplate] = []
            for tab in CarPlayTab.allCases {
                let t = self.makeTemplate(tab)
                self.tabs[tab] = t
                ordered.append(t)
            }
            self.reloadAll()
            self.configureNowPlaying()
            interfaceController.setRootTemplate(CPTabBarTemplate(templates: ordered), animated: false, completion: nil)
            self.observeStores()
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        cancellables.removeAll()
        Task { @MainActor in AppServices.isCarPlayConnected = false }
        CPNowPlayingTemplate.shared.remove(self)
        episodeLists.removeAll()
        upNextTemplate = nil
        rendered.removeAll()
        tabs.removeAll()
        self.interfaceController = nil
    }

    // MARK: Live refresh

    @MainActor private func observeStores() {
        var signals: [AnyPublisher<Void, Never>] = []
        if let store = AppServices.store {
            signals.append(store.$feeds.map { _ in () }.eraseToAnyPublisher())
            signals.append(store.$feedSettingsById.map { _ in () }.eraseToAnyPublisher())
            signals.append(store.$queue.map { _ in () }.eraseToAnyPublisher())
            signals.append(store.$playbackStates.map { _ in () }.eraseToAnyPublisher())
            signals.append(store.$favoriteAtById.map { _ in () }.eraseToAnyPublisher())
            signals.append(store.$archivedAtById.map { _ in () }.eraseToAnyPublisher())
        }
        if let dl = AppServices.downloads {
            signals.append(dl.$downloads.map { _ in () }.eraseToAnyPublisher())
        }
        if let pb = AppServices.playback {
            signals.append(pb.$currentEpisode.map { $0?.id }.removeDuplicates().map { _ in () }.eraseToAnyPublisher())
        }
        if let settings = AppServices.settings {
            signals.append(settings.objectWillChange.map { _ in () }.eraseToAnyPublisher())
        }
        Publishers.MergeMany(signals)
            .debounce(for: .milliseconds(CarPlayBrowseModel.refreshDebounceMs), scheduler: RunLoop.main)
            .sink { [weak self] in MainActor.assumeIsolated { self?.reloadAll() } }
            .store(in: &cancellables)
    }

    @MainActor private var limit: Int { CarPlayParity.itemLimit(templateMax: Int(CPListTemplate.maximumItemCount)) }

    @MainActor private func builder() -> CarPlayListBuilder? {
        guard let store = AppServices.store else { return nil }
        return CarPlayListBuilder(store: store, downloads: AppServices.downloads, settings: AppServices.settings,
                                  currentEpisode: AppServices.playback?.currentEpisode, limit: limit)
    }

    @MainActor private func reloadAll() {
        guard let b = builder() else { return }
        let all = b.allEpisodeInfos()
        if let t = tabs[.queue] { apply(b.queueSections(), to: t) }
        if let t = tabs[.downloads] { apply([(nil, b.downloadRows(all))], to: t) }
        if let t = tabs[.episodes] { apply([(nil, b.episodeRows(all))], to: t) }
        if let t = tabs[.subscriptions] { apply([(nil, b.subscriptionRows())], to: t) }
        let stack = interfaceController?.templates ?? []
        episodeLists.removeAll { entry in !stack.contains { $0 === entry.template } }
        for entry in episodeLists { apply([(nil, b.feedEpisodeRows(entry.feedId))], to: entry.template) }
        if let t = upNextTemplate {
            if stack.contains(where: { $0 === t }) { apply([(nil, b.upNextRows())], to: t) } else { upNextTemplate = nil }
        }
    }

    @MainActor private func apply(_ sections: [(String?, [CarPlayRow])], to template: CPListTemplate) {
        let key = ObjectIdentifier(template)
        let playingId = AppServices.playback?.currentEpisode?.id
        // Fold the playing marker into rows so indicator changes trigger an update.
        let marked = sections.map { $0.1.map { r -> CarPlayRow in
            var r = r
            if case .episode(let id) = r.target, id == playingId { r.detail = "▶︎" + (r.detail ?? "") }
            return r
        } }
        guard rendered[key] != marked else { return }
        rendered[key] = marked
        CarPlayArtworkLoader.shared.prefetch(CarPlayBrowseModel.uniqueArtworkURLs(sections.flatMap(\.1)))
        template.updateSections(sections.map { header, rows in
            CPListSection(items: rows.map { listItem($0, playingId: playingId) }, header: header, sectionIndexTitle: nil)
        })
    }

    // MARK: Templates

    @MainActor private func makeTemplate(_ tab: CarPlayTab) -> CPListTemplate {
        let spec: (String, String, String)
        switch tab {
        case .queue: spec = (String(localized: "Queue"), "list.bullet", String(localized: "Queue is empty"))
        case .downloads: spec = (String(localized: "Downloads"), "arrow.down.circle", String(localized: "No downloads"))
        case .episodes: spec = (String(localized: "Episodes"), "dot.radiowaves.up.forward", String(localized: "No episodes"))
        case .subscriptions: spec = (String(localized: "Subscriptions"), "square.stack", String(localized: "No subscriptions"))
        }
        let (title, icon, empty) = spec
        let t = CPListTemplate(title: title, sections: [])
        t.tabImage = UIImage(systemName: icon)
        t.emptyViewTitleVariants = [empty]
        return t
    }

    @MainActor private func pushEpisodes(feedId: UUID) {
        let store = AppServices.store
        let title = store?.displayTitle(forFeedId: feedId) ?? ""
        let t = CPListTemplate(title: title, sections: [])
        t.emptyViewTitleVariants = [String(localized: "No episodes")]
        apply([(nil, builder()?.feedEpisodeRows(feedId) ?? [])], to: t)
        episodeLists.append((feedId, t))
        interfaceController?.pushTemplate(t, animated: true, completion: nil)
    }

    @MainActor private func listItem(_ row: CarPlayRow, playingId: String?) -> CPListItem {
        let loader = CarPlayArtworkLoader.shared
        let cachedImage = row.imageUrl.flatMap { loader.cached($0) }
        let item = CPListItem(text: row.title, detailText: row.detail, image: cachedImage ?? CarPlayArtworkLoader.placeholder)
        if cachedImage == nil, let url = row.imageUrl {
            Task { @MainActor [weak item] in
                if let img = await loader.image(for: url) { item?.setImage(img) }
            }
        }
        switch row.target {
        case .feed(let id):
            item.accessoryType = .disclosureIndicator
            item.handler = { [weak self] _, completion in
                Task { @MainActor in
                    self?.pushEpisodes(feedId: id)
                    completion()
                }
            }
        case .episode(let id):
            item.isPlaying = (id == playingId)
            item.playingIndicatorLocation = .trailing
            item.playbackProgress = CGFloat(row.progress)
            item.handler = { [weak self] _, completion in
                Task { @MainActor in
                    self?.play(episodeId: id, feedId: row.feedId)
                    completion()
                }
            }
        }
        return item
    }

    // MARK: Now Playing

    /// Rate button (cycles Settings speed presets, like the app's speed chip) and Up Next → Queue.
    /// Skip ± buttons come from MPRemoteCommandCenter skip commands (Settings intervals).
    @MainActor private func configureNowPlaying() {
        let np = CPNowPlayingTemplate.shared
        np.add(self)
        np.isUpNextButtonEnabled = true
        np.upNextTitle = String(localized: "Up Next")
        np.isAlbumArtistButtonEnabled = false
        refreshNowPlayingButtons()
        // Rebuild when the episode (chapters) or sleep-timer state changes.
        if let pb = AppServices.playback {
            pb.$currentEpisode.map { $0?.id }.removeDuplicates().map { _ in () }
                .merge(with: pb.$isSleepTimerActive.removeDuplicates().map { _ in () })
                .receive(on: RunLoop.main)
                .sink { [weak self] in MainActor.assumeIsolated { self?.refreshNowPlayingButtons() } }
                .store(in: &cancellables)
        }
    }

    /// Android Auto custom actions: speed, sleep timer, next chapter (with chapters), skip episode.
    @MainActor private func refreshNowPlayingButtons() {
        let pb = AppServices.playback
        let kinds = NowPlayingLogic.nowPlayingButtons(hasChapters: pb?.hasChaptersForRemote ?? false)
        let buttons: [CPNowPlayingButton] = kinds.compactMap { kind in
            switch kind {
            case .rate:
                return CPNowPlayingPlaybackRateButton { _ in
                    Task { @MainActor in AppServices.playback?.cycleToNextSpeedPreset() }
                }
            case .sleepTimer:
                let active = pb?.isSleepTimerActive ?? false
                guard let img = UIImage(systemName: active ? "moon.zzz.fill" : "moon.zzz") else { return nil }
                let b = CPNowPlayingImageButton(image: img) { _ in
                    Task { @MainActor in
                        guard let pb = AppServices.playback else { return }
                        if pb.isSleepTimerActive {
                            pb.disableSleepTimer()
                        } else {
                            pb.setSleepTimer(minutes: NowPlayingLogic.sleepToggleMinutes(presets: PlaybackService.clockPresetsMinutes))
                        }
                    }
                }
                b.isSelected = active
                return b
            case .nextChapter:
                guard let img = UIImage(systemName: "text.line.first.and.arrowtriangle.forward") else { return nil }
                return CPNowPlayingImageButton(image: img) { _ in
                    Task { @MainActor in AppServices.playback?.skipToNextChapter() }
                }
            case .skipEpisode:
                guard let img = UIImage(systemName: "forward.end.fill") else { return nil }
                return CPNowPlayingImageButton(image: img) { _ in
                    Task { @MainActor in AppServices.playback?.skipToNextEpisode() }
                }
            }
        }
        CPNowPlayingTemplate.shared.updateNowPlayingButtons(buttons)
    }

    func nowPlayingTemplateUpNextButtonTapped(_ nowPlayingTemplate: CPNowPlayingTemplate) {
        Task { @MainActor in
            guard AppServices.store != nil else { return }
            let t = CPListTemplate(title: String(localized: "Up Next"), sections: [])
            t.emptyViewTitleVariants = [String(localized: "Queue is empty")]
            let rows = self.builder()?.upNextRows() ?? []
            self.apply([(nil, rows)], to: t)
            self.upNextTemplate = t
            self.interfaceController?.pushTemplate(t, animated: true, completion: nil)
        }
    }

    func nowPlayingTemplateAlbumArtistButtonTapped(_ nowPlayingTemplate: CPNowPlayingTemplate) {}

    // MARK: Playback

    @MainActor private func play(episodeId: String, feedId: UUID?) {
        guard let playback = AppServices.playback, let episode = builder()?.episodeToPlay(id: episodeId, feedId: feedId)
        else { return }
        let fileURL = AppServices.downloads?.localURL(for: episode)
        guard playback.play(episode: episode, fileURL: fileURL) else { return }
        // System Now Playing is already fed by PlaybackService (MPNowPlayingInfoCenter + remotes).
        let nowPlaying = CPNowPlayingTemplate.shared
        if interfaceController?.topTemplate !== nowPlaying {
            interfaceController?.pushTemplate(nowPlaying, animated: true, completion: nil)
        }
    }
}
