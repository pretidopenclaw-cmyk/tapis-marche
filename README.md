# tapis-marche

Exploiter mon tapis de marche sans passer par l'application du fabricant :
récupérer et conserver l'historique des séances, et trouver d'autres façons de s'en servir.

## Tapis Marche (app macOS)

App de barre de menus qui se connecte seule au WalkingPad Z1 (`KS-HD-Z1E`) en Bluetooth,
enregistre chaque marche en local et l'envoie dans Notion, avec un récap chaque semaine.
Lecture seule : l'app n'envoie jamais de commande au tapis.

- Conception : `docs/superpowers/specs/2026-11-16-journal-marches-design.md`
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

### À savoir

- Le tapis n'accepte qu'une connexion à la fois. Pour utiliser KS Fit, menu ›
  « Libérer le tapis pour KS Fit (15 min) ».
- Une séance se ferme après 3 minutes à l'arrêt ; une séance de moins de 2 min et 100 m est ignorée.
- Le journal local : `~/Library/Application Support/TapisMarche/journal.sqlite`.
- Logs : `/usr/bin/log show --last 10m --info --predicate 'subsystem == "ch.davidpreti.TapisMarche"'`.

## Repères

- `spike/walkingpad_probe.py` : sonde Bluetooth jetable du 2026-11-16 (lecture seule).
- Les données de séances ne sont pas versionnées (`data/` est ignoré).
