import Combine
import Foundation

struct VaultCategory: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    /// Clé de `VaultStore.colorKeys`. Absente des fichiers écrits avant l'ajout des couleurs.
    var color: String?
    /// Nom d'un symbole SF, affiché dans la pastille de la catégorie.
    var symbol: String?
}

struct Vault: Codable, Identifiable, Hashable {
    var id: UUID
    /// Nom affiché dans l'app. Le dossier sur le disque garde le sien.
    var name: String
    var path: String
    /// Signet macOS du dossier : il le retrouve s'il a été déplacé ou si son disque a changé de nom.
    var bookmark: Data?
    var categoryID: UUID
}

/// Contenu de `config.json`.
struct VaultConfiguration: Codable {
    var version = 1
    var categories: [VaultCategory]
    /// L'ordre du tableau est l'ordre d'affichage, à l'intérieur de chaque catégorie.
    var vaults: [Vault]
}

enum VaultStoreError: LocalizedError {
    case emptyName
    case duplicateCategory(String)
    case duplicateVault(name: String, category: String)
    case lastCategory

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Le nom ne peut pas être vide."
        case let .duplicateCategory(name):
            return "Une catégorie s'appelle déjà « \(name) »."
        case let .duplicateVault(name, category):
            return "Ce dossier est déjà dans la liste : « \(name) », catégorie « \(category) »."
        case .lastCategory:
            return "Il faut garder au moins une catégorie."
        }
    }
}

/// Liste des catégories et des vaults de l'app, enregistrée dans `config.json`.
///
/// Chaque modification réécrit le fichier, après en avoir copié la version précédente dans
/// `config.json.bak`. Toutes les méthodes s'appellent depuis le fil principal.
final class VaultStore: ObservableObject {
    static let defaultCategoryName = "Non classés"
    static let defaultSymbol = "folder.fill"
    static let defaultCategorySymbol = "tray.fill"

    /// Couleurs proposées pour les catégories, dans l'ordre du sélecteur.
    static let colorKeys = ["violet", "indigo", "bleu", "turquoise", "vert", "jaune",
                            "orange", "rouge", "rose", "marron", "gris"]
    /// Ordre d'attribution aux nouvelles catégories : deux catégories voisines ont des couleurs bien distinctes.
    static let autoColorOrder = ["violet", "bleu", "vert", "orange", "rose", "turquoise",
                                 "jaune", "rouge", "indigo", "marron", "gris"]

