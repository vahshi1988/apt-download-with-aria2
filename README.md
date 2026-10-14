# apt-download-with-aria2

Accelerate direct downloads and `apt` package installations using [aria2](https://aria2.github.io/) — multi-connection, parallel, and resumable.

This repository provides two shell scripts:

| Script | Description |
|---|---|
| `aria2-dl.sh` | CLI wrapper to download any URL with multi-connection acceleration (up to 16 connections) via aria2. |
| `apt-a2.sh` | Integrates `apt` with aria2: fetches package URLs, downloads them accelerated in parallel to apt's cache, then completes the installation with standard `apt`. |

---

## Prerequisites

Ensure `aria2` and `curl` are installed:

```bash
sudo apt update && sudo apt install -y aria2 curl
```

---

## Installation

Clone the repository and create symbolic links in your `PATH` (e.g. `~/.local/bin`):

```bash
git clone https://github.com/vahshi1988/apt-download-with-aria2.git
cd apt-download-with-aria2
chmod +x aria2-dl.sh apt-a2.sh

mkdir -p ~/.local/bin
ln -s "$PWD/aria2-dl.sh" ~/.local/bin/a2
ln -s "$PWD/apt-a2.sh"   ~/.local/bin/apt-a2
```

> **Note:** Keep both scripts in the same directory, or specify the location of `aria2-dl.sh` using the `A2DL` environment variable.

---

## Usage

### 1. `aria2-dl.sh` (or `a2`)

Download single or multiple files with up to 16 connections per server:

```bash
# Download a file to ~/Downloads with 16 connections
a2 "https://example.com/archive.zip"

# Interactive prompt (if called with no arguments)
a2

# Specify output directory and custom filename
a2 -d ~/Videos -o movie.mkv "https://example.com/video.mp4"

# Download multiple URLs concurrently (up to 5 concurrent downloads)
a2 "https://example.com/file1.zip" "https://example.com/file2.zip"

# Download URLs listed in a text file (one URL per line)
a2 -i links.txt

# Dry run: print equivalent aria2c command without downloading
a2 -p "https://example.com/archive.zip"

# Send download to a running aria2 RPC daemon
ARIA2_SECRET="mysecret" a2 -r "https://example.com/file.iso"
```

#### Options

| Flag | Description |
|---|---|
| `-d DIR` | Download directory (default: `~/Downloads`) |
| `-o NAME` | Output filename (for single URL downloads) |
| `-x N` | Number of connections per server (default: 16, max: 16) |
| `-i FILE` | Input file containing URLs (one per line) |
| `-R URL` | Custom Referer header |
| `-c FILE` | Load cookies from Netscape-format cookie file |
| `-H HEADER` | Custom HTTP header (can be repeated) |
| `-p` | Print command only (dry-run) |
| `-r` | Submit URL to running aria2 JSON-RPC daemon (`ARIA2_RPC`, `ARIA2_SECRET`) |
| `-h` | Display help and usage information |

---

### 2. `apt-a2.sh` (or `apt-a2`)

Use aria2's multi-connection engine to accelerate package downloads for Ubuntu/Debian `apt`:

```bash
# Install packages
apt-a2 install htop vlc build-essential

# Upgrade packages
apt-a2 upgrade
apt-a2 full-upgrade

# Reinstall packages
apt-a2 reinstall bash

# Preview packages and sizes to be downloaded
apt-a2 --dry-run upgrade

# Non-download commands pass directly through to standard apt
apt-a2 update
apt-a2 search nginx
```

> **Note:** Automatically invokes `sudo` when root permissions are required.

#### How It Works

1. Queries package URLs and dependencies via `apt-get --print-uris`.
2. Identifies missing packages (skips packages already verified in `/var/cache/apt/archives`).
3. Downloads archives concurrently with `aria2-dl.sh` directly into `/var/cache/apt/archives/partial`.
4. Moves successfully completed `.deb` packages into `/var/cache/apt/archives`.
5. Handover to native `apt`, which verifies cryptographic hashes and GPG signatures before unpacking and installing.

#### Environment Variables

| Variable | Description |
|---|---|
| `A2DL` | Path to `aria2-dl.sh` (default: script's own folder) |
| `A2_CONN` | Max connections per package download (default: 16) |

---

## License

This project is licensed under the [MIT License](LICENSE).
