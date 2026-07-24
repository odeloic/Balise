# Balise — architecture

A macOS menu bar app for seeing what is running on your Mac: processes, the
ports they hold, where they came from, and your Docker containers.

## The constraint everything follows from

`project.pbxproj` sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Every type
and function is on the main thread unless it says otherwise. The main thread
draws the interface, so any work done there freezes the menu.

So the whole design exists to hold one line: **code that draws is separate from
code that talks to the system.**

## Layers

```
Features   SwiftUI views + one @Observable store each     main thread
   |  asks
Services   talks to macOS and Docker                      off the main thread
   |  returns
Core       plain Sendable structs                         no thread, just data
```

The import statements are the boundary:

- `Core/` — no `import SwiftUI`, no system calls. Just data.
- `Services/` — knows the system, never `import SwiftUI`.
- `Features/` — knows the screen, never does system work.

If a view file needs `import Darwin`, something is in the wrong folder.

## Folders

```
Balise/
  Core/              data types, shared by everything
  Services/
    Process/         list processes and ports (libproc)
    Origin/          read code signatures (Security framework)
    Control/         send signals — the only place that can stop things
    Docker/          find the engine, talk to its API
    Fakes/           stand-in services, all of them, in one place
  Features/
    Processes/       store + view
    Docker/          store + view
  DesignSystem/      shared rows, badges, colours
```

## Rules

**1. Every service is a protocol first.**

Write `ProcessInspecting` before `LibprocProcessInspector`. Then add a fake
implementation returning canned data. This is what makes SwiftUI Previews work
— the preview canvas has no Docker and cannot inspect processes — and it is the
only way to test states like "Docker is not installed".

**2. Reads and writes are different services.**

Listing processes is safe and repeats every few seconds. Stopping one is
destructive, happens once, and needs a confirmation. They live in separate
files (`Services/Process/` vs `Services/Control/`) so the polling loop cannot
reach the stop code by accident.

**3. Scan when the menu opens. Nothing while it is shut.**

A full sweep is cheap — measured at 1.5 to 2.5 ms for 720 processes — but the
icon draws no live data, so a scan while the popover is closed produces
something nobody can see. Balise starts at login to be *resident*, not busy.
macOS agrees: App Nap throttles timers in hidden apps anyway.

This changes only if the icon ever carries a badge, like an open-port count.
That would force a background clock, and it is the line between an idle app and
an always-on one.

**4. Docker's address is discovered, never hardcoded.**

`/var/run/docker.sock` is wrong on plenty of Macs — on this one it is a dead
symlink while the real engine is Colima. Resolution order, first hit wins:

1. `DOCKER_HOST` environment variable
2. `DOCKER_CONTEXT` environment variable, resolved through the context files
3. `currentContext` in `~/.docker/config.json`, same resolution
4. the `default` context, meaning `/var/run/docker.sock`
5. probing known paths for Docker Desktop, Colima, OrbStack, Rancher, Lima

A context's endpoint lives in a folder named after the **SHA-256 hash of the
context name**:

```
~/.docker/contexts/meta/<sha256(name)>/meta.json
```

Two traps:

- **A launched app does not see your shell environment.** `launchctl getenv PATH`
  comes back empty. Anything exported in `.zshrc` is invisible to Balise, so
  steps 1 and 2 will usually miss even when they work in Terminal. Running from
  Xcode may inherit the shell and hide this — test the built app from Finder.
- **Existence is not reachability.** A dead symlink passes a file check. The
  only real test is to connect and ask `/version`.

"No Docker installed" is a normal state with its own calm empty view, not an error.

**5. `URLSession` cannot open a unix socket.**

Docker's API is HTTP over a file socket. Apple's HTTP client will not do that.
Use `NWConnection` with `NWEndpoint.unix(path:)` and write the request by hand.
Keep that plumbing in its own file, apart from anything that knows what a
container is.

## What a row is

One row per listening port, split by address family. Postgres listening over
both IPv4 and IPv6 is two rows, because that is what the machine reports and
merging them hides a real fact. `ListeningPort.id` carries the family for
exactly this reason.

The row shows port, process name, source, address family and — when it is not
yours — the owner. Opening a row adds process id, path, working folder,
command line and start time.

**Source is read off the path, not the signature.** `/opt/homebrew/…` is
Homebrew, `/Applications/Foo.app/…` is Foo, `/System/…` is macOS. Free, and it
is the thing you want to know day to day. The verified answer, `CodeOrigin`,
costs a disk read plus a signature check per process, so it belongs on a row
the user has opened, never on the list.

**Working folder is how you tell two `node` processes apart.** Measured: it
comes back as the project folder. On its own it can mislead — an editor's
helper inherits the folder of the project it was launched from — so it is shown
next to the command line, not instead of it.

## Build settings

- `ENABLE_APP_SANDBOX` is `NO`. Measured, not assumed: under the sandbox both a
  libproc scan and a connect to the Docker socket are killed outright (exit
  133), even with `com.apple.security.network.client` granted. No entitlement
  opens either one. This rules out the Mac App Store — Balise ships signed and
  notarised with a Developer ID instead.
- `ENABLE_HARDENED_RUNTIME` stays `YES`. It is required for notarisation and
  blocks nothing Balise needs; both the process scan and the socket connect
  were verified working with it on.
- `SWIFT_VERSION` is `5.0`. `Core/` already compiles clean under `6.0`. Move
  when the shape settles; it turns thread mistakes into compile errors.
- `ENABLE_USER_SELECTED_FILES = readonly` is left over from the sandbox and now
  does nothing. Harmless, clear it whenever.

## Keep non-source files out of `Balise/`

The target uses a file-system synchronised group, so anything under `Balise/`
joins the build on its own. Non-source files get copied into the app bundle as
resources, and several files sharing a name collide on one output path and fail
the build — seven `.gitkeep` files did exactly that.

So empty folders carry no placeholder, which also means git does not track
them. They become real the moment the first Swift file lands. The layout above
is the reference, not the folders on disk.
