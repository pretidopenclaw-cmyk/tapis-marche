# tapis-marche

Exploiter mon tapis de marche sans passer par l'application du fabricant :
récupérer et conserver l'historique des séances, et trouver d'autres façons de s'en servir.

## Tapis Marche (app macOS)

App de barre de menus qui se connecte seule au WalkingPad Z1 (`KS-HD-Z1E`) en Bluetooth,
enregistre chaque marche en local et l'envoie dans Notion, avec un récap chaque semaine.
Elle pilote aussi la bande (vitesse au démarrage, arrêt quand tu descends, menu, liens, Raycast) via les seules
commandes FTMS standard ; elle ne démarre jamais la bande d'elle-même.

- Conception : `docs/superpowers/specs/2026-11-16-journal-marches-design.md`, `docs/superpowers/specs/2026-11-16-pilotage-tapis-design.md`
- Plan : `docs/superpowers/plans/2026-11-16-journal-marches.md`

### Commandes

| Commande | Effet |
|---|---|
| `make test` | tests du package `WalkingPadKit` (`swift test`) |
| `make build` | génère le projet XcodeGen et compile l'app (Release) dans `build/` |
| `make install` | copie l'app dans `/Applications` |
| `make run` | lance l'app compilée |

Prérequis : Xcode 26+, XcodeGen, certificat « Apple Development » de l'équipe `HFVC9G5X5R`.

### Brancher Notion

1. Sur <https://www.notion.so/profile/integrations>, crée une intégration interne et copie son jeton.
2. Dans Notion, ouvre la page qui accueillera le journal, menu `…` › Connexions › ajoute l'intégration.
3. Dans l'app : menu › Réglages… › colle le jeton et l'URL de la page › « Connecter Notion ».
   L'app crée la base « Marches » et la page « Récaps hebdo » sous cette page.

Le jeton reste dans le Trousseau macOS ; il n'est écrit dans aucun fichier.

### Piloter le tapis

- **Automatique** : à chaque démarrage (télécommande, Mac ou Raycast), la bande passe à la vitesse préférée
  (2,0 km/h par défaut) ; elle s'arrête seule après 10 s sans pas (15 s de délai après un démarrage).
  Réglages › Tapis : vitesse au démarrage, « Arrêter quand je descends ».
- **Menu** : « Démarrer le tapis », « Arrêter le tapis », « Plus vite », « Moins vite » (± 0,5 km/h).
- **Liens** : `open -g "tapismarche://demarrer"`, `…/arreter`, `…/vitesse/2,5`, `…/plus-vite`, `…/moins-vite`.
  Si le tapis n'est pas encore connecté, la commande attend 10 s puis une notification « Tapis introuvable » s'affiche.

#### Raycast

1. Raycast › Settings › Extensions › **Script Commands** › **Add Directories** › choisis `~/repo/tapis-marche/raycast`.
2. Les commandes « Démarrer le tapis », « Arrêter le tapis », « Vitesse du tapis » (demande les km/h),
   « Tapis plus vite », « Tapis moins vite » apparaissent dans Raycast.
3. Pour un raccourci clavier : sélectionne la commande dans Raycast › ⌘K › **Configure Command** › Hotkey
   (suggestion : ⌥⌘↑ démarrer, ⌥⌘↓ arrêter).

### À savoir

- Le tapis n'accepte qu'une connexion à la fois. Pour utiliser KS Fit, menu ›
  « Libérer le tapis pour KS Fit (15 min) ».
- Une séance se ferme après 3 minutes à l'arrêt ; une séance de moins de 2 min et 100 m est ignorée.
- Le journal local : `~/Library/Application Support/TapisMarche/journal.sqlite`.
- Logs : `/usr/bin/log show --last 10m --info --predicate 'subsystem == "ch.davidpreti.TapisMarche"'`.

## Repères

- `spike/walkingpad_probe.py` : sonde Bluetooth jetable du 2026-11-16 (lecture seule).
- Les données de séances ne sont pas versionnées (`data/` est ignoré).
