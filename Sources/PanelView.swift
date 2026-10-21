import SwiftUI

/// État d'affichage du panneau : mode modification et question en cours. Remis à zéro à la fermeture.
@MainActor
final class PanelState: ObservableObject {
    @Published var isEditing = false
    @Published var renamingVault: UUID?
    @Published var renamingCategory: UUID?
    @Published var removingVault: UUID?
    @Published var movingVault: UUID?
    @Published var deletingCategory: UUID?
    @Published var stylingCategory: UUID?
    @Published var isAddingCategory = false

    func startEditing(styling categoryID: UUID? = nil) {
        clearPrompts()
        isEditing = true
        stylingCategory = categoryID
    }

    func finishEditing() {
        clearPrompts()
        isEditing = false
    }

    func startAddingCategory() {
        clearPrompts()
        isEditing = true
        isAddingCategory = true
    }

    /// Une seule question ouverte à la fois : chaque nouvelle demande ferme la précédente.
    func clearPrompts() {
        renamingVault = nil
        renamingCategory = nil
        removingVault = nil
        movingVault = nil
        deletingCategory = nil
        stylingCategory = nil
        isAddingCategory = false
    }

    func reset() {
        finishEditing()
    }
}

/// Panneau affiché sous l'icône de la barre des menus. Tout s'y fait, sans autre fenêtre que le Finder.
struct PanelView: View {
    @EnvironmentObject private var store: VaultStore
    @EnvironmentObject private var actions: VaultActions
    @EnvironmentObject private var state: PanelState
    /// Au-delà, la liste défile.
    let maxListHeight: CGFloat

    @State private var listHeight: CGFloat = 320

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader()
            Divider()
            if let error = store.saveError {
                BannerView(banner: Banner(.error, "Liste non enregistrée", error), dismiss: nil)
                    .padding([.horizontal, .top], 12)
            }
            if let banner = actions.banner {
                BannerView(banner: banner) { actions.banner = nil }
                    .padding([.horizontal, .top], 12)
                    .transition(.opacity)
            }
            content
            Divider()
            PanelFooter()
        }
        .frame(width: panelWidth)
        .animation(.easeOut(duration: 0.15), value: actions.banner?.id)
    }

    @ViewBuilder private var content: some View {
        if store.vaults.isEmpty && store.categories.count == 1 && !state.isEditing {
            EmptyPanel()
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 10) {
                        if state.isEditing { EditingHint() }
                        ForEach(store.categories) { category in
                            CategoryCard(category: category)
                        }
                        if state.isEditing {
                            NewCategoryButton()
                                .id("nouvelle-categorie")
                        }
                    }
                    .padding(12)
                    .background(GeometryReader { geometry in
                        Color.clear.preference(key: ContentHeightKey.self, value: geometry.size.height)
                    })
                }
                .frame(height: min(listHeight, maxListHeight))
                .onPreferenceChange(ContentHeightKey.self) { listHeight = $0 }
                .onChange(of: state.isAddingCategory) { adding in
                    guard adding else { return }
                    DispatchQueue.main.async {
                        withAnimation { proxy.scrollTo("nouvelle-categorie", anchor: .bottom) }
                    }
                }
            }
        }
    }
}

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// MARK: - En-tête et pied de page

private struct PanelHeader: View {
    @EnvironmentObject private var store: VaultStore
    @EnvironmentObject private var state: PanelState

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LinearGradient(colors: [CategoryStyle.color(nil), .obsiVioletDeep],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 30, height: 30)
                .overlay(
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                )
                .shadow(color: Color.obsiViolet.opacity(0.35), radius: 3, y: 1)

