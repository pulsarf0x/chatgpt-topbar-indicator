# Validation — 19 octobre 2026

## Réalisé

- Lecture réelle du compte via le CLI officiel installé sur ce Mac : un groupe `codex`, deux fenêtres de quota. Les chiffres évoluent avec l’usage du compte et ne sont pas figés dans l’app.
- Application macOS Release lancée avec Launch Services. La lecture autonome a alimenté le cache partagé avec un instantané âgé d’une seconde lors du contrôle, sans ouvrir le panneau.
- 14 tests de calcul/décodage et de protocole JSON-RPC : succès. Ils couvrent notamment les fenêtres manquantes, expirées et anciennes, les groupes multiples, les pourcentages fractionnaires, les réponses invalides, les notifications entre les réponses, les erreurs de compte et la fermeture silencieuse du serveur.
- Compilation macOS (Apple Silicon et Intel), app et extension WidgetKit, sans signature : succès.
- Compilation iOS Simulator (arm64 et x86_64), app et extension WidgetKit, sans signature : succès.

## À valider avec l’équipe Apple Developer

- Signature et provisioning des quatre cibles ; App Group enregistré et stockage clé-valeur iCloud autorisé.
- Ajout et affichage effectifs des widgets dans la galerie macOS/iOS.
- Synchronisation entre un Mac et un iPhone avec le même compte Apple, réception iCloud puis propagation au widget.
- Installation et lancement sur un iPhone physique.
- Connexion navigateur d’un nouveau compte, changement de compte, démarrage à la connexion depuis une app signée dans Applications.
- Vérification visuelle des interfaces, des interactions et de l’accessibilité. Le contrôle automatisé de l’interface native n’était pas disponible pendant cette session.

Le service CoreSimulator installé (1171.7.0) est plus ancien que celui attendu par Xcode (1174.9.2). La compilation générique pour le simulateur réussit ; son lancement n’a pas été validé. Aucun composant système n’a été réinstallé ou modifié.

Les résultats de compilation ne constituent pas une validation des capacités iCloud/App Groups ni une distribution signée/notarisée. Le Mac exécute une compilation locale sans signature de distribution.

## Commandes reproductibles

```sh
swift test
./Scripts/probe.sh
./Scripts/check.sh
./Scripts/build-macos.sh
```

`probe.sh` affiche seulement le nombre de groupes/fenêtres et les pourcentages restants. Aucun jeton d’authentification n’est affiché. Voir le README pour les réglages de signature et les limites de rafraîchissement.

## Affichage direct dans la barre

Les fenêtres du groupe sélectionné sont affichées ensemble (exemple : `5 h 72 % · 7 j 84 %`). La lecture se fait automatiquement toutes les 30 secondes après la fin de la lecture précédente, sans ouverture du panneau. Ce rafraîchissement est quasi temps réel et dépend de la disponibilité et du délai de mise à jour de Codex. Les échéances dépassées et les lectures trop anciennes affichent des tirets ; un échec de lecture ajoute un avertissement. Les demandes de rafraîchissement WidgetKit sont regroupées quand les quotas ne changent pas.

Contrôle du rafraîchissement automatique : version finale relancée, lectures réussies au lancement et au cycle suivant, sans ouverture du panneau. Les 14 tests ainsi que les compilations macOS Release et iOS Simulator réussissent après cette modification.

## 0.1.1 — menu bar rendering correction

The 0.1.0 runtime checks confirmed successful quota reads and cache updates but did not validate visible text. A user report confirmed that only the icon appeared. The image-based MenuBarExtra initializer uses its title for accessibility; 0.1.1 uses the text-only initializer instead.

The macOS Release build succeeded, version 0.1.1 was launched in place of the previous instance, and live quota reads succeeded. Automated native UI inspection was unreliable and did not provide visual confirmation of the final menu bar. User confirmation remains required for the visible result (issue #1).
