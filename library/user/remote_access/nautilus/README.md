<h2 align="center">Nautilus</h2>
<p align="center">
<img alt="Nautilus Logo" width="200" src="www/nautilus_logo.png" />
</p>
<p align="center">
<i>Dive deep into your payloads</i>
</p>

<p align="center">
<img src="https://img.shields.io/badge/Platform-WiFi%20Pineapple%20Pager-00d4aa?style=flat-square" />
<img src="https://img.shields.io/badge/Version-1.0-blue?style=flat-square" />
<img src="https://img.shields.io/badge/Author-JustSomeTrout-purple?style=flat-square" />
</p>

```
    Title: Nautilus
    Author: JustSomeTrout (Trout / troot.)
    Developed for Firmware version 1.0.4
    Category: General / Utility
    Web-based payload launcher and console.
    Control your Pager from any device on the network.
    *Humans were harmed in the making of this payload*
```

<p align="center">
<img width="1675" height="1098" alt="Nautilus Dashboard" src="https://github.com/user-attachments/assets/b8538b40-b585-4828-9819-cf73c137980b" />
</p>

<p align="center">
<img width="600" height="4" alt="" src="https://github.com/user-attachments/assets/8560a6c9-b1f1-4eed-ac94-bd9e14d36ac5" />
</p>

## Overview

**Nautilus** transforms your WiFi Pineapple Pager into a web-accessible payload command center. Launch, monitor, and interact with payloads from your phone, laptop, tablet, or any device with a browser.

**Nautilus answers the question:**

> *Why go through pages on pages to find your payload?*

No more fumbling with D-pad navigation. Just point, click, and watch the magic happen in real-time.

<p align="center">
<img width="600" height="4" alt="" src="https://github.com/user-attachments/assets/8560a6c9-b1f1-4eed-ac94-bd9e14d36ac5" />
</p>

## Features

### Core Functionality
- **Browse All Payloads**: Organized by category with collapsible sections
- **Search**: Find payloads instantly with live filtering
- **Payload Details**: View title, description, author, and version
- **One-Click Execution**: Run any payload with a single tap
- **Live Console**: Watch output stream in real-time with color support
- **Stop Control**: Abort running payloads at any time

### Interactive Prompts
Nautilus intercepts and displays DuckyScript prompts in the web UI:

| Command | Web UI |
|---------|--------|
| `CONFIRMATION_DIALOG` | Yes/No modal dialog |
| `TEXT_PICKER` | Text input with default value |
| `NUMBER_PICKER` | Number input with default value |
| `IP_PICKER` | IP address input with validation |
| `MAC_PICKER` | MAC address input with validation |
| `PROMPT` | Generic text input |

Your response is sent back to the payload — no pager interaction required!

<p align="center">
<img width="600" height="4" alt="" src="https://github.com/user-attachments/assets/8560a6c9-b1f1-4eed-ac94-bd9e14d36ac5" />
</p>

## Requirements

### Dependencies

**Auto-Install**: On first run, Nautilus will prompt to install `uhttpd` if it's missing. Just confirm and it handles the rest.

<p align="center">
<img width="600" height="4" alt="" src="https://github.com/user-attachments/assets/8560a6c9-b1f1-4eed-ac94-bd9e14d36ac5" />
</p>

