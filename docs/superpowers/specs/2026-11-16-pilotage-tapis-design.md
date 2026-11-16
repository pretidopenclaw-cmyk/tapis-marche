# Pilotage du tapis — app Tapis Marche + Raycast

Date : 2026-11-16 · Statut : à valider par David (relu par un constructeur)

## Intention

David démarre presque toujours son WalkingPad Z1 (`KS-HD-Z1E`) puis passe tout de suite à **2 km/h**, sa vitesse habituelle.
Il veut :
1. que la bande passe d'elle-même à sa vitesse dès qu'elle démarre ;
2. qu'elle s'arrête d'elle-même quand il descend ;
3. démarrer / arrêter / régler la vitesse sans la télécommande : depuis le menu de l'app, au clavier, et depuis **Raycast** (son lanceur).

C'est la piste « prendre le contrôle du tapis », choisie parce que c'est la plus amusante à développer et qu'elle ouvre la suite (ralentir en réunion, programmes).

## Ce que les essais ont établi (2026-11-16, `spike/walkingpad_control_probe.py`, `spike/walkingpad_presence_probe.py`)

- **Le Z1E obéit au FTMS standard sans déverrouillage KingSmith** : `request control` (0x00), `start` (0x07), `set target speed` (0x02 + uint16 LE en 0,01 km/h), `stop` (0x08 0x01) → tous `success` (indication `80 <op> 01` sur `0x2AD9`).
- Plage annoncée (`0x2AD4`) : **1,0 – 6,0 km/h, pas 0,1**. La bande démarre à 1,0 km/h (≈ 4 s), atteint une nouvelle consigne en ≈ 1 s, s'arrête en ≈ 4 s.
- `Fitness Machine Status` (`0x2ADA`) notifie `04` (démarrée) et `02 01` (arrêtée par l'utilisateur).
- **Les pas ne comptent que de vrais pas** : bande à vide 20 s → +0 ; David marche 20 s → +22 (≈ 1 pas/s à 1 km/h) ; descendu 20 s → +0. Premier pas compté 4–5 s après la montée.
- Après un `stop` FTMS, les compteurs (pas, distance, temps) repartent à 0 (déjà géré par le journal).
- Le service de déverrouillage KingSmith (`24e2521c-…`) et sa trame (`71 00 05 01 2e 5a 31 45 75` pour ce tapis) sont connus mais **inutiles** sur ce firmware.

## Objectifs

1. **Vitesse au démarrage** : quand la bande démarre (télécommande, Mac, Raycast), l'app la passe à la vitesse préférée (2,0 km/h par défaut), une seule fois par démarrage.
2. **Arrêt quand David descend** : bande en marche + aucun pas compté pendant 10 s → arrêt, sauf pendant les 15 s qui suivent un démarrage.
3. **Menu** : « Démarrer le tapis », « Arrêter le tapis », « Plus vite », « Moins vite » dans le menu de la barre de menus.
4. **Commandes par lien** : `tapismarche://demarrer`, `…/arreter`, `…/vitesse/<km/h>`, `…/plus-vite`, `…/moins-vite`.
5. **Raycast** : un dossier `raycast/` de Script Commands prêtes à l'emploi qui ouvrent ces liens ; les raccourcis clavier sont attribués dans Raycast.
6. **Réglages** : vitesse au démarrage (1,0–6,0, pas 0,1, défaut 2,0) + case pour l'activer ; case « Arrêter quand je descends » (activée par défaut).

## Non-objectifs (cette version)

- Programmes (fractionné), ralentissement automatique en réunion (piste suivante, s'appuiera sur ce pilotage).
- Extension Raycast (TypeScript), affichage de la vitesse dans Raycast, actions Raccourcis / Siri.
- Raccourci clavier global géré par l'app (Raycast s'en charge).
- Déverrouillage KingSmith (inutile sur ce firmware).

## Anti-objectifs (échec même si « ça marche »)

- **La bande démarre sans ordre explicite de David** (l'app ne démarre jamais la bande d'elle-même).
- **La bande s'arrête pendant que David marche** (faux positif de l'arrêt automatique).
- L'app contredit la télécommande : elle ne réimpose jamais la vitesse après le démarrage.
- Une trame `0xE8` (mode mise à jour, risque de rendre le tapis inutilisable), ou des commandes plus rapprochées que 400 ms.

## Contraintes

- Une seule connexion BLE : les commandes passent par la connexion que l'app tient déjà ; rien pendant « Libérer le tapis ».
- Lecture seule jusqu'ici : la conception du journal disait « jamais d'écriture » ; ce pilotage lève cette règle **uniquement** pour le point de contrôle FTMS `0x2AD9` et les 4 commandes ci-dessus.
- Vitesse toujours bornée à la plage lue sur `0x2AD4` et arrondie au pas.
- macOS 15, Swift 6, XcodeGen ; logique pure dans `WalkingPadKit` et testée, l'app reste un adaptateur.

## Approches considérées

| | Approche | Compromis | Décision |
|---|---|---|---|
| **A** | **Liens `tapismarche://` + Script Commands Raycast, raccourcis via Raycast** | Simple, robuste, réutilisable (terminal, Raccourcis, Stream Deck) ; Raycast ne fait qu'envoyer des ordres | **Choisie par David** |
| B | Extension Raycast (TypeScript) avec vitesse en direct | Plus riche ; second projet (serveur local + extension), 3–4× plus de travail | Écartée |
| C | App Intents (Raccourcis, Siri, Spotlight) | Natif ; Raycast passe par Raccourcis, plus lent | Plus tard, en complément |

