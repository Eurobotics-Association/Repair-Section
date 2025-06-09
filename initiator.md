⚙️ Initiator - Mini Manuel d'utilisation

Version : Windows 7 / 10 / 11 — Recommandé PowerShell (en administrateur)

📄 Description

Le script initiator.bat est conçu pour préparer automatiquement une machine Windows en installant une suite complète d'outils essentiels pour la sauvegarde, la sécurité, le transfert de fichiers, et l'administration distante.

🔧 Prérequis

Ouvrir PowerShell en tant qu’administrateur (indispensable).

Lancer le script depuis le répertoire où il se trouve.

✅ Assurez-vous d’avoir au moins 1 Go d’espace libre.

🔹 Fonctionnalités principales

Fonction

Détail

Vérification administrateur

Interrompt l’exécution si non lancé avec les droits requis

Vérification PowerShell

Affiche un message si PowerShell n’est pas présent

Espace disque disponible

Refuse de continuer si < 1 Go

Création du dossier /installers

Pour télécharger et stocker les installateurs

Journalisation

Toutes les actions sont loggées dans install_log.txt

Téléchargement automatique

Récupère les dernières versions stables des outils

Installation silencieuse

Installe tous les outils sans interaction utilisateur

📦 Outils installés

Python (dernière version disponible pour Windows x64)

Pip (intégré avec Python)

magic-wormhole (installé via pip)

ClamWin Antivirus (dernière version depuis SourceForge)

7-Zip (dernière version stable depuis https://www.7-zip.org)

RustDesk (version stable Windows depuis https://rustdesk.com)

🔢 Fichiers générés

install_log.txt → journal complet de l’exécution (dans le dossier du script)

installers\ → répertoire contenant tous les installateurs téléchargés

⚠️ Points d'attention

Tous les messages (erreurs, étapes, succès) sont affichés en temps réel et écrits dans le log.

Le script s’arrête immédiatement si une condition n’est pas remplie (ex : non-admin, pas assez d’espace).

Certains fichiers peuvent être bloqués s’ils sont déjà utilisés par un processus.

🔍 Exécution pas à pas

Clic droit sur PowerShell → "Exécuter en tant qu'administrateur"

Naviguez jusqu'au répertoire contenant initiator.bat

Lancez le script :

.\initiator.bat

Laissez le script télécharger, installer et vérifier chaque composant

🚀 Objectif

Ce script est idéal pour initier une machine avant un usage à distance, une réparation, ou une mise en service dans un réseau. Il prépare un environnement sécurisé et prêt à transférer ou sauvegarder des fichiers.

🔗 Téléchargement

Téléchargez la dernière version de initiator.bat via :🔗 https://github.com/Eurobotics-Association/Repair-Section
