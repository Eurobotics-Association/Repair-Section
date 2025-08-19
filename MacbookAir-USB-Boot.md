Booting Linux (Zorin OS) on MacBook Air (2015) – Working Procedure

1. USB Creation

The USB boot stick must be burned on the MacBook Air itself.

Tools used: balenaEtcher installed on ElementaryOS.

Media used: new SD card with an old USB 2.0 stick-reader.

The ISO (Zorin OS 17.3 Core) was first transferred to the Mac (~/Downloads) and burned locally.

Stick burned on the right-side USB port (near the headphone jack).

2. Booting

The boot device was recognized only after several firmware resets:

Reboot 4 times with Option + Cmd + R + P (NVRAM reset).

Then reboot while holding Option → USB device finally appeared.

Successful boot when USB was inserted into the left-side USB port (near the power connector).

3. Bless / EFI Management Options

If on macOS: use bless to set USB as default boot:

sudo bless --mount /Volumes/ZorinUSB --setBoot --file /Volumes/ZorinUSB/EFI/BOOT/BOOTX64.EFI

If on Linux: use efibootmgr to set BootNext or add an entry:

sudo efibootmgr -c -d /dev/sdX -p 1 -L "ZorinUSB" -l '\EFI\BOOT\BOOTX64.EFI'
sudo efibootmgr -n 0002   # example, boot USB once

4. Key Notes

Weird but important: burning the USB on the MacBook Air itself seems required for firmware to accept it.

NVRAM resets are critical to flush out rEFInd remnants and old boot entries.

Use Option key boot picker after resets to manually select USB.

Right port worked for burning, left port worked for booting.

✅ Final result: Zorin OS USB now boots successfully on MacBook Air (2015).

File format: .md (Markdown) → ready to copy into GitHub for documentation.

