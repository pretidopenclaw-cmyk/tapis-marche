# Journal automatique des marches — app macOS barre de menus

Date : 2026-11-16 · Statut : brouillon, à valider par David

## Intention

David marche sur un WalkingPad Z1 (KingSmith, nom BLE `KS-HD-Z1E`) sous son bureau, pendant qu'il travaille.
Le tapis ne garde aucun historique (seule la dernière séance, effacée à la coupure de courant) et David ne veut plus dépendre de l'app KS Fit.
Il veut **ne plus perdre une seule marche** : chaque séance est captée sans y penser et atterrit dans Notion, où il tient déjà ses revues ; un récap hebdo lui montre sa semaine.
Le projet est choisi comme base des pistes suivantes (vitesse pilotée par l'agenda, heatmap « km en codant », doc Z1 open source).

## Ce que la sonde a établi (spike du 2026-11-16, `spike/walkingpad_probe.py`)

- Le Z1 annonce le service FTMS `0x1826` et se laisse connecter depuis le Mac (CoreBluetooth via bleak).
- **Treadmill Data (`0x2ACD`) notifie à 1 Hz sans aucune poignée de main propriétaire**, contrairement à ce que dit la communauté — vérifié **tapis à l'arrêt uniquement**.
- Trame de 17 octets, flags `0x2484` : vitesse instantanée (uint16, 0,01 km/h), distance totale (uint24, m), énergie (5 octets), temps écoulé (uint16, s), puis 3 octets d'extension KingSmith sous le bit 13, présumés être les **pas** (uint24 LE) — **non confirmé** en marche.
- Services propriétaires présents mais muets en lecture passive : `fff0`, `ffe0`, `24e2521c-…`, `02f00000-…fe00`.
- Une seule connexion BLE à la fois : quand l'app tient le tapis, KS Fit ne peut pas s'y connecter (et inversement). Un tapis connecté n'émet plus d'annonces.

## Résultats de la marche-test (2026-11-16, 15:21 → 15:33, captés par l'app elle-même)

- Connexion et notifications `0x2ACD` sans poignée de main **aussi en marche** : 651 trames, écart max 1,16 s (moy. 1,006 s), aucune perte sur 11 min.
- **Pas confirmés** : extension bit 13 = uint24 LE, ≈ 1 pas/s à 1,5 km/h (148 → 652).
- **Distance par paliers de 10 m** (70, 80, 90…) : précision de ±10 m par séance, sans effet sur les règles.
- Temps écoulé (`elapsedS`) et énergie (`kcal`) remontés ; le temps se fige pendant la pause.
- **Pause de bande de 2 min** (vitesse 0 de 15:31:12 à 15:33:17) : les compteurs se figent puis reprennent **sans remise à zéro** ; aucun compteur n'a décru sur toute la marche. La remise à zéro après extinction du tapis reste non observée (la règle « incrément = valeur courante » la couvre).

## Objectifs

1. Dès que le Z1 est allumé et à portée, l'app s'y connecte seule et enregistre la séance — zéro action de David.
2. Chaque séance terminée apparaît dans une base Notion « Marches » (une ligne par séance) en quelques minutes.
3. Chaque semaine, une page de récap Notion (totaux, meilleur jour, répartition par jour).
4. La barre de menus montre l'état en direct (connecté / en marche, vitesse, pas et km du jour).

## Non-objectifs (v1)

- Piloter le tapis (démarrer, vitesse) : lecture seule. Le pilotage est la piste 2, plus tard.
- Apple Health, app iOS, Watch.
- Plusieurs tapis, plusieurs utilisateurs.
- Distribution publique (App Store, Developer ID + notarisation) : usage perso d'abord, voir « Signature ».

## Anti-objectifs (échec même si « ça marche »)

- **Perdre une séance** (crash, Notion indisponible, Mac en veille au mauvais moment) sans que David le voie.
- Dupliquer une séance dans Notion.
- Bloquer KS Fit sans que David puisse reprendre la main.
- Une app qui consomme visiblement de la batterie ou spamme l'API Notion.

## Contraintes

- macOS 15+ (machine de David : 15.6.1), Xcode 26.3, Swift 6.2, XcodeGen installé.
- Données personnelles : stockage local d'abord ; seul Notion reçoit des données, via l'intégration de David.
- Le Mac doit être allumé et à portée pendant la marche ; une marche Mac fermé n'est pas captée (limite acceptée).
- Gates ub-mode (crapper, dryer, mutator) ne supportent pas Swift : principes appliqués, gates sautés, à dire dans le log.

## Approches considérées

| | Approche | Compromis | Décision |
|---|---|---|---|
| A | Service Python (bleak) en `launchd` + API Notion | Le plus rapide, réutilise la sonde, gates outillés ; autorisation Bluetooth d'un agent launchd incertaine, rien de visible | Écartée |
| **B** | **App native Swift barre de menus (CoreBluetooth) + API Notion** | Autorisation Bluetooth propre, état visible, potentiel produit ; 3–4× plus de travail, pas de gates outillés, apps concurrentes existent (Paceora, WalkFlow) | **Choisie par David** |
| C | Python local + sync Notion hebdo par tâche Cowork | Pas de jeton dans le code ; Notion à jour une fois par semaine, dépend d'un run Claude | Écartée |

Pont ESP32 (captation Mac éteint) écarté : matériel, prématuré.

## Design

### Découpage

- **`WalkingPadKit`** (package SwiftPM local, logique pure, testée avec `swift test`) :
  - `FTMSTreadmillFrame` : décodage d'une trame `0x2ACD` selon les flags (spec Bluetooth SIG) + extension KingSmith bit 13.
  - `SessionTracker` : machine à états qui transforme un flux de trames horodatées en séances.
  - `WeeklySummary` : agrégation des séances d'une semaine ISO (lundi → dimanche, fuseau local).
  - `NotionPayloads` : construction des corps JSON (ligne de séance, page de récap) — pas d'appel réseau.
- **App `TapisMarche`** (cible XcodeGen, `LSUIElement`, `MenuBarExtra` SwiftUI) :
  - `PadConnection` : CoreBluetooth — scan du service `0x1826` filtré sur le nom `KS-HD-`, connexion, abonnement `0x2ACD`, reconnexion automatique.
  - `SessionStore` : SQLite local (source de vérité) avec trames brutes et séances.
  - `NotionSync` : envoi des séances non synchronisées, récap hebdo, reprises.
  - UI barre de menus + fenêtre Réglages.
  - Lancement à l'ouverture de session via `SMAppService`.

### Règles de séance

- Une séance **commence** à la première trame avec vitesse > 0.
- Elle **se termine** après 3 minutes consécutives à vitesse 0, ou à la déconnexion si le tapis ne revient pas dans les 3 minutes.
- Une pause < 3 min reste dans la même séance.
- Les compteurs du tapis (distance, pas, temps) peuvent repartir à zéro entre deux démarrages de bande : les totaux d'une séance se calculent en **sommant les incréments positifs** de chaque compteur, une remise à zéro étant traitée comme un nouveau départ, jamais comme un incrément négatif.
- Champs d'une séance : début, fin, durée active (temps à vitesse > 0), distance (m), pas, vitesse moyenne et max, énergie (kcal, telle que rapportée par le tapis).

### Fiabilité (anti-objectif « perdre une séance »)

- Chaque trame est écrite en SQLite à réception (ou par lots courts) : un crash ne perd que quelques secondes.
- Au redémarrage, une séance ouverte est close à partir des trames stockées.
- Synchro Notion idempotente : chaque séance a un identifiant stable stocké dans Notion ; on ne recrée jamais une ligne déjà présente. Échec réseau → nouvel essai avec délai croissant ; l'état « N séances en attente » est visible dans le menu.
- Récap hebdo : généré au premier lancement/réveil après dimanche 23:59 pour chaque semaine terminée sans récap (rattrapage si le Mac dormait).

### Notion

- Intégration interne Notion créée par David ; jeton saisi dans Réglages et stocké dans le **Trousseau** (jamais dans un fichier).
- David partage une page parente avec l'intégration ; au premier lancement, l'app y crée la base « Marches » (propriétés : Date, Début, Fin, Durée, Distance km, Pas, Vitesse moy., Vitesse max, kcal, ID) et une page « Récaps hebdo » sous laquelle vont les récaps.
- Récap : titre « Semaine 47 — 16-22 nov. » (semaine ISO ; à cheval sur deux mois : « Semaine 49 — 30 nov.-6 déc. »), totaux (séances, durée, km, pas), meilleur jour, mini-histogramme par jour, comparaison à la semaine précédente.

### Barre de menus

```
🚶 3,5 km/h · 4 210 pas          ← en marche
🚶 · 12 340 pas                  ← connecté, à l'arrêt
🚶̸                               ← tapis absent

Aujourd'hui : 2 h 05 · 8,4 km · 12 340 pas
Cette semaine : 7 h 40 · 31,2 km
Dernières séances ▸
Notion : à jour  (ou « 2 séances en attente »)
Libérer le tapis pour KS Fit (15 min)
Réglages…
Quitter
```

« Libérer le tapis » déconnecte et suspend la reconnexion le temps indiqué (réponse à l'anti-objectif KS Fit).

## À valider en premier (risques)

1. **Trames en marche réelle** : relancer la sonde pendant une marche pour confirmer vitesse/distance/temps non nuls, le format des pas (bit 13) et le comportement des compteurs entre deux démarrages de bande. Les règles de séance en dépendent.
2. Le Z1 continue-t-il à notifier sans poignée de main sur une connexion longue (> 30 min), et que fait-il quand il se met en veille ?

## Laissé au constructeur

- Choix de la couche SQLite (GRDB ou wrapper fin sur `libsqlite3`).
- Structure exacte des tests, nommage interne, délais de reprise réseau.
- Mise en page fine du menu et de la fenêtre Réglages.

## Décisions prises après la relecture constructeur (choix de Claude, à contester)

- **Ordre de construction** : le plan commence par la marche-test (sonde, ≥ 10 min en marche, avec un arrêt/redémarrage de la bande). `SessionTracker` et le schéma Notion ne sont figés qu'après.
- **Si les pas ne sont pas dans `0x2ACD`** : la v1 sort sans pas (colonne et affichage masqués), aucune estimation ; percer les services propriétaires est hors v1 (lecture seule).
- **Signature** : certificat « Apple Development » déjà présent sur le Mac, équipe `HFVC9G5X5R`. Signature stable → l'autorisation Bluetooth et l'accès Trousseau survivent aux recompilations ; `SMAppService` fonctionne. App installée dans `/Applications` par un script `make install`. Pas de sandbox en v1.
- **Notion autonome** : base « Marches » et pages de récap indépendantes des revues existantes ; un lien vers les revues pourra venir plus tard.
- **Sens de synchro** : Notion en écriture seule. Une séance déjà synchronisée (ID de page Notion stocké localement) n'est jamais recréée, même si David la supprime dans Notion. Une séance synchronisée en retard qui modifie une semaine déjà récapitulée met à jour la page de récap.
- **Seuil de séance** : une séance de moins de 2 min **et** moins de 100 m est ignorée (pas de ligne Notion).
- **Trou dans les données** : un incrément de compteur survenu pendant un trou de plus de 10 s sans trame (déconnexion, « Libérer le tapis », KS Fit) n'est pas crédité ; la séance reprend à partir des nouvelles valeurs.
- **Séance à cheval sur minuit** : rattachée au jour de son début.