## How It Works

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Your Device (Phone/Laptop/etc)                             │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Browser → http://172.16.42.1:8888                    │  │
│  │  ├── Sidebar: Browse payloads                         │  │
│  │  ├── Console: Live SSE stream                         │  │
│  │  └── Modals: Interactive prompts                      │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ HTTP/SSE
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  WiFi Pineapple Pager                                       │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  uhttpd (port 8888)                                   │  │
│  │  └── /cgi-bin/api.sh                                  │  │
│  │      ├── list    → JSON payload catalog               │  │
│  │      ├── run     → Launch wrapper + SSE stream        │  │
│  │      ├── stop    → Kill running payload               │  │
│  │      ├── respond → Send prompt response               │  │
│  │      └── refresh → Rebuild payload cache              │  │
│  └───────────────────────────────────────────────────────┘  │
│                              │                              │
│                              ▼                              │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Wrapper Script (intercepts DuckyScript commands)     │  │
│  │  ├── LOG()              → Echo + real command         │  │
│  │  ├── LED()              → Echo + real command         │  │
│  │  ├── ALERT()            → Echo + real command         │  │
│  │  ├── CONFIRMATION_DIALOG → Prompt via SSE             │  │
│  │  ├── TEXT_PICKER        → Prompt via SSE              │  │
│  │  ├── NUMBER_PICKER      → Prompt via SSE              │  │
│  │  ├── IP_PICKER          → Prompt via SSE              │  │
│  │  └── MAC_PICKER         → Prompt via SSE              │  │
│  └───────────────────────────────────────────────────────┘  │
│                              │                              │
│                              ▼                              │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Your Payload (payload.sh)                            │  │
│  │  Runs with wrapper functions overriding real commands │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### Nautilus Payload Wrapper

When you run a payload through Nautilus, it doesn't run directly. Instead:

1. **Wrapper Created**: A temporary script defines wrapper functions for all DuckyScript commands
2. **Functions Exported**: `LOG`, `LED`, `CONFIRMATION_DIALOG`, etc. are exported to subshells
3. **Payload Sourced**: Your payload runs with wrapper functions taking precedence
4. **Output Captured**: All stdout/stderr streams to `/tmp/nautilus_output.log`
5. **SSE Polling**: The CGI backend polls the log file every 200ms for new lines
6. **Prompts Detected**: Special `[PROMPT:type]` markers in output trigger web modals
7. **Responses Returned**: User input writes to `/tmp/nautilus_response`, which the wrapper polls

### Response Flow

When a prompt appears in the web UI:

```
1. Payload calls: result=$(CONFIRMATION_DIALOG "Continue?")
2. Wrapper writes: [PROMPT:confirm] Continue?  → stderr → log file
3. CGI detects prompt marker, sends SSE event to browser
4. Browser shows modal, user clicks "Yes"
5. Browser calls: /api.sh?action=respond&response=1
6. CGI writes "1" to /tmp/nautilus_response
7. Wrapper's _wait_response() sees file, reads "1", returns it
8. CONFIRMATION_DIALOG echoes "1" to stdout
9. Payload receives: result="1"
```

### File-Based Communication

We use simple files instead of FIFOs for reliability:

| File | Purpose |
|------|---------|
| `/tmp/nautilus_output.log` | All payload output (stdout + stderr) |
| `/tmp/nautilus_response` | User's response to current prompt |
| `/tmp/nautilus_payload.pid` | PID of running wrapper process |
| `/tmp/nautilus_cache.json` | Pre-built payload catalog |
| `/tmp/nautilus_wrapper_$$.sh` | Generated wrapper script |

### Server-Sent Events (SSE)

Instead of polling for updates, Nautilus uses SSE for efficient real-time streaming.

<p align="center">
<img width="600" height="4" alt="" src="https://github.com/user-attachments/assets/8560a6c9-b1f1-4eed-ac94-bd9e14d36ac5" />
</p>

## Installation

1. Copy the `nautilus` folder to your Pager:
   ```
   /root/payloads/user/general/nautilus/
   ```

2. The payload will appear in the Pager's menu under **General**.

### File Structure

```
nautilus/
├── payload.sh          # Main launcher (starts server, builds cache)
├── build_cache.sh      # Scans payloads, generates JSON catalog
├── README.md           # You are here
└── www/
    ├── index.html      # Single-file web UI (~15KB)
    └── cgi-bin/
        └── api.sh      # CGI backend (list, run, stop, respond)
```

<p align="center">
<img width="600" height="4" alt="" src="https://github.com/user-attachments/assets/8560a6c9-b1f1-4eed-ac94-bd9e14d36ac5" />
</p>

## Usage

### Starting Nautilus

