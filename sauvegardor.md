🧰 Sauvegardor - Mini Manuel d'utilisation

Version : Windows 7 / 10 / 11 — Compatible PowerShell et CMD

📋 Description

Le script batch sauvegardor.bat permet de compresser les répertoires utilisateurs présents dans C:\Users\ en utilisant 7-Zip. Il est conçu pour être simple d'utilisation, avec un menu interactif et une vérification des prérequis.

🧪 Prérequis

Lancer le script en tant qu'administrateur.

⚠️ Important : Il est fortement recommandé d'exécuter le script dans un PowerShell administrateur (plutôt qu'un CMD standard), afin d'assurer la compatibilité d'affichage et de certaines fonctionnalités.

Télécharger la dernière version depuis le dépôt officiel : https://github.com/Eurobotics-Association/Repair-Section

Avoir 7-Zip installé (détecté automatiquement dans le PATH ou C:\Program Files\7-Zip).

Le script vérifie automatiquement :

l'accès à PowerShell (pour un meilleur affichage)

l'espace disque disponible

les droits d'accès aux répertoires

📊 Tableau des options disponibles

Option

Action

Cible

Fragmentation en volumes (20 Go)

A

Sauvegarder un utilisateur sans fragmentation zip (archive unique, taille illimitée)

C:\Users\<Utilisateur>

❌ Non

B

Sauvegarder TOUS les utilisateurs avec fragmentation zip 20 Go automatique

Tous les répertoires de C:\Users

✅ Oui

C

Sauvegarder un utilisateur avec fragmentation zip 20 Go automatique

C:\Users\<Utilisateur>

✅ Oui

🧭 Utilisation pas à pas

Ouvrir un terminal PowerShell en tant qu'administrateur.

Naviguer dans le dossier contenant sauvegardor.bat.

Lancer le script :

.\sauvegardor.bat

Choisir une option dans le menu affiché :

A pour sauvegarder un seul utilisateur sans découpage

B pour sauvegarder tous les profils en fragments de 20 Go

C pour sauvegarder un seul utilisateur en fragments de 20 Go

Attendre la fin du processus. Un fichier sauvegardor_log.txt est généré.

📁 Résultats

Les archives .7z, ou .7z.001, .7z.002, etc. sont créées dans le même dossier que le script.

Nom des fichiers : NomDuDossier_NomDuPC_YYYYMMDD.7z

📘 Remarques utiles

Le script estime la taille compressée avec un ratio de 60%.

Les erreurs de fichier verrouillé sont ignorées (fichiers en cours d'utilisation).

Le menu revient automatiquement après chaque opération, sauf si vous choisissez "Q" pour quitter.

🔚 Fin

Ce mini manuel est conçu pour faciliter l'utilisation du script sauvegardor.bat en toute sécurité.
Pour toute amélioration, vérifiez bien l’état de votre installation 7-Zip et exécutez toujours le script dans un PowerShell en mode administrateur.
