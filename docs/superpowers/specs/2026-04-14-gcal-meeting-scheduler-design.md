# Google Calendar Meeting Scheduler — Design Spec

## Overview

Two components that give Claude the ability to query Google Calendar and book
meetings on Mat's behalf using the `gws` (Google Workspace CLI).

- **Skill (`gws-calendar`)** — CLI knowledge layer for all calendar operations
- **Command (`/book-meeting`)** — scheduling workflow with pre-authorized permissions

## Prerequisites

- `gws` CLI installed and authenticated (`gws auth login --scopes calendar`)
- OAuth app: `agentic-workflows-gcal` (Internal, agilebits.com org)
- Scopes: `calendar`, `email`, `profile`, `cloud-platform`
- Reader access to colleagues' calendars (org default)

### Known Limitations

- **No Zoom links via API.** The Zoom-Calendar add-on only fires in the browser
  UI. Events are created without a video link; attendees add Zoom manually from
  the Google Calendar web UI. Future upgrade: Zoom API OAuth integration.
- **No directory lookup.** The `directory.readonly` scope is blocked by org
  policy. Attendee emails must be provided directly. Future upgrade: request
  scope from IT, or use People API `searchDirectoryPeople`.
- **No cross-user working hours.** Google does not expose other users' working
  hours setting via the API (open feature request since 2018). We infer time
  zone from their calendar and default to 10am-5pm in that zone.

## Component 1: Skill — `gws-calendar`

**Location:** `claude-config/skills/gws-calendar/SKILL.md`

**Purpose:** Teach Claude the gws calendar CLI so it can handle ad-hoc calendar
queries ("what's my day look like?", "when am I free this week?") in addition to
powering the `/book-meeting` command.

**Trigger keywords:** calendar, schedule, free, busy, meeting, book, agenda,
"what's on my calendar", "when am I free"

### Contents

- gws CLI helpers (preferred for common operations):
  - `+agenda` — show upcoming events (`--today`, `--week`, `--days N`,
    `--timezone`, `--format table`)
  - `+insert` — create events ergonomically (`--summary`, `--start`, `--end`,
    `--attendee`, `--meet`)
- gws CLI resource methods (for operations helpers don't cover):
  - `freebusy query` — check availability for multiple users
  - `events list` — read events with filters (OOO, focus time, working location)
  - `events get` — read a specific event by ID
  - `events insert` — create events (use when `+insert` is insufficient)
  - `events update` / `events patch` — modify existing events (move, add
    attendees, change details)
  - `events delete` — cancel/remove events
  - `calendars get` — read calendar metadata including time zone
- Time zone handling:
  - Read attendee's time zone via `calendars get` on their calendarId
    (returns `timeZone` property directly — most reliable method)
  - Read Mat's time zone via `settings list` (returns authenticated user's
    zone — do not hardcode)
  - FreeBusy times are always UTC; event times include zone info
- Event type filters: `eventTypes=outOfOffice,focusTime,workingLocation`
- JSON output parsing patterns

**References file:** `references/gws-calendar-api.md` — detailed command
examples with full JSON request/response shapes. Loaded on demand to keep
SKILL.md lean.

### What the skill does NOT contain

- Scheduling rules or heuristics (those live in the command)
- Permissions grants (those live in the command)

## Component 2: Command — `/book-meeting`

**Location:** `claude-config/commands/book-meeting.md`

### Frontmatter

```yaml
id: book-meeting
aliases: [bm]
tags: [calendar, scheduling]
permissions:
  - "Bash(gws:*)"
  - "Bash(date:*)"
  - "Read"
  - "Grep"
  - "Glob"
```

Note: `Bash(gws:*)` grants all gws subcommands. Permission pattern needs
validation during implementation — if Claude Code's matching requires a
different format, adjust accordingly.

### Workflow

1. **Parse request** — extract: who (name or email), duration (default 25 min),
   urgency, topic (if provided)
2. **Resolve email** — if not an email address, ask the user for their email
3. **Resolve attendee name** — needed for event title. Ask Mat, or infer from
   email prefix (e.g. `harun.derya` → `Harun Derya`) and confirm.
