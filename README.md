# tapis-marche

Exploiter mon tapis de marche sans passer par l'application du fabricant :
récupérer et conserver l'historique des séances, et trouver d'autres façons de s'en servir.

## État

Réflexion en cours (ouverte le 2026-11-16). Rien n'est encore construit.

Questions à trancher avant de coder :

- Modèle exact du tapis et application actuelle (détermine le protocole : Bluetooth standard FTMS, protocole propriétaire, ou cloud du fabricant).
- Ce que « historique » doit contenir et où il doit vivre.
- Les usages « différents » visés.

## Repères

- Le design validé ira dans `docs/superpowers/specs/`.
- Les données de séances ne sont pas versionnées (`data/` est ignoré).
