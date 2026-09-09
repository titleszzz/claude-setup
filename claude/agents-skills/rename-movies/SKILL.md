---
name: rename-movies
description: Rename episode files in a folder on the Pi's WD_Movies share (M:) to a clean ep1..epN scheme. Renames directly on the Pi over SSH to avoid Samba "file in use" lock errors. Trigger with /rename-movies, optionally naming the folder and/or scheme.
---

# rename-movies

Rename messy TV-episode filenames (e.g. `S01E001_...by MerkavaMII.mkv`) to a clean scheme
inside a folder on the Pi 5's movie share.

## Why this skill exists

Renaming over the mapped `M:` drive (`\\192.168.50.141\WD_Movies`, the Pi's Samba share)
fails with "The process cannot access the file because it is being used by another process"
because of Samba directory leases — even when nothing is really playing. The fix is to
rename directly on the Pi's own filesystem over SSH. See memory `wd-movies-rename-via-ssh`
and `raspi5-access`.

- Windows `M:` path  →  Pi path is `/mnt/wd_movies`
- SSH: `pi@192.168.50.141`, key `~/.ssh/id_ed25519`
- Jellyfin runs on the Pi and only reads the files; it picks up new names on its next scan.

## Arguments (all optional, from `$ARGUMENTS`)

- **Folder**: the series/movie folder name (usually under `SERIES/`). If not given, ask the
  user which folder, or list `SERIES/` so they can pick.
- **Scheme**: default `epN.mkv` (`ep1.mkv`, `ep2.mkv`, ...). Also accept `S01E01` style
  (`S01E01.mkv`, Jellyfin-friendly) if the user asks. Keep the `.mkv` extension.

## Steps

1. **Find the folder.** If the user gave a name, use it. Otherwise list options:
   ```
   ssh -i "$env:USERPROFILE\.ssh\id_ed25519" -o StrictHostKeyChecking=no pi@192.168.50.141 "ls -1 /mnt/wd_movies/SERIES"
   ```

2. **Show the current files first** so the user can confirm before anything changes:
   ```
   ssh -i "$env:USERPROFILE\.ssh\id_ed25519" -o StrictHostKeyChecking=no pi@192.168.50.141 'ls -1 "/mnt/wd_movies/SERIES/<FOLDER>"'
   ```

3. **Rename via a base64-encoded bash script.** Base64 is required because folder names have
   Thai characters, spaces, and stray `)` that break PowerShell→SSH quoting. In PowerShell:
   ```powershell
   $folder = "SERIES/<FOLDER>"           # adjust
   $script = @'
   cd "/mnt/wd_movies/__FOLDER__" || exit 1
   for f in S01E0*.mkv *.mkv; do
     [ -e "$f" ] || continue
     n=$(echo "$f" | sed -E 's/.*[Ss]0*1?[Ee]0*([0-9]+).*/\1/')
     case "$n" in ''|*[!0-9]*) continue;; esac   # skip if no episode number found
     new="ep${n}.mkv"
     [ "$f" = "$new" ] && continue
     mv -vn "$f" "$new"
   done
   echo "--- result ---"; ls -1
   '@ -replace '__FOLDER__', $folder
   $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($script))
   ssh -i "$env:USERPROFILE\.ssh\id_ed25519" -o StrictHostKeyChecking=no pi@192.168.50.141 "echo $b64 | base64 -d | bash"
   ```
   - `mv -n` = never overwrite an existing file (safety). Report any that were skipped.
   - For the `S01E01` scheme instead, set `new="S01E$(printf '%02d' "$n").mkv"`.

4. **Confirm the result** from the `--- result ---` listing and report old→new as a small table.

5. **Mention Jellyfin**: it will show the new names after its next library scan; offer to note
   if names look duplicated/missing that a manual "Scan library files" fixes it.

## Safety

- Never overwrite: always use `mv -n`.
- Show files and get a quick confirm before renaming when the folder or scheme is ambiguous.
- Only operate under `/mnt/wd_movies`; never touch paths outside it.
