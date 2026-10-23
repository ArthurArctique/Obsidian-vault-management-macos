import ApplicationServices
import Cocoa

/// Fenêtres d'Obsidian, vues de l'extérieur.
///
/// Obsidian n'a aucune commande pour fermer un vault : ObsiVaults appuie à sa place sur le bouton de
/// fermeture de la fenêtre, par l'API d'accessibilité de macOS. Il lui faut pour cela l'accès
/// « Accessibilité » (Réglages Système › Confidentialité et sécurité), qu'il demande la première fois.
enum ObsidianWindows {
    enum CloseResult: Equatable {
        case closed(count: Int)
        /// Aucune fenêtre visible : sur un autre bureau, en plein écran, ou le vault n'est plus ouvert.
        case notFound
        /// Un autre vault ouvert porte le même nom de dossier : les titres ne permettent pas de choisir.
        case ambiguous
    }

    static var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    /// Fait afficher par macOS sa demande d'accès, qui inscrit ObsiVaults dans la liste « Accessibilité ».
    static func requestAccessibility() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        let url = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        NSWorkspace.shared.open(URL(string: url)!)
    }

    /// Vrai si l'app a au moins une vraie fenêtre, même réduite dans le Dock ou sur un autre bureau.
    /// Ne demande aucune autorisation : seuls la taille et le niveau des fenêtres sont lus, pas leur titre.
    static func hasWindows(pid: pid_t) -> Bool {
        let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return windows.contains { info in
            guard info[kCGWindowOwnerPID as String] as? pid_t == pid,
                  info[kCGWindowLayer as String] as? Int == 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { return false }
            // macOS attache à chaque app des bandes de 33 points de haut, de la largeur de l'écran.
            return frame.width >= 200 && frame.height >= 150
        }
    }

    /// Ferme les fenêtres du vault dont le dossier s'appelle `name`. `otherOpenNames` : dossiers des autres
    /// vaults ouverts, pour départager les titres. L'accessibilité ne voit que les fenêtres du bureau actuel.
    static func closeWindows(ofVaultNamed name: String, otherOpenNames: [String], pid: pid_t) -> CloseResult {
        let target = name.precomposedStringWithCanonicalMapping
        if otherOpenNames.contains(where: { $0.precomposedStringWithCanonicalMapping == target }) {
            return .ambiguous
        }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString,
                                            &value) == .success,
              let windows = value as? [AXUIElement] else { return .notFound }

        let candidates = [name] + otherOpenNames
        var closed = 0
        for window in windows {
            guard let title = attribute(kAXTitleAttribute, of: window) as? String,
                  vaultName(inTitle: title, among: candidates) == name,
                  let button = attribute(kAXCloseButtonAttribute, of: window),
                  CFGetTypeID(button) == AXUIElementGetTypeID(),
                  AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString) == .success
            else { continue }
            closed += 1
        }
        return closed > 0 ? .closed(count: closed) : .notFound
    }

    /// Vault auquel appartient une fenêtre d'après son titre : « Note - Vault - Obsidian 1.14.5 », ou
    /// « Vault - Obsidian 1.14.5 » sans note ouverte. Le nom le plus long l'emporte : la fenêtre
    /// « Note - Projet - Cours - Obsidian 1.14.5 » va au vault « Projet - Cours » plutôt qu'à « Cours ».
    static func vaultName(inTitle title: String, among candidates: [String]) -> String? {
        let title = title.precomposedStringWithCanonicalMapping
        guard let suffix = title.range(of: " - Obsidian", options: .backwards),
              title[suffix.upperBound...].isEmpty || title[suffix.upperBound...].hasPrefix(" ") else { return nil }
        let head = title[..<suffix.lowerBound]
        return candidates
            .filter { candidate in
                let name = candidate.precomposedStringWithCanonicalMapping
                return head == name || head.hasSuffix(" - " + name)
            }
            .max { $0.count < $1.count }
    }

    private static func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
}
