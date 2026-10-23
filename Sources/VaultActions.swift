import Cocoa
import ServiceManagement

/// Message affiché en haut du panneau, à la place d'une boîte de dialogue.
struct Banner: Identifiable {
    enum Kind { case info, success, question, progress, warning, error }

    let id = UUID()
    var kind: Kind
    var title: String
    var message: String?
    var actions: [BannerAction]
    /// Le bandeau disparaît à l'ouverture du panneau dès que ce qu'il demande est fait.
    var isResolved: (() -> Bool)?

    init(_ kind: Kind, _ title: String, _ message: String? = nil, actions: [BannerAction] = [],
         isResolved: (() -> Bool)? = nil) {
        self.kind = kind
        self.title = title
        self.message = message
        self.actions = actions
        self.isResolved = isResolved
    }

    init(error: Error, title: String) {
        self.init(.error, title, error.localizedDescription)
    }
}

struct BannerAction: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let isDestructive: Bool
    let run: () -> Void

    init(_ title: String, systemImage: String = "arrow.right", destructive: Bool = false,
         run: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isDestructive = destructive
        self.run = run
    }
}

/// Actions déclenchées depuis le panneau. Leurs résultats et leurs erreurs s'affichent dans `banner`.
@MainActor
final class VaultActions: ObservableObject {
    @Published var banner: Banner? {
        didSet { scheduleAutoDismiss() }
    }
    @Published private(set) var launchesAtLogin = false
    /// Vaults ouverts dans Obsidian, sous la forme de `ObsidianRegistry.normalizedPath`.
    @Published private(set) var openVaultPaths: Set<String> = []

    let store: VaultStore
    private let opener: VaultOpener

    /// Referme le panneau, par exemple une fois le vault ouvert dans Obsidian.
    var closePanel: () -> Void = {}
    /// Exécute un sélecteur du Finder sans que le panneau se referme derrière lui.
    var keepingPanelOpen: (() -> Void) -> Void = { $0() }

    init(store: VaultStore, opener: VaultOpener) {
        self.store = store
        self.opener = opener
        opener.present = { [weak self] in self?.banner = $0 }
        opener.didLaunch = { [weak self] in
            self?.banner = nil
            self?.closePanel()
        }
        opener.openVaultsChanged = { [weak self] in self?.refreshOpenVaults() }
        refreshLaunchAtLogin()
    }

    /// À l'ouverture du panneau : état des vaults dans Obsidian et bandeaux devenus inutiles.
    func refresh() {
        refreshLaunchAtLogin()
        refreshOpenVaults()
        if banner?.isResolved?() == true { banner = nil }
    }

    // MARK: - Vaults

    func open(_ id: UUID) {
        guard let vault = store.vault(id) else { return }
        guard store.isAvailable(vault) else {
            showMissingFolder(vault)
            return
        }
        banner = nil
        opener.open(vault)
    }

    func isOpen(_ vault: Vault) -> Bool {
        openVaultPaths.contains(ObsidianRegistry.normalizedPath(vault.path))
    }

    /// Ferme le vault dans Obsidian ; le panneau reste ouvert.
    func close(_ id: UUID) {
        guard let vault = store.vault(id) else { return }
        banner = nil
        opener.close(vault)
    }

    func refreshOpenVaults() {
        let paths = opener.openVaultPaths()
        if paths != openVaultPaths { openVaultPaths = paths }
    }