4. **Get attendee time zone** — `gws calendar calendars get` on their calendarId
5. **Get Mat's time zone** — `gws calendar settings list` (do not hardcode)
6. **Get OOO/focus time** — query attendee's calendar with
   `eventTypes=outOfOffice,focusTime` for the search window
7. **Query freebusy** — both calendars, starting tomorrow (or today if urgent),
   up to 5 business days out
8. **Find slots** — within the overlap of both parties' booking windows
   (10am-5pm in each person's time zone)
9. **Apply kindness heuristics** — see rules below; flag concerns to Mat
10. **Confirm with Mat** — present the proposed slot: attendee, date, time,
    duration. Wait for approval before creating the event. This step is
    mandatory — calendar invites are socially visible and hard to undo.
11. **Book the event** — create on Mat's calendar with attendee as invitee
12. **Report** — confirm what was booked; note no video link (manual Zoom add
    needed for now)

### Scheduling Defaults

| Setting | Default | Override |
|---------|---------|---------|
| Duration | 25 min (5 min buffer to half hour) | "long meeting" → 50 min (10 min buffer to hour) |
| Booking window | 10am-5pm in each person's time zone | Per-person override if Mat provides one |
| Search window | Next 5 business days (Mon-Fri, no holiday awareness) | "urgent" → include today |
| Mat's morning preference | Prefer slots after 1pm in Mat's zone | Use mornings only if no afternoon slots exist |

### Event Format

- **Title:** `{Attendee Name} / Mat` (their name first)
- **Video:** None (Zoom not available via API; manual add from Calendar UI)
- **Description:** Propose one if context is available; leave blank if the
  meeting purpose is obvious
- **Duration boundary:** Events end at :25/:55 to give buffer before the next
  half hour/hour

### Kindness Heuristics

**Hard rules (never violate):**

- Never double-book anyone
- Never book outside 10am-5pm in the attendee's time zone
- Never book over OOO or focus time events

**Soft rules (flag to Mat if violated):**

- **Last open block:** If the attendee has only one 30+ min free block left in
  their day, flag rather than taking it
- **Lunch protection:** Avoid 12-1pm in the attendee's time zone. Use only if
  it's genuinely the only option, and ask first.
- **Stacking:** If the attendee already has 3+ consecutive meetings (no gap
  >15 min), avoid adding to that run
- **Mat's mornings:** Prefer afternoon slots for Mat. Use mornings only if no
  afternoon slots exist in the search window.

**Not enforced:**

- No guessing at commute times, personal preferences, or habits beyond calendar
  data
- No reading event titles to infer importance — just free/busy and event types

## Scope Boundaries

- **V1 is one-off meetings only.** Recurring events (weekly 1:1s, etc.) are out
  of scope. If requested, create the first occurrence and suggest Mat set up
  recurrence from the Calendar UI.
- **Single attendee per invocation.** Multi-attendee slot finding (intersecting
  N calendars) is a future upgrade.

## File Layout

```
claude-config/
  skills/
    gws-calendar/
      SKILL.md
      references/
        gws-calendar-api.md
  commands/
    book-meeting.md
```

## Future Upgrades

- **Zoom API integration:** Create Zoom meetings programmatically and attach
  join URLs to events. Requires Zoom OAuth app setup.
- **Directory lookup:** If IT enables `directory.readonly` scope, resolve names
  to emails via People API `searchDirectoryPeople`. Eliminates need to ask for
  emails.
- **Working hours API:** If Google ever ships cross-user working hours
  (issue #231620767), read actual configured hours instead of defaulting to
  10am-5pm.
- **Multi-attendee meetings:** Extend freebusy queries to N attendees and find
  common slots. The freebusy API already supports multiple calendar IDs — this
  is a workflow/heuristics extension only.
- **Recurring meetings:** Support creating recurring events via the API's
  recurrence rules.
- **Google Meet fallback:** The `+insert --meet` flag can attach a Google Meet
  link natively. Could offer as an alternative when Zoom isn't critical.
