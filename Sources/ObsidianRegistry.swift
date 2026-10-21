import Foundation

/// Un vault tel qu'Obsidian l'enregistre dans sa propre liste.
struct ObsidianVaultEntry: Equatable {
    let id: String
    let path: String
}

enum ObsidianRegistryError: LocalizedError {
    case unreadable(path: String, reason: String)
    case unwritable(path: String, reason: String)

    var errorDescription: String? {
        switch self {
        case let .unreadable(path, reason):
            return "La liste des vaults d'Obsidian est illisible (\(path)) : \(reason)"
        case let .unwritable(path, reason):
            return "Impossible de modifier la liste des vaults d'Obsidian (\(path)) : \(reason)"
        }
    }
}

/// Lit et complète la liste des vaults d'Obsidian (`obsidian.json`).
///
/// Obsidian n'a aucune commande pour ouvrir un dossier qu'il ne connaît pas : il faut d'abord
/// l'inscrire dans ce fichier, puis l'ouvrir par `obsidian://open?vault=<id>`. L'inscription doit
/// se faire Obsidian fermé : en quittant, il réécrit le fichier avec sa liste en mémoire et
/// effacerait l'entrée ajoutée entre-temps. C'est `VaultOpener` qui s'en charge.
///
/// Les clés inconnues du fichier sont conservées telles quelles : on ne touche qu'à `vaults`.
final class ObsidianRegistry {
    static let bundleIdentifier = "md.obsidian"

    static var defaultConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/obsidian/obsidian.json")
    }

    let configURL: URL

    var backupURL: URL { configURL.appendingPathExtension("bak") }

    init(configURL: URL = ObsidianRegistry.defaultConfigURL) {
        self.configURL = configURL
    }

    /// Vaults connus d'Obsidian, triés par chemin. Liste vide si Obsidian n'a jamais été lancé.
    func knownVaults() throws -> [ObsidianVaultEntry] {
        let vaults = try readConfig()["vaults"] as? [String: Any] ?? [:]
        return vaults.compactMap { id, value in
            guard let path = (value as? [String: Any])?["path"] as? String else { return nil }
            return ObsidianVaultEntry(id: id, path: path)
        }
        .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// Identifiant du vault situé à `path`, ou `nil` si Obsidian ne le connaît pas.
    func vaultID(forPath path: String) throws -> String? {
        let target = Self.normalizedPath(path)
        return try knownVaults().first { Self.normalizedPath($0.path) == target }?.id
    }

    /// Inscrit `path` dans la liste d'Obsidian et renvoie son identifiant (l'existant s'il y est déjà).
    /// Le fichier d'origine est d'abord copié dans `obsidian.json.bak`.
    @discardableResult
    func register(path: String) throws -> String {
        if let existing = try vaultID(forPath: path) { return existing }

        var config = try readConfig()
        var vaults = config["vaults"] as? [String: Any] ?? [:]
        var id = Self.makeVaultID()
        while vaults[id] != nil { id = Self.makeVaultID() }
        vaults[id] = [
            "path": Self.cleanPath(path),
            "ts": Int64(Date().timeIntervalSince1970 * 1000),
        ]
        config["vaults"] = vaults

        let fm = FileManager.default
        do {
            try fm.createDirectory(at: configURL.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            if fm.fileExists(atPath: configURL.path) {
                try? fm.removeItem(at: backupURL)
                try fm.copyItem(at: configURL, to: backupURL)
            }
            let data = try JSONSerialization.data(withJSONObject: config)
            try data.write(to: configURL, options: .atomic)
        } catch {
            throw ObsidianRegistryError.unwritable(path: configURL.path, reason: error.localizedDescription)
        }
        return id
    }

    static func openURL(vaultID: String) -> URL {
        var components = URLComponents()
        components.scheme = "obsidian"
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "vault", value: vaultID)]
        return components.url!
    }

    /// Forme comparable d'un chemin : Unicode composé (NFC), sans `/` final, en minuscules
    /// (APFS et exFAT ne distinguent pas la casse par défaut).
    static func normalizedPath(_ path: String) -> String {
        cleanPath(path).precomposedStringWithCanonicalMapping.lowercased()
    }

    private static func cleanPath(_ path: String) -> String {
        var cleaned = (path as NSString).standardizingPath
        while cleaned.count > 1 && cleaned.hasSuffix("/") { cleaned.removeLast() }
        return cleaned
    }

    /// Même format qu'Obsidian : 16 caractères hexadécimaux.
    private static func makeVaultID() -> String {
        (0..<16).map { _ in String(Int.random(in: 0..<16), radix: 16) }.joined()
    }

    private func readConfig() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: configURL.path) else { return [:] }
        do {
            let data = try Data(contentsOf: configURL)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ObsidianRegistryError.unreadable(path: configURL.path, reason: "ce n'est pas un objet JSON")
            }
            return object
        } catch let error as ObsidianRegistryError {
            throw error
        } catch {
            throw ObsidianRegistryError.unreadable(path: configURL.path, reason: error.localizedDescription)
        }
    }
}
