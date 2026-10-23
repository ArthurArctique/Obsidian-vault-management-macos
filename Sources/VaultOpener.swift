import Cocoa

/// Ouvre un vault dans Obsidian, en l'ajoutant d'abord à la liste d'Obsidian s'il n'y est pas, et le ferme.
///
/// Les erreurs et les questions (fermer Obsidian, autoriser l'accessibilité) s'affichent en bandeau dans
/// le panneau, par `present`.
@MainActor
final class VaultOpener {
    private let registry: ObsidianRegistry
    /// Temps laissé à Obsidian pour se fermer avant d'abandonner.
    private let quitTimeout: TimeInterval = 20

    var present: (Banner) -> Void = { _ in }
    /// Appelé quand le lien est envoyé à Obsidian : le panneau peut se refermer.
    var didLaunch: () -> Void = {}
    /// Appelé quand des vaults ont pu s'ouvrir ou se fermer : le panneau relit `openVaultPaths()`.
    var openVaultsChanged: () -> Void = {}

    init(registry: ObsidianRegistry) {
        self.registry = registry
    }

    /// Le dossier du vault doit exister : c'est à l'appelant de le vérifier.
    func open(_ vault: Vault) {
        guard NSWorkspace.shared.urlForApplication(toOpen: ObsidianRegistry.openURL(vaultID: "x")) != nil else {
            present(Banner(.error, "Obsidian est introuvable",
                           "Aucune application ne sait ouvrir les liens obsidian://. Installe Obsidian, puis réessaie."))
            return
        }

        let knownID: String?
        do {
            knownID = try registry.vaultID(forPath: vault.path)
        } catch {
            present(Banner(error: error, title: "Impossible d'ouvrir « \(vault.name) »"))
            return
        }
        if let knownID {
            launch(vaultID: knownID, name: vault.name)
            return
        }

        // Vault inconnu d'Obsidian : on l'inscrit dans sa liste, ce qui ne marche qu'Obsidian fermé.
        guard isObsidianRunning else {
            registerAndLaunch(vault)
            return
        }
        present(Banner(.question, "Fermer Obsidian pour ajouter « \(vault.name) » ?",
                       "Obsidian ne connaît pas encore ce dossier. Pour l'ajouter à sa liste, il doit se fermer "
                           + "quelques secondes ; il se rouvrira aussitôt sur ce vault.",
                       actions: [BannerAction("Fermer et ouvrir", systemImage: "arrow.clockwise") { [weak self] in
                           self?.quitThenOpen(vault)
                       }]))
    }

    private func quitThenOpen(_ vault: Vault) {
        present(Banner(.progress, "Fermeture d'Obsidian…"))
        Task { @MainActor in
            guard await quitObsidian() else {
                present(Banner(.warning, "Obsidian ne s'est pas fermé",
                               "Ferme Obsidian toi-même (⌘Q), puis rouvre « \(vault.name) »."))
                return
            }
            registerAndLaunch(vault)
        }
    }

    // MARK: - Fermeture

    /// Chemins, sous la forme de `ObsidianRegistry.normalizedPath`, des vaults ouverts dans Obsidian.
    func openVaultPaths() -> Set<String> {
        // Obsidian lancé sans fenêtre garde le dernier vault fermé marqué ouvert : il n'est pas ouvert pour autant.
        guard let obsidian = runningObsidian.first,
              ObsidianWindows.hasWindows(pid: obsidian.processIdentifier) else { return [] }
        return (try? registry.openVaultPaths()) ?? []
    }

    /// Ferme les fenêtres du vault. Sans l'accès « Accessibilité », Obsidian doit quitter pour le fermer :
    /// directement si c'est le seul vault ouvert, sinon après avoir demandé quoi faire.
    func close(_ vault: Vault) {
        guard let obsidian = runningObsidian.first else {
            openVaultsChanged()
            return
        }
        let others = openVaultPaths().subtracting([ObsidianRegistry.normalizedPath(vault.path)])
        if ObsidianWindows.isAccessibilityTrusted {
            closeWindows(of: vault, otherOpenPaths: others, pid: obsidian.processIdentifier, bringForward: true)
        } else if others.isEmpty {
            quitClosing(vault, reopenOthers: false)
        } else {
            present(Banner(.question, "Fermer « \(vault.name) » ?",
                           "Pour fermer une seule fenêtre d'Obsidian, ObsiVaults a besoin de l'accès "
                               + "« Accessibilité » de macOS. Sans lui, Obsidian peut redémarrer sans ce vault : "
                               + "les autres se rouvriront.",
                           actions: [BannerAction("Autoriser l'accès", systemImage: "hand.raised.fill") { [weak self] in
                                         self?.requestAccessibility()
                                     },
                                     BannerAction("Redémarrer Obsidian", systemImage: "arrow.clockwise") { [weak self] in
                                         self?.quitClosing(vault, reopenOthers: true)
                                     }]))
        }
    }

