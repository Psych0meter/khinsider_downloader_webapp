Here is a professional `README.md` specifically for your `scripts/` directory. It explains the purpose of the folder and provides a breakdown of each legacy script's functionality.

---

# Scripts Archive

This directory serves as a repository for legacy versions of the KHInsider download tools. These scripts represent the evolution of the project before it was consolidated into the current Python-based web application.

They are preserved here for reference, CLI-only environments, or cases where a lightweight PowerShell or Bash script is preferred over a Dockerized deployment.

## Script Inventory

### 1. Download-KHInsider.ps1

**Language:** PowerShell

**Platform:** Windows / PowerShell Core

**Key Features:**

* Fetches album metadata using `Invoke-WebRequest`.
* Automatically creates a local directory based on the album title.
* Implements a priority logic: prefers **FLAC** over MP3/M4A if multiple formats are available.
* Sanitizes filenames to remove invalid Windows characters.
* Provides a post-download summary including total size and elapsed time.

### 2. khinsider_album_dl.sh

**Language:** Bash

**Platform:** Linux / macOS / WSL

**Key Features:**

* Utilizes `curl` for web scraping and `wget` for file retrieval.
* Uses `grep` with Perl-compatible regular expressions (PCRE) for metadata extraction.
* Implements basic filename sanitization using `sed` and `tr`.
* Basic summary output upon completion.

### 3. khinsider_album_dl_v2.sh

**Language:** Bash

**Platform:** Linux / macOS / WSL

**Key Features:**

* **Enhanced UI:** Includes a dynamic CLI progress bar that updates in-place using `printf \r`.
* **ETA Calculation:** Provides a real-time estimated time of arrival based on download speed and remaining tracks.
* **Improved Logic:** Standardized title extraction and more robust error handling for missing song links.
* **Format Priority:** Maintains the "FLAC-first" logic found in the original PowerShell version.

---

## Usage (CLI)

These scripts require a single argument: the full URL of the KHInsider album page.

**PowerShell:**

```powershell
./Download-KHInsider.ps1 -albumUrl "https://downloads.khinsider.com/game-soundtracks/album/example"

```

**Bash:**

```bash
chmod +x khinsider_album_dl_v2.sh
./khinsider_album_dl_v2.sh "https://downloads.khinsider.com/game-soundtracks/album/example"

```

---

## Technical Note

These scripts are currently in **maintenance mode**. New features—such as the search engine, automated footer stripping, and the web-based progress interface—are only available in the primary `app.py` located in the root directory.