    func reveal(_ id: UUID) {
        guard let vault = store.vault(id) else { return }
        guard store.isAvailable(vault) else {
            showMissingFolder(vault)
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: vault.path)])
        closePanel()
    }

    /// Fait choisir un dossier dans le Finder. Sans catégorie imposée, le Finder propose de la choisir.
    func addVault(to categoryID: UUID?) {
        let categories = store.categories
        let fixed = categoryID.flatMap(store.category)
        let preselected = categories.firstIndex { $0.id == fixed?.id } ?? 0
        var choice: (url: URL, categoryIndex: Int?)?
        keepingPanelOpen {
            choice = FolderPicker.choose(
                title: fixed.map { "Choisis le dossier du vault à ajouter à « \($0.name) »" }
                    ?? "Choisis le dossier du vault à ajouter",
                prompt: "Ajouter",
                startingAt: nil,
                categories: fixed == nil ? categories.map(\.name) : [],
                selectedCategory: preselected)
        }
        guard let choice else { return }
        let target = categories[choice.categoryIndex ?? preselected]
        do {
            let vault = try store.addVault(at: choice.url, to: target.id)
            banner = Banner(.success, "« \(vault.name) » ajouté à « \(target.name) »", notYetAVaultNote(choice.url))
        } catch {
            banner = Banner(error: error, title: "Impossible d'ajouter ce dossier")
        }
    }

    func changePath(_ id: UUID) {
        guard let vault = store.vault(id) else { return }
        let start = store.isAvailable(vault) ? URL(fileURLWithPath: vault.path).deletingLastPathComponent() : nil
        var url: URL?
        keepingPanelOpen {
            url = FolderPicker.choose(title: "Nouveau dossier de « \(vault.name) »", prompt: "Choisir",
                                      startingAt: start)?.url
        }
        guard let url else { return }
        do {
            try store.changePath(of: id, to: url)
            banner = Banner(.success, "Nouveau dossier pour « \(vault.name) »",
                            notYetAVaultNote(url) ?? Self.shortPath(url.path))
        } catch {
            banner = Banner(error: error, title: "Impossible de changer le dossier")
        }
    }

    /// Renvoie faux si le nom est refusé ; le bandeau explique pourquoi.
    @discardableResult
    func rename(_ id: UUID, to name: String) -> Bool {
        do {
            try store.renameVault(id, to: name)
            return true
        } catch {
            banner = Banner(error: error, title: "Impossible de renommer")
            return false
        }
    }

    func remove(_ id: UUID) {
        store.removeVault(id)
    }

    func move(_ id: UUID, to categoryID: UUID) {
        store.moveVault(id, to: categoryID)
    }

    func move(_ id: UUID, by offset: Int) {
        store.moveVault(id, by: offset)
    }

    func importFromObsidian(into categoryID: UUID) {
        do {
            let count = try store.importFromObsidian(into: categoryID)
            let category = store.category(categoryID)?.name ?? ""
            banner = count == 0
                ? Banner(.info, "Rien à importer", "Tous les vaults connus d'Obsidian sont déjà dans la liste.")
                : Banner(.success, "\(count) vault\(count > 1 ? "s importés" : " importé") dans « \(category) »")
        } catch {
            banner = Banner(error: error, title: "Import impossible")
        }
    }

    // MARK: - Catégories

    func addCategory(named name: String) -> VaultCategory? {
        do {
            return try store.addCategory(named: name)
        } catch {
            banner = Banner(error: error, title: "Impossible de créer la catégorie")
            return nil
        }
    }

    @discardableResult
    func renameCategory(_ id: UUID, to name: String) -> Bool {
        do {
            try store.renameCategory(id, to: name)
            return true
        } catch {
            banner = Banner(error: error, title: "Impossible de renommer")
            return false
        }
    }

    func setStyle(of id: UUID, color: String? = nil, symbol: String? = nil) {
        store.setStyle(of: id, color: color, symbol: symbol)
    }

    func moveCategory(_ id: UUID, by offset: Int) {
        store.moveCategory(id, by: offset)
    }

    func deleteCategory(_ id: UUID, movingVaultsTo destination: UUID?) {
        do {
            try store.deleteCategory(id, movingVaultsTo: destination)
        } catch {
            banner = Banner(error: error, title: "Impossible de supprimer la catégorie")
        }
    }

    // MARK: - Réglages

    func refreshLaunchAtLogin() {
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            banner = Banner(error: error, title: "Impossible de modifier l'ouverture à la connexion")
        }
        if service.status == .requiresApproval {
            banner = Banner(.warning, "Autorisation nécessaire",
                            "macOS demande de valider l'ouverture à la connexion dans Réglages Système.",
                            actions: [BannerAction("Ouvrir les Réglages", systemImage: "gearshape") {
                                SMAppService.openSystemSettingsLoginItems()
                            }])
        }
        refreshLaunchAtLogin()
    }

    func revealConfiguration() {
        NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
        closePanel()
    }

    // MARK: - Outils

    /// Efface les bandeaux qui ne demandent rien quand le panneau se ferme : ils ne seraient plus d'actualité.
    func clearPassiveBanner() {
        guard let kind = banner?.kind, [.info, .success, .question].contains(kind) else { return }
        banner = nil
    }

    /// Un bandeau de réussite sans bouton disparaît tout seul après quelques secondes.
    private func scheduleAutoDismiss() {
        guard let banner, banner.actions.isEmpty, banner.kind == .success || banner.kind == .info else { return }
        let id = banner.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            if self?.banner?.id == id { self?.banner = nil }
        }
    }

    /// Chemin avec `~` à la place du dossier personnel.
    static func shortPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    private func showMissingFolder(_ vault: Vault) {
        banner = Banner(.warning, "Dossier introuvable : « \(vault.name) »",
                        "Il n'est plus à cet endroit : \(Self.shortPath(vault.path)). S'il est sur un disque "
                            + "externe, branche-le ; sinon, indique où il se trouve maintenant.",
                        actions: [BannerAction("Changer le chemin…", systemImage: "folder") { [weak self] in
                            self?.changePath(vault.id)
                        }])
    }

    /// Un dossier jamais ouvert dans Obsidian deviendra un vault à sa première ouverture : on le signale.
    private func notYetAVaultNote(_ url: URL) -> String? {
        VaultStore.looksLikeObsidianVault(url)
            ? nil
            : "Ce dossier n'a encore jamais été ouvert dans Obsidian : il deviendra un vault à sa première ouverture."
    }
}

/// Sélecteur de dossier du Finder, avec un menu « Catégorie » facultatif sous la liste.
@MainActor
enum FolderPicker {
    static func choose(title: String, prompt: String, startingAt directory: URL?,
                       categories: [String] = [], selectedCategory: Int = 0)
        -> (url: URL, categoryIndex: Int?)? {
        // Sans icône dans le Dock, l'app doit passer au premier plan, sinon le Finder s'ouvre derrière.
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        let panel = NSOpenPanel()
        panel.message = title
        panel.prompt = prompt
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = directory

        var popup: NSPopUpButton?
        if !categories.isEmpty {
            let menu = NSPopUpButton(frame: .zero, pullsDown: false)
            menu.addItems(withTitles: categories)
            menu.selectItem(at: selectedCategory)
            let label = NSTextField(labelWithString: "Catégorie :")
            let row = NSStackView(views: [label, menu])
            row.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
            panel.accessoryView = row
            panel.isAccessoryViewDisclosed = true
            popup = menu
        }

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return (url, popup?.indexOfSelectedItem)
    }
}
