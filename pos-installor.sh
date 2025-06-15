function remove_libreoffice() {
    log_info "Removing LibreOffice suite..."
    
    # List of LibreOffice packages to remove
    local libreoffice_pkgs=(
        libreoffice-base 
        libreoffice-calc 
        libreoffice-core
        libreoffice-draw 
        libreoffice-gnome 
        libreoffice-gtk3 
        libreoffice-help-common 
        libreoffice-help-en-us 
        libreoffice-impress 
        libreoffice-math 
        libreoffice-ogltrans 
        libreoffice-pdfimport 
        libreoffice-style-colibre 
        libreoffice-style-elementary 
        libreoffice-style-tango 
        libreoffice-writer
        libreoffice-common
    )
    
    # Check if any LibreOffice packages are installed
    if dpkg -l | grep -q "libreoffice"; then
        # Purge LibreOffice packages
        apt purge -y "${libreoffice_pkgs[@]}" || log_warn "Some LibreOffice packages couldn't be removed"
        
        # Clean up dependencies
        apt autoremove -y
        log_success "LibreOffice removed and replaced by OnlyOffice"
    else
        log_info "LibreOffice not installed - nothing to remove"
    fi
}
