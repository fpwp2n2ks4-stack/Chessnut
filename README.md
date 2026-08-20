# Chessnut

Application macOS pour jouer contre un moteur UCI **exclusivement sur un échiquier
physique Chessnut** (Air, Air+, Go, Pro) via Bluetooth.

> A macOS app to play against a UCI engine **exclusively on a physical Chessnut
> board** (Air, Air+, Go, Pro) over Bluetooth.

---

## 🇫🇷 Français

### Fonctionnalités

- **Échiquier physique uniquement** : détection, connexion Bluetooth et flux de
  position en temps réel (pas de clic-souris, vous jouez sur le plateau).
- **Moteurs UCI** : ajout / suppression de moteurs (binaire), récupération et
  modification des paramètres UCI (`check`, `spin`, `combo`, `string`, `button`).
- **Cadences** indépendantes pour le joueur et le moteur (1s à 60 min, avec ou
  sans incrément).
- **Couleurs** : Blancs / Noirs, avec alternance automatique des couleurs sur
  plusieurs parties.
- **Séries de parties** (1 à 10) avec score cumulé.
- **LED de guidage** sur l'échiquier pour indiquer le coup du moteur.
- **Analyse en direct** du moteur (profondeur, score, variante) dans le bandeau
  du plateau.
- **Alertes sonores et visuelles** : échec au roi, échec et mat, pat et coup
  interdit (avec explication quand le coup laisse le roi en échec).
- **Interface français / anglais**, langue réglable (défaut : langue du système).

### Prérequis

- macOS 13 (Ventura) ou ultérieur.
- [Swift 5.9+](https://www.swift.org/) / Swift Package Manager.
- Un échiquier Chessnut (Air, Air+, Go ou Pro) allumé.
- Autorisation Bluetooth accordée à l'application (demandée au premier lancement).

### Compilation et lancement

```bash
./build-app.sh     # compile en release et empaquette ChessnutAir.app
open ChessnutAir.app
```

Au premier lancement, acceptez l'accès Bluetooth. Connectez l'échiquier avec le
bouton « Scanner », puis ajoutez un moteur UCI avec « Ajouter un moteur »
(sélectionnez le binaire, par ex. `stockfish`).

### Utilisation

1. **Scanner** pour trouver l'échiquier, puis **Connecter**.
2. **Ajouter un moteur** UCI (le nom apparaît alors dans le menu déroulant).
3. Choisissez les **cadences**, la **couleur** et le **nombre de parties**.
4. **Démarrer**. Remettez les pièces en position de départ quand demandé, puis
   jouez vos coups sur l'échiquier : le moteur répond et ses LED indiquent son coup.

### Structure du projet

| Fichier | Rôle |
| --- | --- |
| `ChessnutBoard.swift` | Pilote Bluetooth (Core Bluetooth) de l'échiquier Chessnut |
| `PlayController.swift` | Orchestration d'une partie (flux FEN, horloges, fin de partie) |
| `ChessGame.swift` | Règles, FEN, détection des coups, coups légaux |
| `Engine.swift` / `EngineManager.swift` | Moteur UCI (processus) et persistance de la liste |
| `EngineOptionsView.swift` | Édition des options UCI du moteur |
| `ChessBoardView.swift` | Rendu SwiftUI de l'échiquier + bandeau d'analyse |
| `PlayView.swift` | Panneau de commandes (connexion, moteur, cadences, actions) |
| `Localization.swift` | Traductions français / anglais |
| `build-app.sh` | Compilation release + empaquetage `ChessnutAir.app` (Info.plist Bluetooth) |

### Licence

Distribué sous [licence MIT](LICENSE).

### Remerciements

Ce projet s'appuie sur l'API officielle des échiquiers Chessnut, disponible à
l'adresse : <https://github.com/chessnutech/EasyLinkSDK>

---

## 🇬🇧 English

### Features

- **Physical board only**: Bluetooth detection, connection and real-time position
  stream (no mouse input — you play on the board).
- **UCI engines**: add / remove engines (binary), fetch and edit UCI options
  (`check`, `spin`, `combo`, `string`, `button`).
- Independent **time controls** for the player and the engine (1s to 60 min, with
  or without increment).
- **Colors**: White / Black, with automatic color alternation over several games.
- **Game series** (1 to 10 games) with cumulative score.
- **Guide LEDs** on the board to show the engine's move.
- **Live analysis** from the engine (depth, score, principal variation) in the
  board's status bar.
- **Sound and visual alerts**: check, checkmate, stalemate and illegal move (with
  an explanation when the move leaves your king in check).
- **French / English UI**, switchable (defaults to the system language).

### Requirements

- macOS 13 (Ventura) or later.
- [Swift 5.9+](https://www.swift.org/) / Swift Package Manager.
- A Chessnut board (Air, Air+, Go or Pro), powered on.
- Bluetooth permission granted to the app (prompted on first launch).

### Build & run

```bash
./build-app.sh     # release build + ChessnutAir.app packaging
open ChessnutAir.app
```

On first launch, accept the Bluetooth permission. Find your board with the
**Scan** button, then add a UCI engine with **Add engine** (pick the binary,
e.g. `stockfish`).

### Usage

1. **Scan** to find the board, then **Connect**.
2. **Add an engine** (it then appears in the dropdown).
3. Pick the **time controls**, the **color** and the **number of games**.
4. **Start**. Place the pieces in the starting position when asked, then play
   your moves on the board: the engine replies and its LEDs show its move.

### Project layout

| File | Purpose |
| --- | --- |
| `ChessnutBoard.swift` | Bluetooth driver (Core Bluetooth) for the Chessnut board |
| `PlayController.swift` | Game orchestration (FEN stream, clocks, game end) |
| `ChessGame.swift` | Rules, FEN, move detection, legal moves |
| `Engine.swift` / `EngineManager.swift` | UCI engine (process) and engine list persistence |
| `EngineOptionsView.swift` | UCI engine option editing |
| `ChessBoardView.swift` | SwiftUI board rendering + analysis bar |
| `PlayView.swift` | Controls panel (connection, engine, time, actions) |
| `Localization.swift` | French / English translations |
| `build-app.sh` | Release build + `ChessnutAir.app` packaging (Bluetooth Info.plist) |

### License

Released under the [MIT license](LICENSE).

### Acknowledgements

This project is based on the official Chessnut board API, available at:
<https://github.com/chessnutech/EasyLinkSDK>
