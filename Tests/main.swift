import Foundation

private var failures: [String] = []
private var checks = 0

/// Une erreur levée pendant la vérification compte comme un échec.
private func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) {
    checks += 1
    if (try? condition()) != true { failures.append(message) }
}

private func expectThrows(_ message: String, _ body: () throws -> Void) {
    checks += 1
    do {
        try body()
        failures.append(message)
    } catch {}
}

let fm = FileManager.default
let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["OBSIVAULTS_TEST_DIR"]
    ?? fm.temporaryDirectory.appendingPathComponent("obsivaults-tests-\(UUID().uuidString)").path)
try? fm.removeItem(at: root)
try fm.createDirectory(at: root, withIntermediateDirectories: true)

/// Crée un dossier (et, si demandé, son `.obsidian/`) et renvoie son URL.
@discardableResult
func makeFolder(_ relative: String, vault: Bool = true) -> URL {
    let url = root.appendingPathComponent(relative)
    try! fm.createDirectory(at: vault ? url.appendingPathComponent(".obsidian") : url,
                            withIntermediateDirectories: true)
    return url
}

func writeObsidianConfig(_ object: [String: Any], to url: URL) {
    try! fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! JSONSerialization.data(withJSONObject: object).write(to: url)
}

func readJSON(_ url: URL) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: Data(contentsOf: url))) as? [String: Any] ?? [:]
}

// MARK: - Déplacement d'éléments (même comportement que SwiftUI)

var letters = ["a", "b", "c", "d", "e"]
letters.moveElements(fromOffsets: IndexSet(integer: 0), toOffset: 3)
expect(letters == ["b", "c", "a", "d", "e"], "déplacer vers le bas doit insérer avant l'offset d'origine")
letters = ["a", "b", "c", "d", "e"]
letters.moveElements(fromOffsets: IndexSet(integer: 4), toOffset: 1)
expect(letters == ["a", "e", "b", "c", "d"], "déplacer vers le haut doit insérer à l'offset")
letters = ["a", "b", "c", "d", "e"]
letters.moveElements(fromOffsets: IndexSet([0, 2]), toOffset: 5)
expect(letters == ["b", "d", "e", "a", "c"], "plusieurs éléments déplacés doivent garder leur ordre")

// MARK: - obsidian.json

let obsidianConfig = root.appendingPathComponent("obsidian/obsidian.json")
let registry = ObsidianRegistry(configURL: obsidianConfig)

expect((try? registry.knownVaults())?.isEmpty == true, "sans obsidian.json, la liste d'Obsidian doit être vide")

let notes = makeFolder("Notes")
let cours = makeFolder("Cours")
writeObsidianConfig([
    "vaults": ["aaaaaaaaaaaaaaaa": ["path": notes.path, "ts": 1, "open": true]],
    "updateDisabled": true,
], to: obsidianConfig)

expect(try registry.vaultID(forPath: notes.path) == "aaaaaaaaaaaaaaaa", "un vault connu doit être retrouvé")
expect(try registry.vaultID(forPath: notes.path + "/") == "aaaaaaaaaaaaaaaa", "le / final doit être ignoré")
expect(try registry.vaultID(forPath: notes.path.uppercased()) == "aaaaaaaaaaaaaaaa", "la casse doit être ignorée")
expect(try registry.vaultID(forPath: cours.path) == nil, "un dossier inconnu ne doit pas être retrouvé")

let accented = "Bio-informatique"
let nfc = "/tmp/Universit\u{E9}/\(accented)"
let nfd = "/tmp/Universite\u{301}/\(accented)"
expect(ObsidianRegistry.normalizedPath(nfc) == ObsidianRegistry.normalizedPath(nfd),
       "les accents composés et décomposés doivent être équivalents")

let newID = try registry.register(path: cours.path)
let afterRegister = readJSON(obsidianConfig)
let registered = afterRegister["vaults"] as? [String: Any] ?? [:]
expect(newID.count == 16 && newID.allSatisfy(\.isHexDigit), "l'identifiant doit avoir le format d'Obsidian")
expect(((registered[newID] as? [String: Any])?["path"] as? String).map(ObsidianRegistry.normalizedPath)
           == ObsidianRegistry.normalizedPath(cours.path), "le vault doit être inscrit")
expect(registered["aaaaaaaaaaaaaaaa"] != nil, "les vaults existants doivent être conservés")
expect((registered["aaaaaaaaaaaaaaaa"] as? [String: Any])?["open"] as? Bool == true,
       "les champs des vaults existants doivent être conservés")
