import SwiftUI

/// Largeur du panneau de la barre des menus.
let panelWidth: CGFloat = 340

extension Color {
    /// Violet d'Obsidian, repris de l'icône de l'app.
    static let obsiViolet = Color(red: 0.486, green: 0.227, blue: 0.929)
    static let obsiVioletDeep = Color(red: 0.298, green: 0.114, blue: 0.584)
}

/// Couleurs et icônes proposées pour les catégories.
enum CategoryStyle {
    struct Swatch: Identifiable {
        let key: String
        let name: String
        let color: Color
        var id: String { key }
    }

    private static let palette: [String: (name: String, color: Color)] = [
        "violet": ("Violet", Color(red: 0.545, green: 0.361, blue: 0.965)),
        "indigo": ("Indigo", Color(red: 0.388, green: 0.400, blue: 0.945)),
        "bleu": ("Bleu", Color(red: 0.231, green: 0.510, blue: 0.965)),
        "turquoise": ("Turquoise", Color(red: 0.078, green: 0.690, blue: 0.620)),
        "vert": ("Vert", Color(red: 0.133, green: 0.725, blue: 0.369)),
        "jaune": ("Jaune", Color(red: 0.900, green: 0.680, blue: 0.030)),
        "orange": ("Orange", Color(red: 0.976, green: 0.451, blue: 0.086)),
        "rouge": ("Rouge", Color(red: 0.937, green: 0.267, blue: 0.267)),
        "rose": ("Rose", Color(red: 0.925, green: 0.282, blue: 0.600)),
        "marron": ("Marron", Color(red: 0.620, green: 0.420, blue: 0.260)),
        "gris": ("Gris", Color(red: 0.392, green: 0.455, blue: 0.545)),
    ]

    /// Dans l'ordre du sélecteur, défini par `VaultStore.colorKeys`.
    static let swatches: [Swatch] = VaultStore.colorKeys.compactMap { key in
        palette[key].map { Swatch(key: key, name: $0.name, color: $0.color) }
    }

    static func color(_ category: VaultCategory?) -> Color {
        category?.color.flatMap { palette[$0]?.color } ?? .obsiViolet
    }

    static func symbol(_ category: VaultCategory?) -> String {
        category?.symbol ?? VaultStore.defaultSymbol
    }

    /// Icônes du sélecteur, toutes disponibles depuis macOS 13.
    static let symbols = [
        "folder.fill", "tray.fill", "archivebox.fill", "books.vertical.fill", "book.closed.fill",
        "graduationcap.fill", "briefcase.fill", "doc.text.fill", "pencil", "paintpalette.fill",
        "film.fill", "camera.fill", "music.note", "gamecontroller.fill", "flask.fill",
        "atom", "leaf.fill", "brain.head.profile", "lightbulb.fill", "chart.bar.fill",
        "terminal.fill", "globe.europe.africa.fill", "house.fill", "person.2.fill", "heart.fill",
        "star.fill", "airplane", "cart.fill",
    ]
}

/// Pastille arrondie de couleur avec une icône blanche : identité visuelle d'une catégorie.
struct CategoryBadge: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(LinearGradient(colors: [color.opacity(0.85), color], startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundColor(.white)
            )
    }
}

/// Bouton plein, texte blanc, légèrement éclairci au survol (repris de SNCF Wifi).
struct AccentButton: View {
    let title: String
    let systemImage: String
    var color: Color = .obsiViolet
    var filled = true
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .bold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(filled ? .white : color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(filled ? color : color.opacity(isHovering ? 0.22 : 0.14))
                    .brightness(filled && isHovering ? 0.08 : 0)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

/// Petit bouton icône, avec un fond discret au survol.
struct IconButton: View {
    let systemImage: String
    let help: String
    var color: Color = .secondary
    var size: CGFloat = 12
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .medium))
                .foregroundColor(color)
                .frame(width: size + 12, height: size + 10)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.primary.opacity(isHovering ? 0.10 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .onHover { isHovering = $0 }
    }
}

/// Petit bouton texte arrondi, teinté d'une couleur (actions secondaires des lignes).
struct ChipButton: View {
    let title: String
    let systemImage: String
    var color: Color = .secondary
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .semibold))
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundColor(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(isHovering ? 0.20 : 0.11)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { isHovering = $0 }
    }
}

/// Champ de nom modifiable sur place : valide avec ↩ ou en cliquant ailleurs, annule avec Échap.
struct InlineNameField: View {
    let initial: String
    var placeholder = "Nom"
    var font: Font = .system(size: 13)
    var tint: Color = .obsiViolet
    var autoFocus = false
    /// Renvoie faux si le nom est refusé : le champ reprend alors l'ancien nom.
    let commit: (String) -> Bool
    var finish: () -> Void = {}

    @State private var text = ""
    /// Dernier nom validé : ↩ puis la perte du focus ne doivent l'enregistrer qu'une fois.
    @State private var saved: String?
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(font)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(focused ? 1 : 0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(focused ? tint : Color.primary.opacity(0.12), lineWidth: focused ? 1.5 : 1)
            )
            .focused($focused)
            .onAppear {
                text = initial
                if autoFocus { DispatchQueue.main.async { focused = true } }
            }
            .onChange(of: initial) {
                text = $0
                saved = nil
            }
            .onSubmit { save() }
            // Sortie du mode modification ou fermeture du panneau pendant la saisie : le nom tapé est gardé.
            .onDisappear { save() }
            .onChange(of: focused) { isFocused in
                if !isFocused { save() }
            }
            .onExitCommand {
                text = initial
                finish()
            }
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != initial, trimmed != saved {
            if commit(trimmed) { saved = trimmed } else { text = initial }
        }
        finish()
    }
}

/// Nombre suivi du nom accordé : « 1 vault », « 3 vaults ».
func countLabel(_ count: Int, _ singular: String, _ plural: String) -> String {
    "\(count) \(count > 1 ? plural : singular)"
}
