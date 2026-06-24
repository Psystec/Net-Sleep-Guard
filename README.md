# net-sleep-guard

Prevents your Linux PC from going to sleep while something is downloading. Watches your network speed in real time and holds a `systemd-inhibit` sleep lock for as long as traffic stays above your threshold. Once the network goes quiet for long enough, it releases the lock and lets the system sleep normally.

```
  ┌──────────────────────────────────────────────────────┐
  │  ⏻  net-sleep-guard                                  │
  ├──────────────────────────────────────────────────────┤
  │  ↓ Download   24.81 MB/s     ↑ Upload  1.03 MB/s    │
  │  ⇅ Total      25.84 MB/s     ⚑ Limit   2 MB/s       │
  ├──────────────────────────────────────────────────────┤
  │  ████████████████░░░░░░░░░░░░░░░░░░░░░░   42%        │
  │  Cooldown  08:42  until sleep unlocks                │
  ├──────────────────────────────────────────────────────┤
  │  ● Active — sleep blocked                            │
  └──────────────────────────────────────────────────────┘
```

## Requirements

- **Linux** with **systemd** (any systemd-based distro — Arch, Garuda, Ubuntu, Fedora, etc.)
- **bash** 4.0 or newer
- **python3** (used to generate the inner worker script cleanly — present by default on virtually all distros)
- **`systemd-inhibit`** — part of `systemd`, already installed if your system uses systemd
- **`tput`** — part of `ncurses`, already installed on virtually all distros
- A terminal that supports UTF-8 and 256 colours (Konsole, GNOME Terminal, Alacritty, kitty, etc.)

## Installation

```bash
# clone the repo
git clone https://github.com/yourusername/net-sleep-guard.git
cd net-sleep-guard

# make it executable
chmod +x net-sleep-guard.sh
```

No dependencies to install beyond what ships with your distro.

## Usage

```bash
./net-sleep-guard.sh
```

That's it. The script reads its settings from the config block at the top of the file. Press **Ctrl-C** at any time to release the sleep inhibitor and exit.

## Configuration

Open `net-sleep-guard.sh` in any text editor. The settings are at the very top:

```bash
# CONFIGURATION
# THRESHOLD_MBPS  — minimum speed to count as "active". e.g. 1 = 1 MB/s, 0.5 = 500 KB/s
THRESHOLD_MBPS=2
# QUIET_MINUTES   — how long traffic must stay below the threshold before sleep is allowed
QUIET_MINUTES=15
# UNIT            — display unit for speeds. "MB" = megabytes per second (MBps), "Mb" = megabits per second (Mbps)
UNIT="MB"
```

| Setting | Default | Description |
|---|---|---|
| `THRESHOLD_MBPS` | `2` | Network speed (in your chosen unit) below which traffic is considered idle. Decimals work — `0.5` is valid. |
| `QUIET_MINUTES` | `15` | How many consecutive minutes below the threshold before the sleep lock is released. |
| `UNIT` | `"MB"` | Display unit. `"MB"` for megabytes/s (what Steam and file managers show). `"Mb"` for megabits/s (what ISPs advertise — multiply MB/s by 8 to convert). |

### MB/s vs Mb/s

These are two different ways to measure the same thing:

- **MB/s** (megabytes per second) — used by Steam, torrent clients, file managers. 1 MB/s = 8 Mb/s.
- **Mb/s** (megabits per second) — used by ISPs and speed test sites. If your ISP gives you "100 Mbps", that's about 12.5 MB/s.

Set `UNIT` to match whichever you think in, then set `THRESHOLD_MBPS` in that unit. The script handles the conversion internally.

## How it works

1. On launch, the script registers a sleep inhibitor with `systemd-inhibit --mode=block`, which prevents the system from sleeping for any reason (suspend, hibernate, idle timeout) while the inhibitor is held.
2. Every second it reads raw byte counters from `/proc/net/dev`, skipping the loopback interface (`lo`), and calculates current download and upload speeds.
3. If total speed is above `THRESHOLD_MBPS`, the countdown timer resets to `QUIET_MINUTES`.
4. If total speed stays below the threshold for the full `QUIET_MINUTES` duration, the script exits cleanly — releasing the inhibitor and allowing the system to sleep as normal.
5. Pressing **Ctrl-C** releases the inhibitor immediately.

You can verify the inhibitor is active while the script is running:

```bash
systemd-inhibit --list
```

You should see a `net-sleep-guard` entry with the reason shown as the current threshold.

## Status indicators

The bottom row of the display shows the current state:

| Icon | Colour | Meaning |
|---|---|---|
| `●` | Green | Traffic above threshold — sleep is blocked |
| `◑` | Yellow | Traffic dropped below threshold — countdown started, more than halfway remaining |
| `◔` | Red | Countdown under halfway — sleep will unlock soon if traffic stays low |
| `○` | Red | Countdown reached zero — releasing inhibitor |

The progress bar tracks how far through the quiet-time countdown you are. Green means active traffic, yellow means cooling down, red means nearly idle.

## License

MIT