expect(afterRegister["updateDisabled"] as? Bool == true, "les autres réglages d'Obsidian doivent être conservés")
expect(fm.fileExists(atPath: registry.backupURL.path), "une copie obsidian.json.bak doit être faite")
expect(try registry.register(path: cours.path) == newID, "réinscrire un vault doit renvoyer le même identifiant")
expect(ObsidianRegistry.openURL(vaultID: newID).absoluteString == "obsidian://open?vault=\(newID)",
       "l'URL d'ouverture doit suivre le format d'Obsidian")

let brokenConfig = root.appendingPathComponent("broken/obsidian.json")
try fm.createDirectory(at: brokenConfig.deletingLastPathComponent(), withIntermediateDirectories: true)
try Data("{ pas du json".utf8).write(to: brokenConfig)
expectThrows("un obsidian.json illisible doit être signalé") {
    try ObsidianRegistry(configURL: brokenConfig).register(path: cours.path)
}
expect(String(data: try Data(contentsOf: brokenConfig), encoding: .utf8) == "{ pas du json",
       "un obsidian.json illisible ne doit pas être écrasé")

// MARK: - Premier lancement : import depuis Obsidian

let icloudVault = makeFolder("Mobile Documents/com~apple~CloudDocs/Obsidian")
let schoolVault = makeFolder("Bio-informatique/Obsidian")
let missingPath = root.appendingPathComponent("Disque débranché/Projet").path
writeObsidianConfig([
    "vaults": [
        "1111111111111111": ["path": icloudVault.path, "ts": 1],
        "2222222222222222": ["path": schoolVault.path, "ts": 2],
        "3333333333333333": ["path": notes.path, "ts": 3],
        "4444444444444444": ["path": notes.path + "/", "ts": 4],
        "5555555555555555": ["path": missingPath, "ts": 5],
    ],
], to: obsidianConfig)

let storeDir = root.appendingPathComponent("store")
var store = VaultStore(directory: storeDir, registry: registry)
expect(store.isFirstLaunch, "sans config.json, c'est un premier lancement")
expect(store.categories.map(\.name) == [VaultStore.defaultCategoryName], "une catégorie par défaut doit être créée")
expect(store.categories[0].color == "violet" && store.categories[0].symbol == VaultStore.defaultCategorySymbol,
       "la catégorie par défaut doit avoir une couleur et une icône")
expect(store.vaults.count == 4, "les vaults d'Obsidian doivent être importés une seule fois chacun (reçu \(store.vaults.count))")
expect(store.initialImportCount == 4, "le nombre de vaults importés doit être retenu")
let names = Set(store.vaults.map(\.name))
expect(names.contains("Obsidian (iCloud)"), "le dossier iCloud doit être nommé « iCloud » (reçu \(names))")
expect(names.contains("Obsidian (Bio-informatique)"), "deux vaults homonymes doivent recevoir le nom de leur parent")
expect(names.contains("Notes"), "un vault au nom unique doit garder le nom de son dossier")
expect(fm.fileExists(atPath: store.fileURL.path), "config.json doit être écrit dès le premier lancement")
let missingVault = store.vaults.first { $0.path == missingPath }!
expect(!store.isAvailable(missingVault), "un dossier absent doit être signalé introuvable")
expect(missingVault.bookmark == nil, "un dossier absent ne peut pas avoir de signet")

// MARK: - Catégories

let defaultCategory = store.categories[0]
let video = try store.addCategory(named: "  Vidéo  ")
expect(video.name == "Vidéo", "le nom d'une catégorie doit être nettoyé des espaces")
expectThrows("deux catégories ne doivent pas porter le même nom") { try store.addCategory(named: "vidéo") }
expectThrows("une catégorie ne doit pas avoir un nom vide") { try store.addCategory(named: "   ") }
try store.renameCategory(video.id, to: "Projets vidéo")
expect(store.category(video.id)?.name == "Projets vidéo", "une catégorie doit pouvoir être renommée")
try store.renameCategory(video.id, to: "projets VIDÉO")
expect(store.category(video.id)?.name == "projets VIDÉO", "changer seulement la casse de son propre nom doit marcher")
let school = try store.addCategory(named: "Fac")
expect(video.color == "bleu" && school.color == "vert", "chaque nouvelle catégorie doit recevoir une couleur libre")
expect(school.symbol == VaultStore.defaultSymbol, "une nouvelle catégorie doit avoir l'icône par défaut")
store.setStyle(of: school.id, color: "rose", symbol: "graduationcap.fill")
expect(store.category(school.id)?.color == "rose" && store.category(school.id)?.symbol == "graduationcap.fill",
       "la couleur et l'icône d'une catégorie doivent pouvoir changer")
