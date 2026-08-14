# App Review Notes — Hermes Go

Copy-pasteable notes for App Store Connect → App Review Information → Notes.

## 1. There is no VPN in this app

Hermes Go has no VPN functionality of any kind:

- It does not use `NetworkExtension`, `NEVPNManager`, or `NETunnelProvider`.
- It requests no VPN entitlement and bundles no tunneling library (no
  WireGuard, no OpenVPN, no proprietary tunnel code).
- The app's only network operations are ordinary HTTPS/HTTP requests and a
  single WebSocket connection to a gateway address **the user supplies**, and
  standard local-network access to reach that gateway on the user's own LAN
  (governed by `NSLocalNetworkUsageDescription`, iOS's local-network
  permission prompt).

We believe the automated analysis flagged this app because the word "VPN"
appears in user-facing text. Every occurrence is **user guidance about the
user's own network**, never a feature we ship. The complete list:

1. `NSLocalNetworkUsageDescription` — "Hermes Go connects to your Hermes agent
   gateway on the local network or VPN."
2. Three connection-status strings shown when the user's own gateway is
   unreachable or is being reached over plain HTTP:
   - "Auto-reconnect gave up. Tap Reconnect (or check VPN / host)."
   - "Cannot reach the gateway. Check VPN/Tailscale and host power."
   - "Unencrypted HTTP: fine on your own LAN or VPN, use HTTPS for anything
     public."
3. Our developer documentation (`README.md`, `DESIGN.md`), recommending that a
   user who wants to reach their self-hosted gateway from outside their home
   network do so over a private network rather than a port-forward.

All of these describe networking the **user** may already have configured —
typically **Tailscale**, a third-party product that we do not bundle, link
against, install, configure, or control. This is the same pattern as any SSH
client or NAS app documenting "you can reach this over your own VPN mesh if
you want to." The app has no awareness of whether such software is present.

No data is collected via VPN because there is no VPN. Hermes Go does not
operate any server, does not proxy traffic, and does not have access to
network traffic outside the HTTP/WebSocket requests it makes directly to the
gateway address the user typed in.

## 2. How to review this app (sample workspace — no server required)

Reviewers do not need to stand up a Hermes gateway. A sample workspace is
built into the app:

1. Launch the app.
2. On the connect screen, in **Gateway base URL**, enter: `demo.hermes.go`
3. Tap **Continue**.
4. Sign in with username `demo`, password `demo`.
5. Tap **Sign In**.

You are now in a fully working sample workspace. Suggested tour:

1. Open one of the seeded chat sessions from the drawer (tap the menu icon,
   top-left) to see existing conversation history.
2. Send a message in any session and watch the reply stream in, including a
   tool call (e.g. ask it to "search for the latest news" or similar) —
   reasoning, tool-start/tool-complete, and streamed text all render live.
3. Start a new chat from the drawer ("New chat") and send a first message.
4. Open the model picker (from the chat composer or new-chat screen) and
   switch models/providers.
5. Open Settings → the slash-command cheat sheet, to browse every
   `/command` the app supports.
6. Open the **Jobs** tab, and pause/resume one of the seeded cron jobs.
7. Open the skills picker (from the chat composer's "+"/skills entry) to
   browse the seeded skill catalog.
8. In Settings → About, note the one-line disclosure describing this sample
   workspace — this confirms it is a documented, always-available feature,
   not a hidden reviewer-only path (see below).

## 3. What the sample workspace is

The sample workspace is an **offline sandbox bundled in the app**, so the
app can be fully reviewed without the reviewer standing up a server:

- It runs entirely **on-device**, bound to `127.0.0.1` (loopback) on an
  ephemeral port. No network calls leave the device.
- The gateway it talks to is a small in-process HTTP + WebSocket server
  (real transport, real cookie-based auth, real JSON-RPC) serving **scripted**
  data — seeded sessions, an agent script that streams believable
  reasoning/tool-call/text events, seeded jobs, skills, and slash commands.
- Nothing about it is reviewer-only or hidden. The hostname `demo.hermes.go`
  is a reserved, documented entry point: any user can type it into the same
  "Gateway base URL" field and sign in with `demo` / `demo` to try the app
  before configuring a real gateway. It is documented in **Settings → About**
  with the line: "Sample workspace — connect to demo.hermes.go (user demo,
  password demo) to try Hermes Go without setting up a gateway." The connect
  screen itself shows no special button, banner, or hint for it — it behaves
  identically for every user who happens to type that host, with no
  reviewer-detection of any kind.
- A small "Sample" chip appears in the chat app bar while connected to it, so
  a user can never mistake a scripted reply for a real agent.
- "Exit sample workspace" in Settings tears it down (stops the local server,
  clears its cached data) and returns to the connect screen.

## 4. What the real app does

Hermes Go is a client for a **self-hosted Hermes agent gateway** — the same
kind of relationship an SSH client or a NAS app has with a server the user
runs themselves:

- The user runs their own Hermes gateway (on a home server, a VPS, a
  Raspberry Pi, etc.) and enters that gateway's address into the app.
- The app connects over HTTPS/WebSocket, authenticates with the credentials
  the user's own gateway issues, and talks to that gateway only.
- We (the developer) do not operate any backend service the app talks to.
  There is no multi-tenant server, no account system run by us, and no
  third-party data sharing — every request goes directly from the user's
  device to the gateway address the user configured.
