# ObsiVaults — tes vaults Obsidian dans la barre des menus

ObsiVaults est une petite app macOS qui vit dans la barre des menus. Un clic sur son icône (des livres) ouvre un panneau coloré avec tous tes vaults Obsidian, rangés dans tes propres catégories ; un clic sur un vault l'ouvre dans Obsidian.

Tout se gère depuis ce panneau, sans autre fenêtre : catégories (nom, couleur, icône, ordre), vaults (nom affiché, catégorie, ordre, dossier). Seul le Finder s'ouvre, pour choisir un dossier. L'app retrouve un dossier déplacé ou un disque externe qui a changé de nom, et inscrit elle-même dans Obsidian les dossiers qu'il ne connaît pas encore.

<!-- EMPLACEMENT CAPTURE
     Déposer une capture du panneau dans img/panneau.png et une du mode modification dans
     img/modification.png, puis décommenter ce bloc.

<p align="center">
  <img src="img/panneau.png" width="45%" />
  <img src="img/modification.png" width="45%" />
</p>
-->

---

## Installation

Il faut **macOS 13 (Ventura) ou plus récent** et les outils de compilation d'Apple. S'ils manquent, `xcode-select --install` les installe (Xcode complet n'est pas nécessaire).

Dans le Terminal, depuis ce dossier :

```bash
./build.sh --install
```

Le script compile l'app, la copie dans `/Applications` puis affiche la commande pour la lancer. Sans `--install`, l'app est seulement créée dans `build/ObsiVaults.app`.

Copie l'app dans Applications avant d'activer **Ouvrir à la connexion** : macOS retient l'emplacement de l'app au moment où l'option est cochée.

> **Si macOS bloque l'app** (cela arrive quand elle a été copiée depuis un autre Mac ou téléchargée, car elle n'est pas signée par un développeur Apple) : clic droit sur `ObsiVaults.app` → **Ouvrir**, ou dans le Terminal `xattr -cr /Applications/ObsiVaults.app`.

## Premier lancement

Au premier lancement, ObsiVaults récupère tous les vaults qu'Obsidian connaît déjà et les met dans la catégorie **« Non classés »**. Le panneau s'ouvre tout seul avec un mot d'accueil.

Deux vaults dont les dossiers portent le même nom reçoivent le nom de leur dossier parent, par exemple `Obsidian (iCloud)` et `Obsidian (Bio-informatique)`. Tu peux ensuite les renommer comme tu veux.

## Utilisation

### Le panneau

- **En haut** : le nombre de vaults et de catégories, et le bouton **Modifier**.
- **Au milieu** : une carte colorée par catégorie, avec sa pastille (couleur + icône) et ses vaults.
  - **Clic sur un vault** : il s'ouvre dans Obsidian et le panneau se referme.
  - **Survol d'un vault** : 📁 l'affiche dans le Finder, **⋯** ouvre toutes ses actions (renommer, changer le chemin, déplacer vers une autre catégorie, monter, descendre, retirer).
  - **⋯ d'une catégorie** : ajouter un vault ici, importer les vaults d'Obsidian ici, renommer, couleur et icône, monter, descendre, supprimer.
  - **Vault avec ⚠ orange** : son dossier est introuvable (disque externe débranché, dossier supprimé). Un clic explique le problème et propose **Changer le chemin…**.
- **En bas** :
  - **＋ Vault** ouvre le Finder pour choisir un dossier et sa catégorie ;
  - **＋ Catégorie** crée une catégorie ;
  - ⚙︎ : **Ouvrir à la connexion**, importer les vaults d'Obsidian, afficher la liste (`config.json`) dans le Finder ;
  - ⏻ quitte l'app.

Les messages (vault ajouté, dossier introuvable, erreur…) s'affichent en bandeau en haut du panneau, jamais dans une fenêtre à part.

Relancer l'app alors qu'elle tourne déjà (double-clic dans Applications) ouvre aussi le panneau.

### Le mode modification

**Modifier** passe tout le panneau en édition ; **Terminé** revient à la liste. Les noms se valident avec ↩ ou en cliquant ailleurs, Échap annule.

| Pour… | Fais… |
|---|---|
| Créer une catégorie | **＋ Catégorie** en bas, ou **Nouvelle catégorie** en fin de liste ; tape son nom puis ↩ |
| Renommer une catégorie ou un vault | clique dans son nom et tape le nouveau |
| Changer la couleur et l'icône d'une catégorie | clique sur sa pastille (petit pinceau) : 11 couleurs, 28 icônes |
| Réordonner | flèches ˄ ˅ à côté de la catégorie ou du vault |
| Supprimer une catégorie | 🗑 rouge de la catégorie ; ses vaults vont dans la catégorie choisie sous la question |
| Ajouter un vault à une catégorie | **＋ Ajouter un vault ici** en bas de la carte |
| Changer le dossier d'un vault | **Changer le chemin** (ouvre le Finder) ; le chemin actuel est écrit juste au-dessus |
| Changer un vault de catégorie | **Déplacer**, puis clic sur la catégorie voulue |
| Retirer un vault de la liste | 🗑 rouge du vault, puis **Retirer** |

L'ordre des catégories et des vaults est celui du panneau. Chaque modification est enregistrée aussitôt.

### Ce que l'app ne fait jamais

