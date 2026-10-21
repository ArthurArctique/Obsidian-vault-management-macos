import Cocoa

@main
enum ObsiVaultsApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // `NSApplication.delegate` est une référence faible : on garde le délégué en vie.
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Envoyée par une seconde copie de l'app pour que la première ouvre son panneau.
    private static let showPanelNotification = Notification.Name("fr.arthur.obsivaults.showPanel")

    private var store: VaultStore!
    private var actions: VaultActions!
    private var menuBar: MenuBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Une seule ObsiVaults à la fois (par exemple une copie dans Applications et une autre dans build/).
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0 != NSRunningApplication.current }
        if !others.isEmpty {
            DistributedNotificationCenter.default().postNotificationName(
                Self.showPanelNotification, object: nil, userInfo: nil, deliverImmediately: true)
            NSApp.terminate(nil)
            return
        }

        installMainMenu()

        // OBSIVAULTS_CONFIG_DIR permet d'essayer l'app avec une liste à part, sans toucher à la vraie.
        let directory = ProcessInfo.processInfo.environment["OBSIVAULTS_CONFIG_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) } ?? VaultStore.defaultDirectory
        let registry = ObsidianRegistry()
        store = VaultStore(directory: directory, registry: registry)
        actions = VaultActions(store: store, opener: VaultOpener(registry: registry))
        menuBar = MenuBarController(store: store, actions: actions)

        DistributedNotificationCenter.default().addObserver(
            forName: Self.showPanelNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.menuBar.showPanel() }
        }

        if let banner = launchBanner() {
            actions.banner = banner
            // L'icône n'a sa place dans la barre des menus qu'une fois celle-ci mise en page.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.menuBar.showPanel() }
        }
    }

    /// Accueil au premier lancement, ou avertissement si la liste a dû être restaurée.
    private func launchBanner() -> Banner? {
        if let warning = store.loadWarning { return Banner(.warning, "Liste restaurée", warning) }
        guard store.isFirstLaunch else { return nil }
        let count = store.initialImportCount
        return Banner(.info, "Bienvenue dans ObsiVaults",
                      count > 0
                          ? "Les \(count) vaults qu'Obsidian connaissait sont dans « \(VaultStore.defaultCategoryName) ». "
                              + "Crée tes catégories avec « Catégorie » en bas, puis range-les avec « Modifier »."
                          : "Ajoute tes vaults avec le bouton « Vault » en bas.")
    }

    /// Relancer l'app alors qu'elle tourne déjà (double-clic dans le Finder) ouvre le panneau.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        menuBar?.showPanel()
        return false
    }

    /// Sans icône dans le Dock, l'app n'affiche pas de barre de menus. Celle-ci reste nécessaire :
    /// c'est elle qui fait marcher ⌘C, ⌘V et ⌘A dans les champs du panneau.
    private func installMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quitter ObsiVaults", action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Édition")
        editMenu.addItem(withTitle: "Annuler", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Rétablir", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Couper", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copier", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Coller", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Tout sélectionner", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        NSApp.mainMenu = main
    }
}