## Design

### WalkingPadKit (pur, testé)

- **`PadCommand`** : `requestControl`, `start`, `stop`, `setSpeed(Double)` → octets FTMS. `setSpeed` borne à la plage et arrondit au pas. Refuse par construction tout premier octet `0xE8`.
- **`ControlResponse`** : décode l'indication `80 <op> <résultat>` (success, not supported, invalid parameter, operation failed, control not permitted).
- **`SpeedRange`** : décode `0x2AD4` (min, max, pas en 0,01 km/h).
- **`AutoPilot`** : machine à états qui reçoit les trames (vitesse, pas, horodatage) et les réglages, et rend des commandes :
  - **démarrage détecté** : vitesse passe de 0 à > 0 ; 2 s après, si la vitesse préférée est activée et différente de la vitesse actuelle → `setSpeed(préférée)`, une seule fois pour ce démarrage ;
  - **personne sur la bande** : vitesse > 0, plus de 15 s depuis le démarrage, et aucun incrément de pas depuis 10 s → `stop`, une seule fois ; inactif si le tapis ne rapporte pas de pas ;
  - n'émet **jamais** `start`.
- **`PadURLCommand`** : analyse `tapismarche://demarrer | arreter | vitesse/<km/h> | plus-vite | moins-vite` (± 0,5 km/h) ; lien inconnu ou vitesse illisible → erreur.

### App

- **`PadConnection`** : découvre aussi `0x2AD9` (indications) et `0x2AD4` ; à chaque connexion, lit la plage puis envoie `requestControl` ; file d'envoi qui espace les commandes d'au moins 400 ms et attend l'indication ; si une réponse est « control not permitted », renvoie `requestControl` puis la commande, une fois.
- **`AppModel`** : nourrit `AutoPilot` avec les trames ; exécute ses commandes et celles du menu / des liens ; « Démarrer » = `start` (la vitesse préférée suit via `AutoPilot`, comme pour la télécommande).
- **Liens** : schéma `tapismarche` déclaré dans l'Info.plist, reçus par un délégué d'application.
- **Menu** : « Démarrer le tapis » (bande arrêtée) / « Arrêter le tapis » (bande en marche), « Plus vite », « Moins vite » ; grisés si le tapis est absent ou libéré.
- **Retour d'information** : dernier arrêt automatique affiché dans le menu (« Arrêt auto à 14:32 : personne sur le tapis ») et journalisé. Une commande impossible (tapis absent, libéré) est ignorée et journalisée.

### Raycast

- `raycast/` : `tapis-demarrer.sh`, `tapis-arreter.sh`, `tapis-vitesse.sh` (argument « km/h »), `tapis-plus-vite.sh`, `tapis-moins-vite.sh` ; chacun `open -g "tapismarche://…"` (sans passer l'app au premier plan), mode silencieux, icône 🚶.
- README : Raycast › Extensions › Script Commands › Add Directories › `raycast/` ; suggestion de raccourcis (ex. ⌥⌘↑ démarrer, ⌥⌘↓ arrêter).

## À valider en premier (risques)

1. **Démarrage à la télécommande pendant que l'app a le contrôle** : la télécommande reste-t-elle active, et `AutoPilot` voit-il le démarrage ?
2. Le contrôle reste-t-il acquis sur une connexion longue, ou faut-il le redemander (réponse « control not permitted ») ?
3. Particularité KingSmith signalée par d'autres : déconnexion possible juste après un démarrage à froid.

## Décisions prises après la relecture constructeur (choix de Claude, à contester)

- **Télécommande et contrôle** : la validation n°1 se fait en premier. Si la télécommande cesse de fonctionner tant que l'app détient le contrôle, l'app passe au **contrôle à la demande** : `requestControl` juste avant chaque commande, et pas de maintien entre deux (pas de `reset`, qui pourrait arrêter la bande). Perdre la télécommande n'est pas acceptable.
- **Connexion pendant que la bande tourne déjà** (lancement de l'app, fin de « Libérer », reconnexion) : **ce n'est pas un démarrage**, l'app n'impose pas la vitesse préférée (anti-objectif « ne jamais réimposer »). Exception : si l'app a vu le démarrage et que la connexion tombe avant que la vitesse préférée ait été appliquée (cas KingSmith signalé), elle l'applique à la reconnexion, si celle-ci survient dans les 30 s. Le délai de 15 s de l'arrêt automatique repart à chaque (re)connexion.
- **Liens ouvrables par tout programme du Mac (décision de David)** : accepté sans secret ni confirmation — Mac personnel, les navigateurs demandent confirmation avant d'ouvrir un schéma inconnu, et une bande démarrée à vide est arrêtée par l'arrêt automatique en ≈ 25 s.
- **Commande reçue avant que le tapis soit connecté** (Raycast lance l'app) : elle attend la connexion **au plus 10 s**, puis elle est abandonnée avec une notification macOS « Tapis introuvable ». Une seule commande en attente à la fois (la plus récente remplace la précédente).

## Laissé au constructeur

- Noms internes, structure des tests, délai exact d'attente d'une indication.
- Mise en page des réglages et du menu.
