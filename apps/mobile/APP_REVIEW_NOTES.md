# App Review Notes for Hermes Go

Two paste blocks. No em dashes anywhere, because App Store Connect mangles
them. The Notes block is kept under the 4000 character limit of the App
Review Information field.

---

## BLOCK A: paste into App Review Information, then Notes

<!-- BEGIN NOTES BLOCK -->
DEMO ACCESS (no server required)

Hermes Go is a client for a Hermes agent gateway that the user runs on their
own computer, in the same way an SSH client or a NAS app talks to a server the
user runs. Reviewers do not need to set one up. A sample workspace is built
into the app.

To sign in:
1. Launch the app.
2. On the connect screen, in "Gateway base URL", enter: demo.hermes.go
3. Tap Continue.
4. Username: demo
5. Password: demo
6. Tap Sign In.

Suggested tour:
1. Open a seeded chat session from the drawer (menu icon, top left) to see
   existing conversation history.
2. Send a message in any session and watch the reply stream in, including a
   tool call. Try "search for the latest news". Reasoning, tool start, tool
   finish and streamed text all render live.
3. Start a new chat from the drawer ("New chat") and send a first message.
4. Open the model picker from the chat composer and switch models or
   providers.
5. Open Settings, then the slash command cheat sheet, to browse every
   /command the app supports.
6. Open the Jobs tab and pause or resume one of the seeded cron jobs.
7. Open the skills picker from the composer's "+" entry to browse the seeded
   skill catalog.
8. Open Settings, then About, and note the one line describing this sample
   workspace.

WHAT THE SAMPLE WORKSPACE IS

An offline sandbox bundled in the app, so the app can be fully reviewed
without the reviewer standing up a server.

It runs entirely on device, bound to 127.0.0.1 (loopback) on an ephemeral
port. No network calls leave the device. It is a small in-process HTTP and
WebSocket server with real transport, real cookie based authentication and
real JSON-RPC, serving scripted data: seeded sessions, an agent script that
streams reasoning, tool calls and text, plus seeded jobs, skills and slash
commands.

Nothing about it is reviewer only or hidden. The hostname demo.hermes.go is a
reserved, documented entry point. Any user can type it into the same "Gateway
base URL" field and sign in with demo / demo to try the app before setting up
a real gateway. It is documented in Settings, then About, with this line:
"Sample workspace, connect to demo.hermes.go (user demo, password demo) to
try Hermes Go without setting up a gateway." The connect screen shows no
special button, banner or hint for it, and the app performs no reviewer
detection of any kind.

A small "Sample" chip appears in the chat title bar while connected, so a
scripted reply can never be mistaken for a real agent. "Exit sample
workspace" in Settings stops the local server, clears its cached data and
returns to the connect screen.

NO VPN FUNCTIONALITY

This app contains no VPN feature. It does not use NetworkExtension,
NEVPNManager or NETunnelProvider, requests no VPN entitlement, and bundles no
tunneling library. It collects no user information via VPN, because there is
no VPN, and no data is shared with third parties. The word "VPN" appears only
as guidance about the user's own network: the NSLocalNetworkUsageDescription
string, and three connection status messages that suggest checking a VPN or
Tailscale when the user's own gateway is unreachable. Tailscale is a third
party product that we do not bundle, link against, install or control.

WHAT THE REAL APP DOES

The user runs their own Hermes gateway on a home server, a VPS or similar,
and enters that address into the app. The app connects over HTTPS and
WebSocket, authenticates with credentials that the user's own gateway issues,
and talks to that gateway only. We operate no backend service. There is no
multi-tenant server, no account system run by us, and no third party data
sharing. Every request goes directly from the user's device to the gateway
address the user configured.
<!-- END NOTES BLOCK -->

---

## BLOCK B: reply to the Guideline 2.1(a) message about a demo authentication code

Submission ID cef05d7f-02cd-4c0a-884d-abe10b3daebd, reviewed August 05 2026.
This is the message asking for an authentication code and offering a call.

