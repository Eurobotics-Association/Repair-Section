#!/bin/bash
# Eurobotics - Remote Repair Tunnel Script
# File: ebtx-repair-connect

echo "🔧 Eurobotics Remote Repair Utility"
echo "------------------------------------"
echo "Ce script permet d'établir une connexion sécurisée à distance avec la section Repair d’Eurobotics."
echo

read -p "❓ Acceptez-vous la connexion avec Eurobotics Repair Section ? (Oui/O/o/Y/Yes ou Non/N/no) : " consent

case "${consent,,}" in
    o|oui|y|yes)
        echo "✅ Connexion autorisée. Démarrage de la connexion SSH inversée..."
        echo "⏳ Veuillez patienter, ne fermez pas cette fenêtre."
        echo "------------------------------------"
        sleep 1
        ssh -v -R ebtx-repair:22:localhost:22 serveo.net
        echo "------------------------------------"
        echo "🔚 Script terminé. Connexion SSH inversée fermée."
        ;;
    *)
        echo "❌ Connexion refusée. Aucune action n'a été effectuée."
        echo "🔚 Script terminé. Aucune connexion établie."
        ;;
esac

