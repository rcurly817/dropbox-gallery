# dropbox-gallery
image gallery on raspberry pi

## setup
* ssh raspi@192.168.178.55
* git clone https://github.com/rcurly817/dropbox-gallery.git
* bash dropbox-gallery/setup.sh

## ansible sudo error
If you see `sudo: a password is required`, run Ansible with a sudo password prompt:

* `ansible-playbook ansible/auto_update.yml -i inventory-remote.ini -K`

## auto update logs
If `auto-update.timer` shows `active (waiting)`, this is normal while it waits for the next schedule.

Useful checks on Raspberry Pi:

* `sudo systemctl status auto-update.timer --no-pager`
* `sudo systemctl list-timers auto-update.timer --all`
* `sudo systemctl status auto-update.service --no-pager -l`
* `sudo journalctl -u auto-update.service -n 200 --no-pager`
* `sudo journalctl --disk-usage`

Manual test run:

* `sudo systemctl start auto-update.service`

Log retention:

* Config file: `/etc/systemd/journald.conf.d/90-auto-update-retention.conf`
* Defaults set by playbook: `SystemMaxUse=200M`, `SystemKeepFree=100M`, `MaxRetentionSec=14day`

## install ssh + static ip
Run the SSH setup playbook:

* `ansible-playbook ansible/ssh.yml -i inventory-remote.ini -K`

This installs/enables SSH and configures static IP `192.168.178.1`.
For internet access, configure router port-forwarding TCP `22` to `192.168.178.1`.

`-K` (`--ask-become-pass`) prompts for your sudo password used by `become: yes`.

## dropbox credentials
Required files (text files) in `credentials/`:

* `dropbox_key.txt` (client_id)
* `dropbox_secret.txt` (client_secret)
* `dropbox_refresh_token.txt` (refresh token)

Token behavior:

1. Access-Tokens are short-lived (typically a few hours).
2. The setup now refreshes Access-Tokens automatically via `refresh_token` without user interaction.

Update refresh token (only when revoked/invalid):

1. Run `sudo /usr/local/bin/dropbox-authorize.sh` on the Raspberry Pi.
2. The script stores the refresh token automatically.
3. If needed, pass a custom output path: `sudo /usr/local/bin/dropbox-authorize.sh /path/to/dropbox_refresh_token.txt`
4. Run `ansible-playbook ansible/dropbox.yml -i inventory-remote.ini -K` again.

Automatic token refresh service:

* Timer: `dropbox-token-refresh.timer`
* Service: `dropbox-token-refresh.service`
* Default schedule: every 45 minutes

Useful checks:

* `sudo systemctl status dropbox-token-refresh.timer --no-pager`
* `sudo systemctl list-timers dropbox-token-refresh.timer --all`
* `sudo systemctl start dropbox-token-refresh.service`
* `sudo journalctl -u dropbox-token-refresh.service -n 100 --no-pager`

## dropbox and gallery split
The setup is split into two playbooks:

* `ansible/dropbox.yml` for Dropbox/rclone download and sync service
* `ansible/gallery.yml` for gallery player/autostart setup

Run both (recommended order):

1. `ansible-playbook ansible/dropbox.yml -i inventory-remote.ini -K`
2. `ansible-playbook ansible/gallery.yml -i inventory-remote.ini -K`

Gallery refresh after Dropbox sync:

* `ansible/dropbox.yml` restarts the gallery player automatically after a successful sync.
* Manual test: `sudo systemctl start dropbox-rclone-copy.service`

Smoother video playback on Raspberry Pi:

* `ansible/gallery.yml` enables a low-lag mpv setup (`profile=fast`, `hwdec=auto-safe`, frame dropping, cache).
* If videos still stutter, reduce source resolution/bitrate further (recommended max ~1280p, low/medium bitrate H.264).

## less sudo password prompts
After first installation, `ansible/dropbox.yml` installs a restricted sudoers rule so frequent operations do not ask for password again.

Passwordless commands for user `raspi`:

* `/usr/local/bin/dropbox-authorize.sh`
* `/usr/local/bin/dropbox-reconnect.sh`
* `systemctl start dropbox-rclone-copy.service`
* `systemctl restart dropbox-rclone-copy.timer`
* `systemctl status dropbox-rclone-copy.service`

Run once to apply:

* `ansible-playbook ansible/dropbox.yml -i inventory-remote.ini -K`

Note: running full Ansible setup playbooks with `become` still needs admin rights.

## desktop shortcuts on Raspberry Pi
`ansible/gallery.yml` creates desktop shortcuts in `~/Desktop`:

* `Dropbox Verbinden`
* `Dropbox Neu-Verbinden`
* `Dropbox Sync Starten`
* `Gallery Starten`

## shared folders for both playbooks
Shared folder variables are defined in `ansible/vars/shared_paths.yml` and loaded by both playbooks.

Current shared paths:

* `dropbox_download_dir` (`/opt/dropbox-download`)
* `dropbox_slideshow_dir` (`/opt/digital-frame`)
* `dropbox_slideshow_media_dir`
* `dropbox_playlist_file`

If you change folders, update only `ansible/vars/shared_paths.yml`.

## NAS-Archivierung (Backup & Konvertierung)

Das Playbook `ansible/nas_archivierung.yml` sichert Bilder inkrementell vom Raspberry Pi auf das Asustor-NAS, konvertiert `.heic`-Dateien in `.jpg` und schickt Status-Mails via IONOS.

### Automatische Ausführung (Cronjob)

Das Skript läuft nachts um 04:00 Uhr und zusätzlich 30 Sekunden nach jedem Systemstart (Reboot), um verpasste Backups nachzuholen.

Einträge in `crontab -e`:
```bash
# Jede Nacht um 4 Uhr ausführen
0 4 * * * ansible-playbook /home/raspi/dropbox-gallery/ansible/nas_archivierung.yml --vault-password-file /home/raspi/.ansible_vault_pass > /dev/null 2>&1

# Direkt nach jedem Neustart des Raspberry Pi ausführen
@reboot sleep 30 && ansible-playbook /home/raspi/dropbox-gallery/ansible/nas_archivierung.yml --vault-password-file /home/raspi/.ansible_vault_pass > /dev/null 2>&1
```

### Verschlüsselte Passwörter (Ansible Vault)

Das E-Mail-Passwort liegt verschlüsselt in `ansible/geheimnisse.yml`. 

- **Datei editieren/ansehen:**
  ```bash
  EDITOR=nano ansible-vault edit ansible/geheimnisse.yml
  ```
- **Manuell testen mit Passwort-Prompt:**
  ```bash
  ansible-playbook ansible/nas_archivierung.yml --ask-vault-pass
  ```
- **Manuell testen mit Passwort-Datei (wie Cronjob):**
  ```bash
  ansible-playbook ansible/nas_archivierung.yml --vault-password-file /home/raspi/.ansible_vault_pass
  ```

### Schutz vor SD-Karten-Überlastung

Das Playbook prüft vor dem Kopieren über die System-Mounts (`ansible_facts.mounts`), ob das NAS unter `/mnt/asustor` wirklich aktiv eingehängt ist. Ist das NAS offline (z. B. nach einem Stromausfall), bricht das Skript ab und sendet eine Warn-E-Mail, anstatt die lokale SD-Karte vollzuschreiben.