            VStack(alignment: .leading, spacing: 1) {
                Text("ObsiVaults")
                    .font(.system(size: 14, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 8)

            if state.isEditing {
                AccentButton(title: "Terminé", systemImage: "checkmark") { finishEditing() }
                    .help("Revenir à la liste")
            } else {
                AccentButton(title: "Modifier", systemImage: "pencil", filled: false) { state.startEditing() }
                    .help("Renommer, colorer, ranger ou supprimer catégories et vaults")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            LinearGradient(colors: [Color.obsiViolet.opacity(0.20), Color.obsiViolet.opacity(0.04)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }

    private var subtitle: String {
        state.isEditing
            ? "Mode modification"
            : "\(countLabel(store.vaults.count, "vault", "vaults")) · "
                + countLabel(store.categories.count, "catégorie", "catégories")
    }

    /// Termine d'abord la saisie en cours, pour que le nom tapé soit enregistré.
    private func finishEditing() {
        NSApp.keyWindow?.makeFirstResponder(nil)
        DispatchQueue.main.async { state.finishEditing() }
    }
}

private struct PanelFooter: View {
    @EnvironmentObject private var store: VaultStore
    @EnvironmentObject private var actions: VaultActions
    @EnvironmentObject private var state: PanelState

    var body: some View {
        HStack(spacing: 6) {
            AccentButton(title: "Vault", systemImage: "plus") { actions.addVault(to: nil) }
                .help("Ajouter un dossier comme vault (ouvre le Finder)")
            AccentButton(title: "Catégorie", systemImage: "plus", filled: false) { state.startAddingCategory() }
                .help("Créer une catégorie")

            Spacer()

            Menu {
                Toggle("Ouvrir à la connexion", isOn: Binding(
                    get: { actions.launchesAtLogin },
                    set: { actions.setLaunchAtLogin($0) }))
                Menu("Importer les vaults d'Obsidian dans") {
                    ForEach(store.categories) { category in
                        Button(category.name) { actions.importFromObsidian(into: category.id) }
                    }
                }
                Button("Afficher la liste (config.json) dans le Finder") { actions.revealConfiguration() }
                Divider()
                Button("Quitter ObsiVaults") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Réglages")

            IconButton(systemImage: "power", help: "Quitter ObsiVaults", size: 13) { NSApp.terminate(nil) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

private struct EditingHint: View {
    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "hand.point.up.left.fill")
                .foregroundColor(.obsiViolet)
            Text("Clique sur un nom pour le changer, sur une pastille pour sa couleur et son icône. "
                 + "Les flèches changent l'ordre.")
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11))
        .foregroundColor(.secondary)
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.obsiViolet.opacity(0.08)))
    }
}

private struct EmptyPanel: View {
    @EnvironmentObject private var store: VaultStore
    @EnvironmentObject private var actions: VaultActions

    var body: some View {
        VStack(spacing: 10) {
            CategoryBadge(symbol: "books.vertical.fill", color: .obsiViolet, size: 44)
            Text("Aucun vault pour l'instant")
                .font(.system(size: 13, weight: .semibold))
            Text("Ajoute un dossier, ou récupère les vaults qu'Obsidian connaît déjà.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 6) {
                AccentButton(title: "Ajouter un dossier", systemImage: "plus") { actions.addVault(to: nil) }
                AccentButton(title: "Importer", systemImage: "square.and.arrow.down", filled: false) {
                    actions.importFromObsidian(into: store.categories[0].id)
                }
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Catégorie

private struct CategoryCard: View {
    let category: VaultCategory

    @EnvironmentObject private var store: VaultStore
    @EnvironmentObject private var actions: VaultActions
    @EnvironmentObject private var state: PanelState

    private var color: Color { CategoryStyle.color(category) }
    private var vaults: [Vault] { store.vaults(in: category.id) }
    private var index: Int { store.categories.firstIndex { $0.id == category.id } ?? 0 }
    private var isLast: Bool { index == store.categories.count - 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if state.isEditing { editingHeader } else { header }

            if state.isEditing && state.stylingCategory == category.id {
                StylePicker(category: category)
                    .padding(.vertical, 3)
            }
            if state.deletingCategory == category.id {
                DeleteCategoryPrompt(category: category)
                    .padding(.vertical, 3)
            }

            if vaults.isEmpty {
                HStack(spacing: 6) {
                    Text("Aucun vault")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    if !state.isEditing {
                        ChipButton(title: "Ajouter", systemImage: "plus", color: color) { actions.addVault(to: category.id) }
                    }
                }
                .padding(.leading, 31)
                .padding(.vertical, 4)
            } else {
                ForEach(Array(vaults.enumerated()), id: \.element.id) { offset, vault in
                    VaultRow(vault: vault, color: color, isFirst: offset == 0, isLast: offset == vaults.count - 1)
                }
            }

            if state.isEditing {
                ChipButton(title: "Ajouter un vault ici", systemImage: "plus", color: color) {
                    actions.addVault(to: category.id)
                }
                .padding(.leading, 4)
                .padding(.top, 3)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(color.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(color.opacity(0.25), lineWidth: 1))
    }

    private var header: some View {
        HStack(spacing: 8) {
            CategoryBadge(symbol: CategoryStyle.symbol(category), color: color)
            if state.renamingCategory == category.id {
                InlineNameField(initial: category.name, font: .system(size: 12.5, weight: .semibold), tint: color,
                                autoFocus: true,
                                commit: { actions.renameCategory(category.id, to: $0) },
                                finish: { state.renamingCategory = nil })
            } else {
                Text(category.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                CountPill(count: vaults.count, color: color)
                Spacer(minLength: 4)
                categoryMenu
            }
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
    }

    private var editingHeader: some View {
        HStack(spacing: 6) {
            Button {
                state.stylingCategory = state.stylingCategory == category.id ? nil : category.id
            } label: {
                CategoryBadge(symbol: CategoryStyle.symbol(category), color: color, size: 26)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "paintbrush.pointed.fill")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(color)
                            .padding(2.5)
                            .background(Circle().fill(Color(nsColor: .windowBackgroundColor)))
                            .offset(x: 4, y: 4)
                    }
            }
            .buttonStyle(.plain)
            .help("Couleur et icône de la catégorie")

            InlineNameField(initial: category.name, font: .system(size: 12.5, weight: .semibold), tint: color,
                            commit: { actions.renameCategory(category.id, to: $0) })

            IconButton(systemImage: "chevron.up", help: "Monter la catégorie") {
                actions.moveCategory(category.id, by: -1)
            }
            .disabled(index == 0)
            .opacity(index == 0 ? 0.3 : 1)
            IconButton(systemImage: "chevron.down", help: "Descendre la catégorie") {
                actions.moveCategory(category.id, by: 1)
            }
            .disabled(isLast)
            .opacity(isLast ? 0.3 : 1)
            IconButton(systemImage: "trash", help: store.categories.count == 1
                           ? "Il faut garder au moins une catégorie" : "Supprimer la catégorie",
                       color: .red) {
                state.clearPrompts()
                state.deletingCategory = category.id
            }
            .disabled(store.categories.count == 1)
            .opacity(store.categories.count == 1 ? 0.3 : 1)
        }
        .padding(.bottom, 2)
    }

    private var categoryMenu: some View {
        Menu {
            Button("Ajouter un vault ici…") { actions.addVault(to: category.id) }
            Button("Importer les vaults d'Obsidian ici") { actions.importFromObsidian(into: category.id) }
            Divider()
            Button("Renommer") {
                state.clearPrompts()
                state.renamingCategory = category.id
            }
            Button("Couleur et icône…") { state.startEditing(styling: category.id) }
            Button("Monter") { actions.moveCategory(category.id, by: -1) }
                .disabled(index == 0)
            Button("Descendre") { actions.moveCategory(category.id, by: 1) }
                .disabled(isLast)
            Divider()
            Button("Supprimer la catégorie…") {
                state.clearPrompts()
                state.deletingCategory = category.id
            }
            .disabled(store.categories.count == 1)
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 13))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Gérer la catégorie « \(category.name) »")
    }
}

private struct CountPill: View {
    let count: Int
    let color: Color

    var body: some View {
        Text("\(count)")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.16)))
    }
}

private struct StylePicker: View {
    let category: VaultCategory

    @EnvironmentObject private var actions: VaultActions
    @EnvironmentObject private var state: PanelState

    private var color: Color { CategoryStyle.color(category) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            label("Couleur")
            HStack(spacing: 5) {
                ForEach(CategoryStyle.swatches) { swatch in
                    let selected = swatch.key == category.color
                    Button { actions.setStyle(of: category.id, color: swatch.key) } label: {
                        Circle()
                            .fill(swatch.color)
                            .frame(width: 18, height: 18)
                            .overlay(
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .heavy))
                                    .foregroundColor(.white)
                                    .opacity(selected ? 1 : 0)
                            )
                            .overlay(Circle().strokeBorder(swatch.color.opacity(selected ? 0.5 : 0), lineWidth: 2)
                                .padding(-3))
                    }
                    .buttonStyle(.plain)
                    .help(swatch.name)
                }
            }
            .padding(.leading, 3)

            label("Icône")
                .padding(.top, 2)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 4), count: 7), alignment: .leading,
                      spacing: 4) {
                ForEach(CategoryStyle.symbols, id: \.self) { symbol in
                    let selected = symbol == category.symbol
                    Button { actions.setStyle(of: category.id, symbol: symbol) } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(selected ? .white : color)
                            .frame(width: 30, height: 24)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(selected ? color : color.opacity(0.12)))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Spacer()
                ChipButton(title: "OK", systemImage: "checkmark", color: color) { state.stylingCategory = nil }
            }
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.7)))
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundColor(.secondary)
    }
}

