# omarchy-companion-display

An always-on companion display for a secondary (vertical) monitor on [Omarchy](https://omarchy.org/).

It turns a spare screen into a quiet, glanceable dashboard:

- **Chats from your phone** via [KDE Connect](https://kdeconnect.kde.org/): WhatsApp, Telegram, Signal… grouped by chat with the latest message. They disappear when you read them on the phone; hover one and press ✕ to dismiss it on the phone too.
- **Mail** built from notifications: desktop mail clients (e.g. BlueMail) and mail apps on the phone (Outlook, Gmail) via KDE Connect. No credentials needed. Click the counter to mark everything as seen.
- **Other phone notifications**, counted per app.
- **Media player** (any MPRIS player: Spotify, the phone through KDE Connect, browsers): a compact bar at the bottom that expands to a full player.
- **Claude Code sessions**: a one-line counter at the bottom (working, done, waiting, idle) that expands to list every open session and how long ago it changed, plus usage limits from Omarchy's agents usage records.
- **Burn-in care**: dark palette with no white areas, a slow pixel shift, and an idle mode (pure black, small dim block that moves around) after a few minutes without news.

## Requirements

- Omarchy with the Quickshell-based shell (plugin support)
- `kdeconnect` paired with your phone, for chats and phone notifications
- Python 3 with PyGObject (ships with Omarchy)

## Install

```bash
omarchy plugin add https://github.com/apuyana/omarchy-companion-display.git --enable
cp ~/.config/omarchy/plugins/apuyana.companion-display/config.example.json ~/.config/omarchy/companion-display.json
```

Then set `screen` in `~/.config/omarchy/companion-display.json` to the monitor you want (see `hyprctl monitors`). The config is reloaded on save.

For development, link your checkout instead:

```bash
ln -s ~/path/to/omarchy-companion-display ~/.config/omarchy/plugins/apuyana.companion-display
omarchy-shell shell rescanPlugins && omarchy plugin enable apuyana.companion-display
```

QML changes need `omarchy restart shell` to show up, because the panel stays loaded.

## Configuration

`~/.config/omarchy/companion-display.json`:

| Key | Default | What it does |
|---|---|---|
| `screen` | `HDMI-A-1` | Monitor name to draw on |
| `locale` | `en_US` | Locale for the date |
| `dateFormat` | `dddd, MMMM d` | Qt date format under the clock |
| `idleSeconds` | `300` | Seconds without news (or mouse movement on the panel) before idle mode |
| `privacy` | `false` | Hide message and mail text, show only senders and counts |
| `hideBar` | `false` | Cover the Omarchy bar on this monitor with a black strip (burn-in) |
| `chatApps` | WhatsApp, Telegram, Signal… | Phone apps shown as chats |
| `mailApps` | `["BlueMail"]` | Desktop apps whose notifications count as mail |
| `phoneMailApps` | Outlook, Gmail, BlueMail | Phone apps whose notifications count as mail |
| `ignoreApps` | `[]` | Phone apps to leave out |
| `mailHistory` | `30` | Desktop mails kept |
| `paperclip` | `{}` | Paperclip instance, see below |
| `claude.expanded` | `false` | Start with the Claude session list open |
| `claude.doneMinutes` | `15` | Minutes a finished session shows as "done" before it turns idle |
| `modules` | all `true` | Turn sections off: `clock`, `paperclip`, `mail`, `chats`, `apps`, `player`, `claude` |

### Paperclip (optional)

Shows task counts (blocked, in review, in progress, pending approvals), agent availability and the latest blocked or in-review tasks from a [Paperclip](https://github.com/paperclipai/paperclip) instance. Add to the config:

```json
"paperclip": {
  "url": "https://paperclip.example.com",
  "companyId": "<company uuid>",
  "name": "My Company",
  "interval": 60,
  "maxIssues": 4
}
```

It needs a board API key in `~/.config/omarchy/companion-display-paperclip.token`. If the Paperclip CLI is logged in (`paperclipai auth login`), create one with:

```bash
~/.config/omarchy/plugins/apuyana.companion-display/bin/paperclip-create-key https://paperclip.example.com
```

The key is named `companion-display`, expires in a year by default, and is never printed. The panel only reads from Paperclip, but a board key has your full board permissions, so keep the file private.

### Phone shows "Sensitive notification content hidden"

Android hides the content of some notifications from KDE Connect. On the phone, allow sensitive notification content (Settings › Notifications, or the app's own notification settings) to see senders and text.

## How it works

`bin/companion-feed` is a small Python process that reads KDE Connect over D-Bus, listens to desktop `Notify` calls for mail apps, and prints the combined state as JSON lines. `Panel.qml` runs it, draws the panel on the Bottom layer of the chosen monitor (windows on that monitor still cover it), and reads MPRIS and the Claude usage record directly. Mail state lives in `~/.local/state/omarchy-companion-display/`.

## License

[MIT](LICENSE)