store.setStyle(of: school.id, color: "fuchsia")
expect(store.category(school.id)?.color == "rose", "une couleur inconnue doit être ignorée")
store.moveCategories(fromOffsets: IndexSet(integer: 2), toOffset: 0)
expect(store.categories.map(\.id) == [school.id, defaultCategory.id, video.id], "les catégories doivent pouvoir être réordonnées")
store.moveCategory(school.id, by: 1)
expect(store.categories.map(\.id) == [defaultCategory.id, school.id, video.id], "descendre une catégorie d'un cran")
store.moveCategory(video.id, by: -2)
expect(store.categories.map(\.id) == [video.id, defaultCategory.id, school.id], "monter une catégorie de deux crans")
store.moveCategory(video.id, by: -1)
expect(store.categories.first?.id == video.id, "monter la première catégorie ne doit rien changer")
store.moveCategories(fromOffsets: IndexSet(integer: 0), toOffset: 3)
store.moveCategories(fromOffsets: IndexSet(integer: 1), toOffset: 0)
expect(store.categories.map(\.id) == [school.id, defaultCategory.id, video.id], "retour à l'ordre de départ")

// MARK: - Vaults

let film = makeFolder("Film")
let added = try store.addVault(at: film, to: video.id)
expect(added.name == "Film" && added.categoryID == video.id, "un vault ajouté doit aller dans la catégorie choisie")
expect(added.bookmark != nil, "un vault ajouté doit avoir un signet")
expectThrows("un même dossier ne doit pas être ajouté deux fois") {
    try store.addVault(at: URL(fileURLWithPath: film.path + "/"), to: school.id)
}
let samename = makeFolder("Autre/Notes")
expect(try store.addVault(at: samename, to: video.id).name == "Notes (Autre)",
       "un vault ajouté sous un nom déjà pris doit recevoir le nom de son parent")

try store.renameVault(added.id, to: "Mon film")
expect(store.vault(added.id)?.name == "Mon film", "un vault doit pouvoir être renommé")
expect(store.vault(added.id)?.path == film.path, "renommer un vault ne doit pas changer son chemin")
expectThrows("un vault ne doit pas avoir un nom vide") { try store.renameVault(added.id, to: "") }

let film2 = makeFolder("Film-v2")
try store.changePath(of: added.id, to: film2)
expect(store.vault(added.id)?.path == film2.path, "le chemin d'un vault doit pouvoir changer")
expectThrows("le nouveau chemin ne doit pas être celui d'un autre vault") {
    try store.changePath(of: added.id, to: notes)
}
try store.changePath(of: added.id, to: film2)
expect(store.vault(added.id)?.path == film2.path, "rechoisir le même dossier doit être accepté")

let notesVault = store.vaults.first { $0.path == notes.path }!
store.moveVault(notesVault.id, to: video.id)
expect(store.vaults(in: video.id).last?.id == notesVault.id, "un vault déplacé doit arriver à la fin de la catégorie")
let videoOrder = store.vaults(in: video.id).map(\.id)
store.moveVaults(in: video.id, fromOffsets: IndexSet(integer: videoOrder.count - 1), toOffset: 0)
expect(store.vaults(in: video.id).map(\.id) == [videoOrder.last!] + videoOrder.dropLast(),
       "les vaults doivent pouvoir être réordonnés dans leur catégorie")
expect(store.vaults(in: defaultCategory.id).count == 3, "réordonner une catégorie ne doit pas toucher aux autres")
let videoBefore = store.vaults(in: video.id).map(\.id)
store.moveVault(videoBefore[0], by: 1)
expect(store.vaults(in: video.id).map(\.id) == [videoBefore[1], videoBefore[0]] + videoBefore.dropFirst(2),
       "descendre un vault d'un cran")
store.moveVault(videoBefore[0], by: -1)
expect(store.vaults(in: video.id).map(\.id) == videoBefore, "remonter un vault d'un cran")
store.moveVault(videoBefore.last!, by: 1)
expect(store.vaults(in: video.id).map(\.id) == videoBefore, "descendre le dernier vault ne doit rien changer")

// MARK: - Dossier déplacé : le signet le retrouve

let moved = root.appendingPathComponent("Film-renomme")
try fm.moveItem(at: film2, to: moved)
expect(!store.isAvailable(store.vault(added.id)!), "après le déplacement, l'ancien chemin est introuvable")
store.refreshLocations()
expect(URL(fileURLWithPath: store.vault(added.id)!.path).lastPathComponent == "Film-renomme",
       "le signet doit retrouver un dossier renommé (reçu \(store.vault(added.id)!.path))")
expect(store.isAvailable(store.vault(added.id)!), "le vault doit redevenir disponible")

