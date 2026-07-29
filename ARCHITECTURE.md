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

On disk today: `Core/`, `Services/Process/`, `Services/Control/`,
`Services/Fakes/`, `Features/Processes/`, `DesignSystem/`. `Services/Origin/`,
`Services/Docker/` and `Features/Docker/` have no files yet.

## Rules

Each rule carries a note saying whether it is honoured by code today or is
still only a decision. Anything marked *not yet committed* is on `feat/libroc`.

**1. Every service is a protocol first.**

*Built for processes. Docker has neither a protocol nor a fake yet.*

Write `ProcessInspecting` before `LibprocProcessInspector`. Then add a fake
implementation returning canned data. This is what makes SwiftUI Previews work
— the preview canvas has no Docker and cannot inspect processes — and it is the
only way to test states like "Docker is not installed".

**2. Reads and writes are different services.**

*Built. Both protocols in d6ddbfe; `LibprocProcessInspector` and
`SignalProcessController` behind them, not yet committed.*

Listing processes is safe and repeats every few seconds. Stopping one is
destructive, happens once, and needs a confirmation. They live in separate
files (`Services/Process/` vs `Services/Control/`) so the polling loop cannot
reach the stop code by accident.

**3. Scan when the menu opens. Nothing while it is shut.**

*Built. `ProcessListView` scans from `.task`, d6ddbfe. There is no timer
anywhere in the app.*

A full sweep is cheap — measured at 1.5 to 2.5 ms for 720 processes — but the
icon draws no live data, so a scan while the popover is closed produces
something nobody can see. Balise starts at login to be *resident*, not busy.
macOS agrees: App Nap throttles timers in hidden apps anyway.

This changes only if the icon ever carries a badge, like an open-port count.
That would force a background clock, and it is the line between an idle app and
an always-on one.

**4. Docker's address is discovered, never hardcoded.**

*Not built. Only the `DockerEndpoint(hostString:)` parser exists, in `Core/`,
dbd758c. Nothing looks for a context or a socket yet.*

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

*Not built. No `NWConnection` code exists.*

Docker's API is HTTP over a file socket. Apple's HTTP client will not do that.
Use `NWConnection` with `NWEndpoint.unix(path:)` and write the request by hand.
Keep that plumbing in its own file, apart from anything that knows what a
container is.

**6. A service that touches the system is an actor, not a struct.**

*Built, not yet committed. Learned while writing the two real services, so it
is younger than rules 1 to 5.*

`SWIFT_APPROACHABLE_CONCURRENCY` is on, and it brings
`NonisolatedNonsendingByDefault` with it. Under that rule a `nonisolated async`
function runs on **whoever called it** — and the caller is a store, on the main
thread. Marking a service `nonisolated` buys nothing.

Measured, not assumed: a `nonisolated async` method called from a `@MainActor`
test reports `Thread.isMainThread == true`. The same call on an actor reports
`false`.

So `LibprocProcessInspector` and `SignalProcessController` are actors. That is
what keeps a 3 ms sweep, and a 1.5 second wait for a process to quit, off the
thread that draws.

## What a row is

*Built in d6ddbfe against the fakes, and filled with real data since. The one
gap: `CodeOrigin` is still only a type — nothing reads a signature yet, so an
opened row shows no verified origin.*

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

## What libproc will and will not tell you

*Built, not yet committed. `Services/Process/Libproc.swift` holds the calls,
`LibprocProcessInspector.swift` the sweep.*

Measured on this Mac: 791 processes, 35 listening ports held by 17 of them, 248
processes macOS refused to open. One full sweep, command lines included, takes
3.1 to 4.2 ms.

Three things the documentation does not say:

- **A refusal comes back as `0`, not `-1`.**
  `proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)` answers `0` with `errno == EPERM`
  for a process you may not open. Reading that as "has no file descriptors"
  quietly drops a third of the machine and leaves `unreadableProcessCount` at
  zero, which is the number that stops a short list reading as "nothing runs".

- **`PROC_PIDTBSDINFO` is refused across accounts. `PROC_PIDT_SHORTBSDINFO` is not.**
  `launchd` answers `EPERM` to the first and hands over its name and user id to
  the second. That is how a refused stop can still say *which* process it failed
  to stop.

- **One socket can sit behind several file descriptors**, after a `fork` or a
  `dup`. `ListeningPort.id` is what collapses them. Without it a shared socket
  is two identical rows.

The command line comes from `sysctl KERN_PROCARGS2`, which costs far more than
the rest. It is read only for processes that hold a port — 17 here, not 791 —
which is why the scan can afford it up front rather than on demand.

## Tests

*Built, not yet committed. 75 tests, green five runs in a row. Nothing covers
Docker or `CodeOrigin`, because neither exists.*

`BaliseTests` is a unit test target hosted in `Balise.app`. Hosting is what
makes `@testable import Balise` work, and it means the tests run inside the
real, signed, hardened-runtime app rather than a bare bundle.

```
BaliseTests/
  Core/        pure data types, no machine involved
  Features/    stores, driven by fakes and stubs
  Services/    the C layer, plus real sweeps of this Mac
  Support/     fixtures, stubs, sockets and processes to stop
```

Run them with ⌘U, or:

```
xcodebuild test -project Balise.xcodeproj -scheme Balise -destination 'platform=macOS'
```

The scheme is shared, in `xcshareddata/`, so the test action does not depend on
anyone's local Xcode state.

Three things learned the hard way:

**Break the code on purpose before trusting a test.** Deleting the re-entrancy
guard in `ProcessListStore.refresh` first made its test *hang* rather than fail:
the fake was holding a gate nobody would ever open. `GatedProcessInspector` now
holds only the first scan, so the same break fails in a millisecond with a
readable message.

**A test must ask the same question the code asks.** `Orphan.waitUntilGone`
first used `bsdInfo`, which stops answering for a process that has died but not
yet been reaped, while the controller uses `kill(pid, 0)`, which still says yes.
One run in three failed until both used the same test.

**Processes started by a test are deliberately not its children.** A dead child
stays a zombie until its parent reaps it, and a zombie still answers
`kill(pid, 0)`. `Orphan` hands the job to a shell that then exits, so the
process is parented to `launchd` and reaped at once. That is also the truer
shape: Balise stops other people's processes, never its own children.

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
- `SWIFT_APPROACHABLE_CONCURRENCY` is `YES`. Read rule 6 before writing a
  service — it changes where a `nonisolated async` function runs.
- `ENABLE_TESTABILITY` is `YES` in Debug, which is what `@testable import`
  needs. `BaliseTests` carries the same `SWIFT_DEFAULT_ACTOR_ISOLATION` and
  `SWIFT_APPROACHABLE_CONCURRENCY` as the app, so a test sees the same rules
  the code does.
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
