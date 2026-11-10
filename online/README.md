# Buzzer Android en ligne

Cette version reprend les écrans arabes de l’APK v1.3. Supabase arbitre les buzzers dans la base de données. Un verrou sur la salle garantit qu’un seul buzz est accepté par ouverture et un numéro d’ouverture écarte les requêtes arrivées en retard.

## Mise en service

1. Dans un projet Supabase dédié, exécuter `setup.sql` une fois. Les données du jeu sont dans le schéma privé `buzzer_private`.
2. Dans `config.js`, renseigner l’URL du projet et sa clé **publishable**. Aucune clé d’administration ne doit être incluse.
3. Dans le projet Android, remplacer `assets/index.html` et ajouter `config.js` et `transport.js` dans les assets. Conserver `Cairo.ttf`, sa licence et `buzzer-logo.png` du projet v1.3. Le pont Android doit conserver `Native.qr(code)`, `Native.scan()` et le rappel `fromNative('scanned', code)`. Charger les assets via une origine HTTPS locale, par exemple WebViewAssetLoader, et conserver la permission Internet.
4. Compiler et signer l’APK avec la clé originale pour une mise à jour de l’application v1.3. Vérifier le scan et une manche complète entre un téléphone en Wi-Fi et un téléphone en données mobiles.

Les joueurs peuvent rejoindre jusqu’à 20 par salle. Le nom de la première personne à buzzer s’affiche sur tous les écrans. En cas de mauvaise réponse, le serveur la met en attente et rouvre les boutons pour les autres joueurs disponibles. Les salles expirent six heures après leur création.