private struct DeleteCategoryPrompt: View {
    let category: VaultCategory

    @EnvironmentObject private var store: VaultStore
    @EnvironmentObject private var actions: VaultActions
    @EnvironmentObject private var state: PanelState
    @State private var destination: UUID?

    private var others: [VaultCategory] { store.categories.filter { $0.id != category.id } }

    var body: some View {
        let count = store.vaults(in: category.id).count
        VStack(alignment: .leading, spacing: 6) {
            Text("Supprimer « \(category.name) » ?")
                .font(.system(size: 12, weight: .semibold))
            if count == 0 {
                note("Elle ne contient aucun vault.")
            } else {
                HStack(spacing: 6) {
                    note(count == 1 ? "Son vault ira dans" : "Ses \(count) vaults iront dans")
                    Picker("", selection: $destination) {
                        ForEach(others) { other in
                            Text(other.name).tag(Optional(other.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .fixedSize()
                }
            }
            note("Aucun dossier n'est supprimé.")
            HStack(spacing: 6) {
                Spacer()
                ChipButton(title: "Annuler", systemImage: "xmark") { state.deletingCategory = nil }
                AccentButton(title: "Supprimer", systemImage: "trash", color: .red) {
                    state.deletingCategory = nil
                    actions.deleteCategory(category.id, movingVaultsTo: destination ?? others.first?.id)
                }
            }
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.red.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.red.opacity(0.3)))
        .onAppear { destination = others.first?.id }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct NewCategoryButton: View {
    @EnvironmentObject private var actions: VaultActions
    @EnvironmentObject private var state: PanelState
    @State private var isHovering = false

    var body: some View {
        if state.isAddingCategory {
            HStack(spacing: 8) {
                CategoryBadge(symbol: VaultStore.defaultSymbol, color: .obsiViolet)
                InlineNameField(initial: "", placeholder: "Nom de la nouvelle catégorie",
                                font: .system(size: 12.5, weight: .semibold), autoFocus: true,
                                commit: create,
                                finish: { state.isAddingCategory = false })
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.obsiViolet.opacity(0.08)))
            .overlay(dashedBorder)
        } else {
            Button { state.startAddingCategory() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text("Nouvelle catégorie")
                }
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(.obsiViolet)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.obsiViolet.opacity(isHovering ? 0.12 : 0.04)))
                .overlay(dashedBorder)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
        }
    }

    private var dashedBorder: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .strokeBorder(Color.obsiViolet.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
    }

    /// La nouvelle catégorie s'ouvre aussitôt sur le choix de sa couleur et de son icône.
    private func create(_ name: String) -> Bool {
        guard let category = actions.addCategory(named: name) else { return false }
        DispatchQueue.main.async { state.stylingCategory = category.id }
        return true
    }
}

// MARK: - Vault

private struct VaultRow: View {
    let vault: Vault
    let color: Color
    let isFirst: Bool
    let isLast: Bool

    @EnvironmentObject private var store: VaultStore
    @EnvironmentObject private var actions: VaultActions
    @EnvironmentObject private var state: PanelState
    @State private var isHovering = false

    private var available: Bool { store.isAvailable(vault) }
    private var otherCategories: [VaultCategory] { store.categories.filter { $0.id != vault.categoryID } }

    var body: some View {
        if state.removingVault == vault.id {
            removalPrompt
        } else if state.isEditing {
            editingRow
        } else {
            row
        }
    }

    // Liste : un clic ouvre le vault.
    private var row: some View {
        HStack(spacing: 8) {
            Image(systemName: available ? "book.closed.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundColor(available ? color : .orange)
                .frame(width: 16)
            if state.renamingVault == vault.id {
                InlineNameField(initial: vault.name, tint: color, autoFocus: true,
                                commit: { actions.rename(vault.id, to: $0) },
                                finish: { state.renamingVault = nil })
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text(vault.name)
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .foregroundColor(available ? .primary : .secondary)
                    if !available {
                        Text("Dossier introuvable")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                    }
                }
                Spacer(minLength: 4)
                if isHovering {
                    IconButton(systemImage: "folder", help: "Afficher dans le Finder") { actions.reveal(vault.id) }
                    vaultMenu
                }
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .frame(minHeight: 30)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(color.opacity(isHovering ? 0.18 : 0)))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture {
            if state.renamingVault != vault.id { actions.open(vault.id) }
        }
        .help(available ? VaultActions.shortPath(vault.path) : "Introuvable : \(VaultActions.shortPath(vault.path))")
    }

    private var vaultMenu: some View {
        Menu {
            Button("Ouvrir dans Obsidian") { actions.open(vault.id) }
            Button("Afficher dans le Finder") { actions.reveal(vault.id) }
            Divider()
            Button("Renommer") {
                state.clearPrompts()
                state.renamingVault = vault.id
            }
            Button("Changer le chemin…") { actions.changePath(vault.id) }
            Menu("Déplacer vers") {
                ForEach(otherCategories) { category in
                    Button { actions.move(vault.id, to: category.id) } label: {
                        Label(category.name, systemImage: CategoryStyle.symbol(category))
                    }
                }
            }
            .disabled(otherCategories.isEmpty)
            Button("Monter") { actions.move(vault.id, by: -1) }
                .disabled(isFirst)
            Button("Descendre") { actions.move(vault.id, by: 1) }
                .disabled(isLast)
            Divider()
            Button("Retirer de la liste…") {
                state.clearPrompts()
                state.removingVault = vault.id
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 13))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Gérer « \(vault.name) »")
    }

    // Mode modification : tout est visible et modifiable sur place.
    private var editingRow: some View {
        HStack(alignment: .center, spacing: 5) {
            VStack(spacing: 0) {
                IconButton(systemImage: "chevron.up", help: "Monter", size: 9) { actions.move(vault.id, by: -1) }
                    .disabled(isFirst)
                    .opacity(isFirst ? 0.25 : 1)
                IconButton(systemImage: "chevron.down", help: "Descendre", size: 9) { actions.move(vault.id, by: 1) }
                    .disabled(isLast)
                    .opacity(isLast ? 0.25 : 1)
            }

            VStack(alignment: .leading, spacing: 5) {
                InlineNameField(initial: vault.name, tint: color, commit: { actions.rename(vault.id, to: $0) })
                Text(available ? VaultActions.shortPath(vault.path) : "Introuvable : \(VaultActions.shortPath(vault.path))")
                    .font(.system(size: 10))
                    .foregroundColor(available ? .secondary : .orange)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.leading, 6)
                    .help(vault.path)
                HStack(spacing: 5) {
                    ChipButton(title: "Changer le chemin", systemImage: "folder",
                               color: available ? .secondary : .orange) { actions.changePath(vault.id) }
                        .help("Choisir un autre dossier dans le Finder")
                    ChipButton(title: "Déplacer", systemImage: "arrow.turn.down.right", color: color) {
                        let opening = state.movingVault != vault.id
                        state.clearPrompts()
                        state.movingVault = opening ? vault.id : nil
                    }
                    .help("Changer de catégorie")
                }
                if state.movingVault == vault.id { moveChoices }
            }

            IconButton(systemImage: "trash", help: "Retirer de la liste", color: .red) {
                state.clearPrompts()
                state.removingVault = vault.id
            }
        }
        .padding(.vertical, 5)
        .padding(.trailing, 2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55)))
    }