- **Renommer ne touche pas au dossier** : seul le nom affiché dans ObsiVaults change. Le sélecteur de vaults d'Obsidian continue d'afficher le nom du dossier.
- **Retirer un vault ou supprimer une catégorie ne supprime aucun fichier**, et ne retire rien de la liste d'Obsidian.

## Comment ObsiVaults ouvre un vault

Obsidian ouvre un vault avec un lien `obsidian://open?vault=<identifiant>`, à condition que le vault figure dans sa liste (`~/Library/Application Support/obsidian/obsidian.json`).

- **Si Obsidian connaît le dossier**, ObsiVaults ouvre simplement ce lien.
- **Sinon**, ObsiVaults inscrit le dossier dans `obsidian.json`, puis ouvre le lien. Avant chaque modification, la liste d'Obsidian est copiée dans `obsidian.json.bak`, dans le même dossier.
- **Si Obsidian est ouvert à ce moment-là**, un bandeau du panneau demande d'abord la permission de le fermer quelques secondes (**Fermer et ouvrir**). En quittant, Obsidian réécrit sa liste avec ce qu'il a en mémoire, et effacerait l'inscription. Obsidian se rouvre ensuite directement sur le vault.

Après un changement de chemin, la première ouverture inscrit le nouveau dossier de la même façon. L'ancienne entrée reste dans la liste d'Obsidian, sans gêner.

## Réglages et sauvegarde

Tout est dans `~/Library/Application Support/ObsiVaults/` :

| Fichier | Contenu |
|---|---|
| `config.json` | catégories (nom, couleur, icône), vaults, noms affichés, chemins |
| `config.json.bak` | la version précédente, refaite à chaque modification |
| `config.illisible.json` | n'existe que si `config.json` a été abîmé : il est mis de côté et la version précédente est restaurée |

- **Sauvegarder ou transférer ta liste sur un autre Mac** : copie `config.json`. Les chemins doivent être les mêmes sur l'autre Mac ; sinon, utilise « Changer le chemin ».
- **Repartir de zéro** : quitte ObsiVaults, supprime `config.json`, relance. L'app réimporte les vaults d'Obsidian comme au premier lancement.

Pour retrouver un dossier déplacé ou renommé, ou un disque externe qui a changé de nom, ObsiVaults garde un signet macOS de chaque dossier (le champ `bookmark` de `config.json`).

## Dépannage

- **L'icône n'apparaît pas dans la barre des menus.** Sur un MacBook à encoche, une barre trop remplie cache des icônes sous l'encoche. ObsiVaults se place volontairement loin à droite de l'encoche au premier lancement. Si elle reste cachée, retire d'autres icônes (⌘ + glisser hors de la barre). Avec un gestionnaire de barre des menus (Thaw, Ice, Bartender…), elle peut aussi atterrir dans sa section masquée : ramène-la dans la section visible. Relancer l'app ouvre le panneau dans tous les cas.
- **« Obsidian ne s'est pas fermé »** : ferme Obsidian toi-même (⌘Q), puis rouvre le vault depuis le panneau.
- **Ouvrir à la connexion ne se coche pas** : macOS peut demander une validation dans *Réglages Système → Général → Ouverture* ; ObsiVaults ouvre ce panneau quand c'est nécessaire.

## Développement

```
obsidian-launcher/
├── build.sh                 compile build/ObsiVaults.app (--install : copie dans /Applications)
├── Resources/
│   ├── Info.plist           identifiant fr.arthur.obsivaults, pas d'icône dans le Dock
│   └── AppIcon.icns         icône, régénérable avec scripts/make_icon.sh
├── Sources/
│   ├── AppDelegate.swift      démarrage, menus d'édition (⌘C/⌘V…), une seule copie à la fois
│   ├── MenuBarController.swift  icône de la barre et panneau (NSPopover)
│   ├── PanelView.swift        contenu du panneau (SwiftUI) : cartes, mode modification, bandeaux
│   ├── Theme.swift            couleurs, icônes des catégories, boutons
│   ├── VaultActions.swift     actions du panneau, bandeaux, sélecteur du Finder
│   ├── VaultOpener.swift      ouverture dans Obsidian (fermeture, inscription, lien)
│   ├── VaultStore.swift       catégories, vaults, config.json, signets
│   └── ObsidianRegistry.swift lecture et écriture de obsidian.json
├── Tests/main.swift         tests de VaultStore et ObsidianRegistry
└── scripts/
    ├── run_tests.sh         compile et lance les tests (dans un dossier temporaire)
    ├── make_icon.sh         régénère Resources/AppIcon.icns
    └── make_icon.swift
```

- **Tests** : `./scripts/run_tests.sh`. Ils travaillent sur des copies dans un dossier temporaire, sans toucher ni à ta liste ni à Obsidian.
- **Essayer l'app avec une autre liste** que la tienne :
  ```bash
  OBSIVAULTS_CONFIG_DIR=/tmp/obsivaults-essai build/ObsiVaults.app/Contents/MacOS/ObsiVaults
  ```
  La liste de l'app est alors lue et écrite dans ce dossier. La liste d'Obsidian reste la vraie.
- **Signature** : `build.sh` signe l'app en ad hoc, sans certificat. Le Bureau étant synchronisé par iCloud Drive, le système remet parfois sur l'app des attributs que `codesign` refuse : le script les efface et réessaie tout seul.
