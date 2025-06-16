#!/bin/bash
# Eurobotics - Remote Repair Tunnel Script
echo "🔧 Eurobotics Remote Repair Utility"
echo "------------------------------------"
echo "Ce script permet d'établir une connexion sécurisée à distance avec la section Repair d’Eurobotics."
echo

read -p "❓ Acceptez-vous la connexion avec Eurobotics Repair Section ? (Oui/O/o/Y/Yes ou Non/N/no) : " consent

case "${consent,,}" in
    o|oui|y|yes)
        echo "✅ Connexion autorisée. Démarrage de la connexion SSH inversée..."
        echo "⏳ Veuillez patienter, ne fermez pas cette fenêtre."
        echo "ℹ️  Les techniciens se connecteront avec:"
        echo "    ssh -p 8022 USERNAME@ebtx-repair.serveo.net"
        echo "------------------------------------"
        sleep 1
        
        # Critical fixes:
        # 1. Use port 8022 instead of 22 (privileged port issue)
        # 2. Add keepalive packets
        # 3. Exit on tunnel failure
        ssh -o ExitOnForwardFailure=yes \
            -o ServerAliveInterval=60 \
            -v -R ebtx-repair:8022:localhost:22 serveo.net
            
        echo "------------------------------------"
        echo "🔚 Script terminé. Connexion SSH inversée fermée."
        ;;
    *)
        echo "❌ Connexion refusée. Aucune action n'a été effectuée."
        echo "🔚 Script terminé. Aucune connexion établie."
        ;;
esac
