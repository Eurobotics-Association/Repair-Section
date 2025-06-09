# 📦 Mini-Guide d'utilisation — Verificator.bat

**Objectif :** Vérifier l'intégrité des fichiers `.zip` et `.7z` présents dans le répertoire d'exécution, sans avoir à les décompresser.

---

## ✅ Fonctionnalités principales

| Fonction                    | Description                                                                 |
| --------------------------- | --------------------------------------------------------------------------- |
| 🔍 Recherche automatique    | Scanne le dossier courant à la recherche de fichiers `.zip` ou `.7z`.       |
| 📂 Prise en charge multiple | Tous les fichiers trouvés sont testés l’un après l’autre.                   |
| 📄 Log détaillé             | Un fichier `verificator_log.txt` est généré avec tous les résultats.        |
| 🟢 Sortie claire à l'écran  | Messages explicites en couleur (si PowerShell) et statut de chaque fichier. |

---

## 🛠️ Prérequis

* Windows 7, 10 ou 11
* 7-Zip doit être installé et accessible dans le PATH (`7z.exe`)
* Lancer le script en **mode administrateur**, de préférence dans **PowerShell**

---

## ▶️ Comment l'utiliser

1. Placez `verificator.bat` dans le dossier contenant vos fichiers `.zip` / `.7z`
2. Lancez un terminal PowerShell en tant qu’administrateur
3. Exécutez le script :

```bat
./verificator.bat
```

---

## 📊 Résultat attendu à l’écran

Chaque archive affiche l’un des statuts suivants :

* ✅ `[OK] Archive intacte : <nom_du_fichier>`
* ❌ `[ERREUR] Archive corrompue ou illisible : <nom_du_fichier>`
* ⚠️ `[AVERTISSEMENT] Erreur de lecture, fichier en usage : <nom_du_fichier>`

---

## 📁 Log disponible

Un fichier `verificator_log.txt` est créé dans le même dossier que le script, contenant :

* Nom du fichier testé
* Statut de test
* Horodatage

---

## ℹ️ Notes complémentaires

* Le test utilise la commande :

```bat
7z.exe t "nom_du_fichier.7z"
```

* Aucun fichier n’est extrait durant le test.
* Pour vérifier manuellement une archive :

```bat
7z.exe t archive.7z
```

---

> ✉️ Pour plus d’informations ou pour contribuer : [https://github.com/Eurobotics-Association/Repair-Section](https://github.com/Eurobotics-Association/Repair-Section)