    private var moveChoices: some View {
        VStack(alignment: .leading, spacing: 4) {
            if otherCategories.isEmpty {
                Text("Crée d'abord une autre catégorie.")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
            } else {
                Text("Déplacer vers :")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                FlowLayout(spacing: 5) {
                    ForEach(otherCategories) { category in
                        CategoryChip(category: category) {
                            state.movingVault = nil
                            actions.move(vault.id, to: category.id)
                        }
                    }
                }
            }
        }
    }

    private var removalPrompt: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Retirer « \(vault.name) » de la liste ?")
                .font(.system(size: 12, weight: .semibold))
            Text("Le dossier reste sur le disque, et Obsidian le garde dans sa liste.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Spacer()
                ChipButton(title: "Annuler", systemImage: "xmark") { state.removingVault = nil }
                AccentButton(title: "Retirer", systemImage: "minus.circle.fill", color: .red) {
                    state.removingVault = nil
                    actions.remove(vault.id)
                }
            }
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.red.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.red.opacity(0.3)))
    }
}

private struct CategoryChip: View {
    let category: VaultCategory
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        let color = CategoryStyle.color(category)
        Button(action: action) {
            HStack(spacing: 4) {
                CategoryBadge(symbol: CategoryStyle.symbol(category), color: color, size: 15)
                Text(category.name)
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.leading, 3)
            .padding(.trailing, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(isHovering ? 0.28 : 0.15)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Déplacer vers « \(category.name) »")
    }
}

// MARK: - Bandeau

struct BannerView: View {
    let banner: Banner
    /// `nil` : le bandeau ne peut pas être fermé.
    let dismiss: (() -> Void)?

    private var tint: Color {
        switch banner.kind {
        case .info: return .blue
        case .success: return .green
        case .question, .progress: return .obsiViolet
        case .warning: return .orange
        case .error: return .red
        }
    }

    private var symbol: String {
        switch banner.kind {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .question, .progress: return "questionmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if banner.kind == .progress {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 14))
                    .foregroundColor(tint)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(banner.title)
                    .font(.system(size: 12, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let message = banner.message {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !banner.actions.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(banner.actions) { action in
                            AccentButton(title: action.title, systemImage: action.systemImage,
                                         color: action.isDestructive ? .red : tint) {
                                dismiss?()
                                action.run()
                            }
                        }
                        if banner.kind == .question, let dismiss {
                            ChipButton(title: "Annuler", systemImage: "xmark", action: dismiss)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
            if banner.kind != .progress, let dismiss {
                IconButton(systemImage: "xmark", help: "Fermer", size: 9, action: dismiss)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(tint.opacity(0.3)))
    }
}

// MARK: - Mise en page

/// Place ses éléments en ligne et passe à la ligne quand la largeur manque.
struct FlowLayout: Layout {
    var spacing: CGFloat = 5

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