    static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ObsiVaults")
    }

    @Published private(set) var categories: [VaultCategory] = []
    @Published private(set) var vaults: [Vault] = []
    /// Dernière erreur d'enregistrement, `nil` si le dernier enregistrement a réussi.
    @Published private(set) var saveError: String?

    let fileURL: URL
    var backupURL: URL { fileURL.appendingPathExtension("bak") }
    /// Vrai si `config.json` n'existait pas : la liste vient d'être créée à partir d'Obsidian.
    private(set) var isFirstLaunch = false
    /// Nombre de vaults importés d'Obsidian au premier lancement.
    private(set) var initialImportCount = 0
    /// Message à montrer si `config.json` était illisible au chargement.
    private(set) var loadWarning: String?

    private let registry: ObsidianRegistry

    init(directory: URL = VaultStore.defaultDirectory, registry: ObsidianRegistry) {
        fileURL = directory.appendingPathComponent("config.json")
        self.registry = registry
        load()
    }

    // MARK: - Lecture

    func category(_ id: UUID) -> VaultCategory? { categories.first { $0.id == id } }

    func vault(_ id: UUID) -> Vault? { vaults.first { $0.id == id } }

    func vaults(in categoryID: UUID) -> [Vault] { vaults.filter { $0.categoryID == categoryID } }

    func isAvailable(_ vault: Vault) -> Bool { Self.isFolder(atPath: vault.path) }

    // MARK: - Catégories

    @discardableResult
    func addCategory(named name: String) throws -> VaultCategory {
        let name = try validCategoryName(name, excluding: nil)
        let category = VaultCategory(id: UUID(), name: name, color: nextColor(), symbol: Self.defaultSymbol)
        categories.append(category)
        persist()
        return category
    }

    /// Change la couleur et/ou l'icône ; `nil` laisse la valeur actuelle.
    func setStyle(of id: UUID, color: String? = nil, symbol: String? = nil) {
        guard let index = categories.firstIndex(where: { $0.id == id }) else { return }
        if let color, Self.colorKeys.contains(color) { categories[index].color = color }
        if let symbol, !symbol.isEmpty { categories[index].symbol = symbol }
        persist()
    }

    func renameCategory(_ id: UUID, to name: String) throws {
        let name = try validCategoryName(name, excluding: id)
        guard let index = categories.firstIndex(where: { $0.id == id }) else { return }
        categories[index].name = name
        persist()
    }

    /// Supprime une catégorie. Ses vaults vont dans `destination` (obligatoire si elle n'est pas vide).
    func deleteCategory(_ id: UUID, movingVaultsTo destination: UUID?) throws {
        guard categories.count > 1 else { throw VaultStoreError.lastCategory }
        let target = destination.flatMap { $0 == id ? nil : category($0) }?.id
            ?? categories.first { $0.id != id }!.id
        for index in vaults.indices where vaults[index].categoryID == id {
            vaults[index].categoryID = target
        }
        categories.removeAll { $0.id == id }
        persist()
    }

    func moveCategories(fromOffsets source: IndexSet, toOffset destination: Int) {
        categories.moveElements(fromOffsets: source, toOffset: destination)
        persist()
    }

    /// Monte (`offset` négatif) ou descend une catégorie d'autant de places.
    func moveCategory(_ id: UUID, by offset: Int) {
        guard let index = categories.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard target != index, categories.indices.contains(target) else { return }
        categories.moveElements(fromOffsets: IndexSet(integer: index), toOffset: target > index ? target + 1 : target)
        persist()
    }

    // MARK: - Vaults

    @discardableResult
    func addVault(at url: URL, name: String? = nil, to categoryID: UUID) throws -> Vault {
        try ensureNotListed(url.path, except: nil)
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let vault = Vault(id: UUID(),
                          name: trimmed.isEmpty ? defaultName(forPath: url.path) : trimmed,
                          path: url.path,
                          bookmark: Self.makeBookmark(for: url),
                          categoryID: category(categoryID)?.id ?? categories[0].id)
        vaults.append(vault)
        persist()
        return vault
    }

    func renameVault(_ id: UUID, to name: String) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw VaultStoreError.emptyName }
        guard let index = vaults.firstIndex(where: { $0.id == id }) else { return }
        vaults[index].name = name
        persist()
    }

    func changePath(of id: UUID, to url: URL) throws {
        try ensureNotListed(url.path, except: id)
        guard let index = vaults.firstIndex(where: { $0.id == id }) else { return }
        vaults[index].path = url.path
        vaults[index].bookmark = Self.makeBookmark(for: url)
        persist()
    }

    /// Place le vault à la fin de la catégorie `categoryID`.
    func moveVault(_ id: UUID, to categoryID: UUID) {
        guard category(categoryID) != nil,
              let index = vaults.firstIndex(where: { $0.id == id }),
              vaults[index].categoryID != categoryID else { return }
        var vault = vaults.remove(at: index)
        vault.categoryID = categoryID
        vaults.append(vault)
        persist()
    }

    /// Réordonne les vaults d'une catégorie ; les offsets portent sur `vaults(in: categoryID)`.
    func moveVaults(in categoryID: UUID, fromOffsets source: IndexSet, toOffset destination: Int) {
        let positions = vaults.indices.filter { vaults[$0].categoryID == categoryID }
        var reordered = positions.map { vaults[$0] }
        reordered.moveElements(fromOffsets: source, toOffset: destination)
        for (position, vault) in zip(positions, reordered) { vaults[position] = vault }
        persist()
    }

    /// Monte (`offset` négatif) ou descend un vault d'autant de places dans sa catégorie.
    func moveVault(_ id: UUID, by offset: Int) {
        guard let vault = vault(id) else { return }
        let siblings = vaults(in: vault.categoryID)
        guard let index = siblings.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard target != index, siblings.indices.contains(target) else { return }
        moveVaults(in: vault.categoryID, fromOffsets: IndexSet(integer: index),
                   toOffset: target > index ? target + 1 : target)
    }

    /// Retire le vault de la liste de l'app. Le dossier et la liste d'Obsidian ne changent pas.
    func removeVault(_ id: UUID) {
        vaults.removeAll { $0.id == id }
        persist()
    }

    /// Ajoute à `categoryID` les vaults connus d'Obsidian qui ne sont pas encore dans la liste.
    /// Renvoie le nombre de vaults ajoutés.
    @discardableResult
    func importFromObsidian(into categoryID: UUID) throws -> Int {
        let target = category(categoryID)?.id ?? categories[0].id
        let listed = Set(vaults.map { ObsidianRegistry.normalizedPath($0.path) })
        var seen = Set<String>()
        let fresh = try registry.knownVaults().filter {
            let key = ObsidianRegistry.normalizedPath($0.path)
            return !listed.contains(key) && seen.insert(key).inserted
        }
        guard !fresh.isEmpty else { return 0 }

        // Deux dossiers du même nom (« Obsidian », par exemple) reçoivent le nom de leur parent.
        let takenNames = vaults.map { $0.name.lowercased() }
        let freshNames = fresh.map { ($0.path as NSString).lastPathComponent.lowercased() }
        let imported = fresh.map { entry -> Vault in
            let url = URL(fileURLWithPath: entry.path)
            let base = url.lastPathComponent.lowercased()
            let ambiguous = takenNames.contains(base) || freshNames.filter { $0 == base }.count > 1
            return Vault(id: UUID(),
                         name: Self.displayName(for: url, withParent: ambiguous),
                         path: entry.path,
                         bookmark: Self.makeBookmark(for: url),
                         categoryID: target)
        }
        vaults += imported.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        persist()
        return imported.count
    }

    /// Met à jour le chemin des vaults introuvables dont le dossier a été déplacé ou renommé,
    /// grâce à leur signet. À appeler avant d'afficher la liste.
    func refreshLocations() {
        var changed = false
        for index in vaults.indices {
            let vault = vaults[index]
            if Self.isFolder(atPath: vault.path) {
                // Vault ajouté alors que son dossier était absent : on crée son signet maintenant.
                if vault.bookmark == nil, let bookmark = Self.makeBookmark(for: URL(fileURLWithPath: vault.path)) {
                    vaults[index].bookmark = bookmark
                    changed = true
                }
                continue
            }
            guard let bookmark = vault.bookmark else { continue }
            var stale = false
            // .withoutMounting : un disque débranché reste introuvable, sans tentative de montage.
            guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting],
                                     relativeTo: nil, bookmarkDataIsStale: &stale),
                  Self.isFolder(atPath: url.path),
                  !url.path.contains("/.Trash/") else { continue }
            vaults[index].path = url.path
            vaults[index].bookmark = Self.makeBookmark(for: url) ?? bookmark
            changed = true
        }
        if changed { persist() }
        // La disponibilité des dossiers n'est pas publiée : on force le rafraîchissement de l'affichage.
        objectWillChange.send()
    }

    // MARK: - Outils

    static func isFolder(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// Vrai si le dossier a déjà été ouvert comme vault (il contient `.obsidian/`).
    static func looksLikeObsidianVault(_ url: URL) -> Bool {
        isFolder(atPath: url.appendingPathComponent(".obsidian").path)
    }

    static func displayName(for url: URL, withParent: Bool) -> String {
        guard withParent else { return url.lastPathComponent }
        return "\(url.lastPathComponent) (\(friendlyParentName(of: url)))"
    }

    private static func friendlyParentName(of url: URL) -> String {
        let parent = url.deletingLastPathComponent()
        switch parent.lastPathComponent {
        case "com~apple~CloudDocs":
            return "iCloud"
        case "Documents" where parent.deletingLastPathComponent().lastPathComponent == "iCloud~md~obsidian":
            return "iCloud"
        case "", "/":
            return "racine"
        default:
            return parent.lastPathComponent
        }
    }

    private static func makeBookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    private func defaultName(forPath path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let ambiguous = vaults.contains { $0.name.lowercased() == url.lastPathComponent.lowercased() }
        return Self.displayName(for: url, withParent: ambiguous)
    }

    /// Première couleur pas encore prise, ou la suivante dans le cycle si toutes le sont.
    private func nextColor() -> String {
        let used = categories.compactMap(\.color)
        return Self.autoColorOrder.first { !used.contains($0) }
            ?? Self.autoColorOrder[used.count % Self.autoColorOrder.count]
    }

    private func validCategoryName(_ name: String, excluding id: UUID?) throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw VaultStoreError.emptyName }
        if categories.contains(where: { $0.id != id && $0.name.lowercased() == name.lowercased() }) {
            throw VaultStoreError.duplicateCategory(name)
        }
        return name
    }

    private func ensureNotListed(_ path: String, except id: UUID?) throws {
        let key = ObsidianRegistry.normalizedPath(path)
        if let existing = vaults.first(where: { $0.id != id && ObsidianRegistry.normalizedPath($0.path) == key }) {
            throw VaultStoreError.duplicateVault(name: existing.name,
                                                 category: category(existing.categoryID)?.name ?? "?")
        }
    }

    // MARK: - Fichier

    private func load() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else {
            isFirstLaunch = true
            categories = [Self.makeDefaultCategory()]
            initialImportCount = (try? importFromObsidian(into: categories[0].id)) ?? 0
            persist()
            return
        }
        if let config = Self.decode(fileURL) {
            apply(config)
            // Enregistre les couleurs et icônes attribuées à d'anciennes catégories.
            if config.categories != categories { persist() }
            return
        }

        // Fichier illisible : on le met de côté plutôt que de l'écraser, puis on essaie la copie de secours.
        let aside = fileURL.deletingLastPathComponent().appendingPathComponent("config.illisible.json")
        try? fm.removeItem(at: aside)
        try? fm.moveItem(at: fileURL, to: aside)
        if let config = Self.decode(backupURL) {
            apply(config)
            loadWarning = "La liste des vaults était illisible : la version précédente a été restaurée. "
                + "Le fichier illisible a été mis de côté sous le nom config.illisible.json."
        } else {
            categories = [Self.makeDefaultCategory()]
            vaults = []
            _ = try? importFromObsidian(into: categories[0].id)
            loadWarning = "La liste des vaults était illisible : elle a été recréée à partir d'Obsidian. "
                + "Le fichier illisible a été mis de côté sous le nom config.illisible.json."
        }
        persist()
    }

    private static func makeDefaultCategory() -> VaultCategory {
        VaultCategory(id: UUID(), name: defaultCategoryName, color: autoColorOrder[0], symbol: defaultCategorySymbol)
    }

    private func apply(_ config: VaultConfiguration) {
        categories = []
        for var category in config.categories {
            // Catégorie écrite avant l'ajout des couleurs : elle en reçoit une, comme une nouvelle.
            if category.color.map(Self.colorKeys.contains) != true { category.color = nextColor() }
            if category.symbol?.isEmpty != false {
                category.symbol = category.name == Self.defaultCategoryName ? Self.defaultCategorySymbol : Self.defaultSymbol
            }
            categories.append(category)
        }
        if categories.isEmpty { categories = [Self.makeDefaultCategory()] }
        let known = Set(categories.map(\.id))
        // Un vault rattaché à une catégorie disparue revient dans la première.
        vaults = config.vaults.map { vault in
            var vault = vault
            if !known.contains(vault.categoryID) { vault.categoryID = categories[0].id }
            return vault
        }
    }

    private static func decode(_ url: URL) -> VaultConfiguration? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(VaultConfiguration.self, from: data)
    }

    private func persist() {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: fileURL.path) {
                try? fm.removeItem(at: backupURL)
                try fm.copyItem(at: fileURL, to: backupURL)
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(VaultConfiguration(categories: categories, vaults: vaults))
            try data.write(to: fileURL, options: .atomic)
            saveError = nil
        } catch {
            saveError = "Impossible d'enregistrer la liste des vaults : \(error.localizedDescription)"
        }
    }
}

extension Array {
    /// Même comportement que `move(fromOffsets:toOffset:)` de SwiftUI, sans dépendre de SwiftUI.
    mutating func moveElements(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.map { self[$0] }
        let removedBefore = source.filter { $0 < destination }.count
        for index in source.reversed() { remove(at: index) }
        insert(contentsOf: moving, at: destination - removedBefore)
    }
}