    private func closeWindows(of vault: Vault, otherOpenPaths: Set<String>, pid: pid_t, bringForward: Bool) {
        let name = URL(fileURLWithPath: vault.path).lastPathComponent
        let otherNames = otherOpenPaths.map { URL(fileURLWithPath: $0).lastPathComponent }
        switch ObsidianWindows.closeWindows(ofVaultNamed: name, otherOpenNames: otherNames, pid: pid) {
        case .closed:
            // Obsidian met sa liste à jour juste après la fermeture de la fenêtre.
            for delay in [0.4, 1.5] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.openVaultsChanged() }
            }
        case .ambiguous:
            present(Banner(.warning, "Deux vaults ouverts s'appellent « \(name) »",
                           "Leurs fenêtres portent le même titre : ObsiVaults ne sait pas laquelle fermer. Ferme-la "
                               + "dans Obsidian, ou redémarre Obsidian sans « \(vault.name) ».",
                           actions: [restartAction(vault)]))
        case .notFound:
            // L'accessibilité ne voit que le bureau actuel : Obsidian amène d'abord la fenêtre du vault ici.
            if bringForward, let id = try? registry.vaultID(forPath: vault.path) {
                NSWorkspace.shared.open(ObsidianRegistry.openURL(vaultID: id))
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 900_000_000)
                    closeWindows(of: vault, otherOpenPaths: otherOpenPaths, pid: pid, bringForward: false)
                }
            } else {
                present(Banner(.warning, "Fenêtre de « \(vault.name) » introuvable",
                               "Obsidian ne montre aucune fenêtre de ce vault. Ferme-la dans Obsidian, ou "
                                   + "redémarre Obsidian sans lui.",
                               actions: [restartAction(vault, reopenOthers: !otherOpenPaths.isEmpty)]))
            }
        }
    }

    private func restartAction(_ vault: Vault, reopenOthers: Bool = true) -> BannerAction {
        BannerAction(reopenOthers ? "Redémarrer Obsidian" : "Quitter Obsidian",
                     systemImage: reopenOthers ? "arrow.clockwise" : "power") { [weak self] in
            self?.quitClosing(vault, reopenOthers: reopenOthers)
        }
    }

    private func requestAccessibility() {
        present(Banner(.warning, "Autorise ObsiVaults dans « Accessibilité »",
                       "Réglages Système › Confidentialité et sécurité › Accessibilité : active ObsiVaults, "
                           + "puis clique de nouveau sur la croix.",
                       actions: [BannerAction("Ouvrir les Réglages", systemImage: "gearshape") {
                           ObsidianWindows.openAccessibilitySettings()
                       }],
                       isResolved: { ObsidianWindows.isAccessibilityTrusted }))
        ObsidianWindows.requestAccessibility()
    }

    /// Quitte Obsidian et retire au vault son drapeau « ouvert », pour qu'il ne revienne pas au prochain
    /// lancement. Avec `reopenOthers`, Obsidian est relancé en arrière-plan et rouvre les autres vaults.
    private func quitClosing(_ vault: Vault, reopenOthers: Bool) {
        present(Banner(.progress, reopenOthers ? "Redémarrage d'Obsidian…" : "Fermeture d'Obsidian…"))
        Task { @MainActor in
            defer { openVaultsChanged() }
            guard await quitObsidian() else {
                present(Banner(.warning, "Obsidian ne s'est pas fermé",
                               "Ferme toi-même la fenêtre de « \(vault.name) » dans Obsidian."))
                return
            }
            do {
                try registry.markClosed(path: vault.path)
            } catch {
                present(Banner(error: error, title: "Obsidian rouvrira « \(vault.name) » à son prochain lancement"))
                return
            }
            guard reopenOthers else {
                present(Banner(.success, "« \(vault.name) » est fermé",
                               "C'était le seul vault ouvert : Obsidian a quitté."))
                return
            }
            guard await relaunchObsidian() else {
                present(Banner(.warning, "« \(vault.name) » est fermé, mais Obsidian ne s'est pas relancé",
                               "Rouvre Obsidian : il retrouvera les autres vaults."))
                return
            }
            present(Banner(.success, "« \(vault.name) » est fermé", "Obsidian a rouvert les autres vaults."))
        }
    }

    /// Relance Obsidian sans le passer au premier plan, pour que le panneau reste ouvert.
    private func relaunchObsidian() async -> Bool {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: ObsidianRegistry.bundleIdentifier)
        else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        return await withCheckedContinuation { continuation in
            NSWorkspace.shared.openApplication(at: app, configuration: configuration) { _, error in
                continuation.resume(returning: error == nil)
            }
        }
    }

    // MARK: - Obsidian

    private var runningObsidian: [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: ObsidianRegistry.bundleIdentifier)
            .filter { !$0.isTerminated }
    }

    private var isObsidianRunning: Bool { !runningObsidian.isEmpty }

    private func quitObsidian() async -> Bool {
        runningObsidian.forEach { $0.terminate() }
        let deadline = Date().addingTimeInterval(quitTimeout)
        while isObsidianRunning && Date() < deadline {
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        return !isObsidianRunning
    }

    private func registerAndLaunch(_ vault: Vault) {
        do {
            let id = try registry.register(path: vault.path)
            launch(vaultID: id, name: vault.name)
        } catch {
            present(Banner(error: error, title: "Impossible d'ajouter « \(vault.name) » à Obsidian"))
        }
    }

    private func launch(vaultID: String, name: String) {
        let url = ObsidianRegistry.openURL(vaultID: vaultID)
        NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            guard let error else { return }
            Task { @MainActor [weak self] in
                self?.present(Banner(error: error, title: "Impossible d'ouvrir « \(name) »"))
            }
        }
        didLaunch()
    }
}
