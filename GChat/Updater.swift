import Combine
import Sparkle

/// Automatic updates with Sparkle. The app reads the appcast of its
/// organization's build, and installs a newer release after Sparkle has made
/// sure that it is genuine (docs/design.md).
@MainActor
@Observable
final class Updater {
    /// Nil when the build has no appcast address or no Sparkle key, and in
    /// development builds. A development build has version 1, so every
    /// release looks newer.
    private let controller: SPUStandardUpdaterController?
    private var observers: Set<AnyCancellable> = []

    /// False while a check is in progress, and when there is no updater.
    private(set) var canCheckForUpdates = false

    var checksAutomatically = false {
        didSet {
            guard let updater = controller?.updater, updater.automaticallyChecksForUpdates != checksAutomatically
            else { return }
            updater.automaticallyChecksForUpdates = checksAutomatically
        }
    }

    var downloadsAutomatically = false {
        didSet {
            guard let updater = controller?.updater, updater.automaticallyDownloadsUpdates != downloadsAutomatically
            else { return }
            updater.automaticallyDownloadsUpdates = downloadsAutomatically
        }
    }

    var isAvailable: Bool { controller != nil }

    init() {
        #if DEBUG
        controller = nil
        #else
        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        controller = feed.isEmpty || key.isEmpty
            ? nil
            : SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        #endif
        guard let updater = controller?.updater else { return }

        // Sparkle keeps these values, and its own windows can change them.
        updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
            .store(in: &observers)
        updater.publisher(for: \.automaticallyChecksForUpdates)
            .sink { [weak self] in self?.checksAutomatically = $0 }
            .store(in: &observers)
        updater.publisher(for: \.automaticallyDownloadsUpdates)
            .sink { [weak self] in self?.downloadsAutomatically = $0 }
            .store(in: &observers)
    }

    func checkForUpdates() {
        controller?.updater.checkForUpdates()
    }
}
