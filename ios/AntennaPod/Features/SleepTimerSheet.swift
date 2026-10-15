import PodcastCore
import SwiftUI

/// Android `SleepTimerDialog` as a bottom sheet: minutes entry + presets, End of episode /
/// chapter / queue, the running timer with +5 / +10 / +30 min extend buttons and Turn off,
/// and the timer options (Shake to reset, Vibrate, Auto-enable with from/to hours, Fade).
struct SleepTimerSheet: View {
    @EnvironmentObject private var playback: PlaybackService
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: PodcastStore
    @Environment(\.dismiss) private var dismiss
    @State private var minutesText = ""
    @State private var kind: SleepTimerKind = .clock
    @State private var episodes = 1

    private var range: ClosedRange<Int> { PlaybackService.customSleepTimerMinutesRange }
    private var parsedMinutes: Int? {
        guard let m = Int(minutesText.trimmingCharacters(in: .whitespaces)), range.contains(m) else { return nil }
        return m
    }

    var body: some View {
        NavigationStack {
            Form {
                if playback.isSleepTimerActive {
                    activeSection
                } else {
                    startSection
                }
                optionsSection
            }
            .navigationTitle(String(localized: "Sleep timer"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
            .onAppear {
                minutesText = String(settings.lastSleepTimerMinutes)
                episodes = settings.lastSleepTimerEpisodes
                kind = settings.sleepTimerKind
            }
        }
        .presentationDetents([.large])
    }

    // MARK: Running timer

    private var activeSection: some View {
        Section {
            HStack {
                Image(systemName: "moon.zzz.fill").foregroundStyle(.tint)
                Text(activeTitle).font(.title2.monospacedDigit().weight(.semibold))
                Spacer()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(playback.sleepTimerAccessibilityLabel)
            if playback.sleepTimerWasAutoEnabled {
                Text(String(localized: "Turned on automatically (Auto-enable)."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if playback.sleepTimerMode == .episodes {
                HStack(spacing: 8) {
                    ForEach(EpisodeSleepCounter.extendSteps, id: \.self) { count in
                        Button(String(format: String(localized: "+%lld ep."), count)) {
                            playback.extendSleepTimer(byEpisodes: count)
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(String(format: String(localized: "Extend by %lld episodes"), count))
                    }
                }
            }
            HStack(spacing: 8) {
                ForEach(SleepTimerLogic.extendMinutes, id: \.self) { minutes in
                    Button(String(format: String(localized: "+%lld min"), minutes)) {
                        playback.extendSleepTimer(byMinutes: minutes)
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(String(format: String(localized: "Extend by %lld minutes"), minutes))
                }
            }
            Button(playback.sleepTimerWasAutoEnabled ? String(localized: "Undo") : String(localized: "Turn off"),
                   role: .destructive) {
                playback.disableSleepTimer()
            }
        } header: {
            Text(String(localized: "Timer active"))
        }
    }

    private var activeTitle: String {
        switch playback.sleepTimerMode {
        case .endOfEpisode: return String(localized: "End of episode")
        case .endOfChapter: return String(localized: "End of chapter")
        case .endOfQueue: return String(localized: "End of queue")
        case .episodes:
            let left = playback.sleepTimerEpisodeCounter?.remaining ?? 0
            return left == 1 ? String(localized: "Last episode")
                : String(format: String(localized: "%lld episodes left"), left)
        default: return playback.sleepTimerStatusLabel ?? String(localized: "Sleep timer")
        }
    }

    // MARK: Start

    private var startSection: some View {
        Section {
            Picker(String(localized: "Timer type"), selection: $kind) {
                Text(String(localized: "Minutes")).tag(SleepTimerKind.clock)
                Text(String(localized: "Episodes")).tag(SleepTimerKind.episodes)
            }
            .pickerStyle(.segmented)
            .onChange(of: kind) { _, newKind in settings.sleepTimerKind = newKind }
            if kind == .episodes {
                episodesStartRows
            } else {
                clockStartRows
            }
            if let hint = playback.sleepTimerHint(kind: kind, episodes: episodes, minutes: parsedMinutes) {
                Text(PlaybackService.sleepTimerHintText(hint))
                    .font(.caption).foregroundStyle(.orange)
                    .accessibilityIdentifier("sleepTimerHint")
            }
            Button(String(localized: "End of episode")) { playback.setSleepTimerEndOfEpisode(); dismiss() }
            Button(String(localized: "End of chapter")) { playback.setSleepTimerEndOfChapter(); dismiss() }
                .disabled(!playback.canSetSleepTimerEndOfChapter)
            Button(String(localized: "End of queue")) { playback.setSleepTimerEndOfQueue(); dismiss() }
                .disabled(!canEndOfQueue)
        } header: {
            Text(String(localized: "Set sleep timer"))
        }
    }

    /// Android episode type: stop after N episodes (ended, Skip ending or skipped).
    @ViewBuilder private var episodesStartRows: some View {
        HStack {
            Stepper(value: $episodes, in: EpisodeSleepCounter.range) {
                Text(episodes == 1 ? String(localized: "1 episode")
                     : String(format: String(localized: "%lld episodes"), episodes))
                    .monospacedDigit()
            }
            .accessibilityHint(String(localized: "Playback stops after this many episodes have finished or been skipped."))
            .disabled(!canStartEpisodes)
            Button(String(localized: "Start")) { playback.setSleepTimer(episodes: episodes); dismiss() }
                .buttonStyle(.borderedProminent)
                .disabled(!canStartEpisodes)
        }
        if canStartEpisodes {
            Text(String(localized: "Keeps playing the next episode (continuous playback) and stops after the last one."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var clockStartRows: some View {
            HStack {
                TextField(String(localized: "Minutes"), text: $minutesText)
                    .keyboardType(.numberPad)
                    .frame(maxWidth: 80)
                    .accessibilityLabel(String(localized: "Minutes"))
                Text(String(localized: "min")).foregroundStyle(.secondary)
                Spacer()
                Button(String(localized: "Start")) {
                    if let parsedMinutes { playback.setSleepTimer(minutes: parsedMinutes); dismiss() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(parsedMinutes == nil)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PlaybackService.clockPresetsMinutes, id: \.self) { minutes in
                        Button(String(format: String(localized: "%lld min"), minutes)) {
                            playback.setSleepTimer(minutes: minutes)
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
    }

    /// Android: no episode timer while continuous playback is off (End of episode instead).
    private var canStartEpisodes: Bool {
        SleepTimerHints.canStart(kind: .episodes, continuousPlayback: playback.sleepTimerContinuousPlayback)
    }

    private var canEndOfQueue: Bool {
        guard let id = playback.currentEpisode?.id else { return false }
        return store.nextQueueEpisode(after: id) != nil
    }

    // MARK: Options (global settings, same as Settings → Playback → Sleep timer)

    private var optionsSection: some View {
        Section {
            if SleepTimerHints.showsOptions(kind: kind, continuousPlayback: playback.sleepTimerContinuousPlayback) {
                SleepTimerOptionRows()
            }
        } header: {
            Text(String(localized: "Options"))
        }
    }
}

/// Sleep timer options shared by the timer sheet and Settings (all global, like Android).
struct SleepTimerOptionRows: View {
    @EnvironmentObject private var settings: AppSettings
    /// Settings already shows the fade toggle with its own caption.
    var includeFade = true
    @State private var confirmAlwaysEpisodes = false

    var body: some View {
        if SleepTimerHints.showsShakeToReset(kind: settings.sleepTimerKind) {
            Toggle(String(localized: "Shake to reset"), isOn: $settings.sleepTimerShakeToReset)
                .accessibilityHint(String(localized: "During the last 10 seconds, shaking the phone restarts the timer."))
        }
        Toggle(String(localized: "Vibrate before the end"), isOn: $settings.sleepTimerVibrate)
            .accessibilityHint(String(localized: "Vibrates once about 10 seconds before the timer ends."))
        if includeFade {
            Toggle(String(localized: "Sleep timer volume fade"), isOn: $settings.sleepTimerFadeEnabled)
        }
        Toggle(String(localized: "Auto-enable"), isOn: $settings.sleepTimerAutoEnable)
            .accessibilityHint(String(localized: "Starts the last used timer when playback starts within the chosen hours."))
        if settings.sleepTimerAutoEnable {
            Picker(String(localized: "From"), selection: $settings.sleepTimerAutoEnableFromHour) {
                ForEach(0..<24, id: \.self) { Text(Self.hourLabel($0)).tag($0) }
            }
            Picker(String(localized: "To"), selection: $settings.sleepTimerAutoEnableToHour) {
                ForEach(0..<24, id: \.self) { Text(Self.hourLabel($0)).tag($0) }
            }
            Text(autoEnableSummary).font(.caption).foregroundStyle(.secondary)
        }
        Color.clear.frame(height: 0)
            .onChange(of: settings.sleepTimerAutoEnable) { _, _ in checkAlwaysEpisodes() }
            .onChange(of: settings.sleepTimerAutoEnableFromHour) { _, _ in checkAlwaysEpisodes() }
            .onChange(of: settings.sleepTimerAutoEnableToHour) { _, _ in checkAlwaysEpisodes() }
            .alert(String(localized: "Disable continuous playback"), isPresented: $confirmAlwaysEpisodes) {
                Button(String(localized: "Disable continuous playback"), role: .destructive) {
                    settings.continuousPlaybackMode = .off
                    settings.sleepTimerAutoEnable = false
                }
                Button(String(localized: "Change hours")) {}
                Button(String(localized: "Cancel"), role: .cancel) { settings.sleepTimerAutoEnable = false }
            } message: {
                Text(String(localized: "Instead of always automatically enabling the sleep timer with one episode, please instead disable \"continuous playback\" in the settings."))
            }
    }

    /// Android `confirmAlwaysSleepTimerDialog`: an episode timer auto-enabled for most of the day.
    private func checkAlwaysEpisodes() {
        if SleepTimerHints.needsAlwaysEpisodeConfirmation(
            autoEnable: settings.sleepTimerAutoEnable, kind: settings.sleepTimerKind,
            fromHour: settings.sleepTimerAutoEnableFromHour, toHour: settings.sleepTimerAutoEnableToHour) {
            confirmAlwaysEpisodes = true
        }
    }

    private var autoEnableSummary: String {
        let from = settings.sleepTimerAutoEnableFromHour, to = settings.sleepTimerAutoEnableToHour
        if settings.sleepTimerKind == .episodes {
            if from == to {
                return String(format: String(localized: "Starts a %lld-episode timer whenever playback starts."),
                              settings.lastSleepTimerEpisodes)
            }
            return String(format: String(localized: "Starts a %lld-episode timer when playback starts between %@ and %@."),
                          settings.lastSleepTimerEpisodes, Self.hourLabel(from), Self.hourLabel(to))
        }
        if from == to {
            return String(format: String(localized: "Starts a %lld-minute timer whenever playback starts."),
                          settings.lastSleepTimerMinutes)
        }
        return String(format: String(localized: "Starts a %lld-minute timer when playback starts between %@ and %@."),
                      settings.lastSleepTimerMinutes, Self.hourLabel(from), Self.hourLabel(to))
    }

    static func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}