// MARK: - Suppressions

expectThrows("la dernière catégorie ne doit pas pouvoir être supprimée") {
    let lonely = VaultStore(directory: root.appendingPathComponent("lonely"), registry: ObsidianRegistry(
        configURL: root.appendingPathComponent("absent/obsidian.json")))
    try lonely.deleteCategory(lonely.categories[0].id, movingVaultsTo: nil)
}
let videoCount = store.vaults(in: video.id).count
try store.deleteCategory(video.id, movingVaultsTo: school.id)
expect(store.category(video.id) == nil, "la catégorie doit être supprimée")
expect(store.vaults(in: school.id).count == videoCount, "ses vaults doivent aller dans la catégorie choisie")
let countBeforeRemove = store.vaults.count
store.removeVault(added.id)
expect(store.vaults.count == countBeforeRemove - 1 && store.vault(added.id) == nil, "un vault doit pouvoir être retiré")
expect(fm.fileExists(atPath: moved.path), "retirer un vault ne doit pas supprimer son dossier")

// MARK: - Import manuel

let imported = try store.importFromObsidian(into: school.id)
expect(imported == 0, "réimporter ne doit rien ajouter quand tout est déjà là (reçu \(imported))")
store.removeVault(notesVault.id)
expect(try store.importFromObsidian(into: school.id) == 1, "un vault retiré doit pouvoir être réimporté")

// MARK: - Relecture et fichiers abîmés

let snapshotCategories = store.categories
let snapshotVaults = store.vaults
store = VaultStore(directory: storeDir, registry: registry)
expect(!store.isFirstLaunch, "un config.json existant n'est pas un premier lancement")
expect(store.categories == snapshotCategories, "les catégories doivent être relues à l'identique")
expect(store.vaults == snapshotVaults, "les vaults doivent être relus à l'identique")
expect(fm.fileExists(atPath: store.backupURL.path), "une copie config.json.bak doit exister")

try Data("{ cassé".utf8).write(to: store.fileURL)
store = VaultStore(directory: storeDir, registry: registry)
expect(store.loadWarning != nil, "un config.json illisible doit être signalé")
expect(!store.vaults.isEmpty, "la copie de secours doit être restaurée")
expect(fm.fileExists(atPath: storeDir.appendingPathComponent("config.illisible.json").path),
       "le fichier illisible doit être mis de côté")

let orphanDir = root.appendingPathComponent("orphan")
try fm.createDirectory(at: orphanDir, withIntermediateDirectories: true)
let orphanCategory = VaultCategory(id: UUID(), name: "Seule")
let orphan = Vault(id: UUID(), name: "Perdu", path: notes.path, bookmark: nil, categoryID: UUID())
try JSONEncoder().encode(VaultConfiguration(categories: [orphanCategory], vaults: [orphan]))
    .write(to: orphanDir.appendingPathComponent("config.json"))
let orphanStore = VaultStore(directory: orphanDir, registry: registry)
expect(orphanStore.vaults.first?.categoryID == orphanCategory.id,
       "un vault d'une catégorie disparue doit revenir dans la première catégorie")

// MARK: - Ancien fichier, sans couleurs ni icônes

let legacyDir = root.appendingPathComponent("legacy")
try fm.createDirectory(at: legacyDir, withIntermediateDirectories: true)
let legacyIDs = [UUID(), UUID()]
try Data("""
{"version": 1, "vaults": [], "categories": [
  {"id": "\(legacyIDs[0].uuidString)", "name": "\(VaultStore.defaultCategoryName)"},
  {"id": "\(legacyIDs[1].uuidString)", "name": "Cours"}
]}
""".utf8).write(to: legacyDir.appendingPathComponent("config.json"))
let legacy = VaultStore(directory: legacyDir, registry: registry)
expect(legacy.loadWarning == nil, "un fichier sans couleurs doit rester lisible")
expect(legacy.categories.map(\.color) == ["violet", "bleu"], "les anciennes catégories doivent recevoir des couleurs distinctes")
expect(legacy.categories.map(\.symbol) == [VaultStore.defaultCategorySymbol, VaultStore.defaultSymbol],
       "les anciennes catégories doivent recevoir une icône")
let legacyReloaded = VaultStore(directory: legacyDir, registry: registry)
expect(legacyReloaded.categories == legacy.categories, "les couleurs attribuées doivent être enregistrées")

// MARK: - Bilan

if failures.isEmpty {
    print("✅ \(checks) vérifications réussies")
} else {
    print("❌ \(failures.count) échec(s) sur \(checks) vérifications :")
    failures.forEach { print("  - \($0)") }
    exit(1)
}