<!-- BEGIN AUTHCODE REPLY BLOCK -->
Thank you for the review, and for setting out the options.

There is no authentication code for this app, and none exists to give you. I
can see why the previous build looked as though there was one, and I am sorry
for the wasted round trip.

Hermes Go is a client for a Hermes agent gateway that the user runs on their
own computer, in the same way an SSH client or a NAS app connects to a server
the user runs themselves. The first field on the connect screen asks for that
server's address, not for a code. The username and password are issued by the
user's own server. In build 5 we supplied credentials but no reachable server,
so there was nothing for the reviewer to sign in to and no way past the first
screen. That was our mistake.

We have taken the third option you recommended, "including a demonstration
mode that exhibits the app's full features and functionality". It is bundled
in the new build and needs no server, no code and no network access.

To sign in:
1. Launch the app.
2. On the connect screen, in "Gateway base URL", enter: demo.hermes.go
3. Tap Continue.
4. Username: demo
5. Password: demo
6. Tap Sign In.

That gives you a fully working sample workspace with existing chat history.
You can send messages and watch replies stream in with live tool calls, start
new chats, switch models, browse the slash command reference and the skills
catalog, and pause or resume scheduled jobs. A suggested tour is in the App
Review Information notes for this version.

The sample workspace runs entirely on the device, on 127.0.0.1, and no network
calls leave the device. It is available to every user, not only to reviewers:
the same host and credentials work for anyone, it is documented in the app
under Settings, then About, and the app performs no reviewer detection of any
kind. A "Sample" chip is shown while it is active so that its scripted replies
can never be mistaken for a real agent.

A call should not be necessary, since there is no code to convey. If anything
in the sample workspace does not behave as described, please tell me what you
saw and I will fix it promptly.

Thank you,
Tom
<!-- END AUTHCODE REPLY BLOCK -->

---

## BLOCK C: reply to the earlier VPN message

<!-- BEGIN REPLY BLOCK -->
Thank you for the review.

Regarding the VPN question, Hermes Go has no VPN functionality of any kind:

- It does not use NetworkExtension, NEVPNManager or NETunnelProvider.
- It requests no VPN entitlement and bundles no tunneling library. There is
  no WireGuard, no OpenVPN and no proprietary tunnel code.
- Its only network operations are ordinary HTTPS and HTTP requests plus a
  single WebSocket connection to a gateway address the user supplies, and
  standard local network access to reach that gateway on the user's own LAN,
  governed by NSLocalNetworkUsageDescription.

To answer the three specific questions: the app collects no user information
using VPN, because it has no VPN functionality. There is therefore no purpose
for which such data is collected, and no data is shared with any third party.
Chat messages travel directly between the user's device and the user's own
self-hosted gateway. We operate no server in that path.

We believe the automated analysis flagged the app because the word "VPN"
appears in user-facing text. Every occurrence is guidance about the user's own
network, never a feature we ship. The complete list:

1. NSLocalNetworkUsageDescription: "Hermes Go connects to your Hermes agent
   gateway on the local network or VPN."
2. Three connection status messages, shown when the user's own gateway is
   unreachable or is being reached over plain HTTP:
   "Auto-reconnect gave up. Tap Reconnect (or check VPN / host)."
   "Cannot reach the gateway. Check VPN/Tailscale and host power."
   "Unencrypted HTTP: fine on your own LAN or VPN, use HTTPS for anything
   public."
3. Our developer documentation, which recommends that a user who wants to
   reach their self-hosted gateway from outside their home network do so over
   a private network rather than a port forward.

All of these describe networking the user may already have configured,
typically Tailscale, a third party product that we do not bundle, link
against, install, configure or control. The app has no awareness of whether
such software is present. This is the same pattern as an SSH client or a NAS
app documenting that you can reach your own server over your own VPN if you
choose to.

Regarding demo access, we have added a sample workspace to the build so that
review can proceed without setting up a server. Full sign-in steps and a
suggested tour are in the App Review Information notes for this version.

Thank you,
Tom
<!-- END REPLY BLOCK -->
