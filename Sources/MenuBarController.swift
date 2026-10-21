import Cocoa
import SwiftUI

/// Icône de la barre des menus et panneau qui s'ouvre dessous (repris de SNCF Wifi).
@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    /// Nom d'autosauvegarde du `NSStatusItem` : il identifie la position mémorisée par macOS
    /// quand l'utilisateur déplace l'icône (⌘ + glisser).
    private static let autosaveName = "ObsiVaultsStatusItem"

    /// Position initiale, en points depuis le bord droit de l'écran. Sans elle, macOS place un nouvel
    /// élément au premier emplacement libre à droite, qui tombe sous l'encoche des MacBook quand la
    /// barre est déjà bien remplie : l'icône y serait invisible.
    private static let defaultPreferredPosition = 400

    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let store: VaultStore
    private let actions: VaultActions
    private let panelState = PanelState()

    init(store: VaultStore, actions: VaultActions) {
        self.store = store
        self.actions = actions
        statusItem = Self.makeStatusItem()
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "books.vertical", accessibilityDescription: "ObsiVaults")
            button.image?.isTemplate = true
            button.toolTip = "ObsiVaults"
            button.target = self
            button.action = #selector(togglePanel)
        }
        configurePopover()
    }

    private static func makeStatusItem() -> NSStatusItem {
        let positionKey = "NSStatusItem Preferred Position \(autosaveName)"
        if UserDefaults.standard.object(forKey: positionKey) == nil {
            UserDefaults.standard.set(defaultPreferredPosition, forKey: positionKey)
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = autosaveName
        return item
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        // Laisse de la place à l'en-tête et au pied de page, même sur un petit écran.
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        let panel = PanelView(maxListHeight: max(240, min(560, screenHeight - 220)))
            .environmentObject(store)
            .environmentObject(actions)
            .environmentObject(panelState)
        let host = NSHostingController(rootView: panel)
        // Le panneau suit la taille de son contenu (ouverture d'une question, mode modification…).
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host

        actions.closePanel = { [weak self] in self?.popover.performClose(nil) }
        actions.keepingPanelOpen = { [weak self] body in
            guard let self else { return body() }
            self.keepPanelOpen(during: body)
        }
    }

    // MARK: - Panneau

    @objc private func togglePanel() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPanel()
        }
    }

    func showPanel() {
        guard let button = statusItem.button, !popover.isShown else { return }
        // Disques branchés ou débranchés, dossiers déplacés : la liste est à jour à chaque ouverture.
        store.refreshLocations()
        actions.refreshLaunchAtLogin()
        activateApp()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    /// Le Finder s'ouvre par-dessus le panneau : sans cela, le panneau se refermerait dès qu'il perd la main.
    private func keepPanelOpen(during body: () -> Void) {
        popover.behavior = .applicationDefined
        body()
        popover.behavior = .transient
        if popover.isShown {
            activateApp()
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func activateApp() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        panelState.reset()
        actions.clearPassiveBanner()
    }
}
