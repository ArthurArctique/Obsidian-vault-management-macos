import Cocoa

/// Ouvre un vault dans Obsidian, en l'ajoutant d'abord à la liste d'Obsidian s'il n'y est pas.
///
/// Les erreurs et la demande de fermeture d'Obsidian s'affichent en bandeau dans le panneau, par `present`.
@MainActor
final class VaultOpener {
    private let registry: ObsidianRegistry
    /// Temps laissé à Obsidian pour se fermer avant d'abandonner.
    private let quitTimeout: TimeInterval = 20

    var present: (Banner) -> Void = { _ in }
    /// Appelé quand le lien est envoyé à Obsidian : le panneau peut se refermer.
    var didLaunch: () -> Void = {}

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