1. Navigate to **General → Nautilus** on your Pager
2. Press **A** to run
3. The display shows the server URL:
   ```
   Nautilus running
   http://172.16.42.1:8888
   Press B to stop
   ```
4. Open that URL in any browser on the same network

### Using the Web Interface

1. **Browse**: Payloads are organized by category in the left sidebar
2. **Search**: Type to filter payloads instantly
3. **Select**: Click a payload to see details
4. **Run**: Click the green **Run Payload** button
5. **Watch**: Output streams to the console in real-time
6. **Interact**: Prompts appear as modal dialogs — respond and continue
7. **Stop**: Click **Stop** to abort a running payload

### Stopping Nautilus

- Press **B** on the Pager, OR

<p align="center">
<img width="600" height="4" alt="" src="https://github.com/user-attachments/assets/8560a6c9-b1f1-4eed-ac94-bd9e14d36ac5" />
</p>

## Supported DuckyScript Commands

### Output Commands (Displayed in Console)

| Command | Behavior |
|---------|----------|
| `LOG "message"` | Displays in console |
| `LOG green "message"` | Displays with color |
| `LED SETUP` | Shows LED status |
| `ALERT "message"` | Shows as yellow alert |
| `ERROR_DIALOG "message"` | Shows as red error |
| `SPINNER "message"` | Shows spinner status |
| `SPINNER_STOP` | Shows spinner stopped |

### Interactive Commands (Web Modals)

| Command | Modal Type | Returns |
|---------|------------|---------|
| `CONFIRMATION_DIALOG "msg"` | Yes/No buttons | `1` or `0` |
| `TEXT_PICKER "title" "default"` | Text input | User's text |
| `NUMBER_PICKER "title" "42"` | Number input | User's number |
| `IP_PICKER "title" "192.168.1.1"` | IP input | IP address |
| `MAC_PICKER "title" "00:11:22:33:44:55"` | MAC input | MAC address |
| `PROMPT "message"` | Text input | User's text |

### Passthrough Commands

These commands execute on the Pager AND show status in the console:
- `LED` 
- `ALERT`
- Real system commands work normally

<p align="center">
<img width="600" height="4" alt="" src="https://github.com/user-attachments/assets/8560a6c9-b1f1-4eed-ac94-bd9e14d36ac5" />
</p>

## Technical Details

### Stack
- **Web Server**: uhttpd (built into OpenWrt)
- **Backend**: Pure shell script CGI
- **Frontend**: Vanilla HTML/CSS/JS (no frameworks, no dependencies)
- **Streaming**: Server-Sent Events (SSE)
- **Port**: 8888

### Performance
- **Startup**: ~2 seconds to build payload cache
- **Cache**: JSON catalog stored in `/tmp` for instant listing
- **Streaming**: 200ms polling interval for smooth output
- **Size**: ~15KB total (HTML + CSS + JS inlined)

### Security Considerations
- Only accessible from the local network
- Path validation prevents directory traversal
- Payload paths must start with `/root/payloads/`

<p align="center">
<img width="600" height="4" alt="" src="https://github.com/user-attachments/assets/8560a6c9-b1f1-4eed-ac94-bd9e14d36ac5" />
</p>

## Troubleshooting

### "Cache not ready" error
The payload cache is building. Wait 2 seconds and refresh, or click the refresh button.

### Payloads not appearing
Click the **↻** refresh button in the header to rebuild the cache.

### Prompts not showing
Make sure you're using the standard DuckyScript prompt commands. Check the console for `[PROMPT:...]` markers.

### Console stops updating
The SSE connection may have timed out. Refresh the page and run again.

### Can't connect to server
1. Make sure Nautilus is running (check Pager display)
2. Verify you're on the same network as the Pager
3. Try the IP: `http://172.16.42.1:8888`

<p align="center">
<img width="600" height="4" alt="" src="https://github.com/user-attachments/assets/8560a6c9-b1f1-4eed-ac94-bd9e14d36ac5" />
</p>