# Google Calendar Meeting Scheduler — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Claude the ability to query Google Calendar and book meetings via the `gws` CLI, with scheduling heuristics that respect people's time.

**Architecture:** A skill (`gws-calendar`) teaches gws CLI patterns; a command (`/book-meeting`) defines the scheduling workflow with pre-authorized Bash permissions. The skill handles knowledge, the command handles policy.

**Tech Stack:** gws CLI, Google Calendar API v3 (via gws), Claude Code skills/commands

**Spec:** `docs/superpowers/specs/2026-04-14-gcal-meeting-scheduler-design.md`

---

## Chunk 0: Global permissions

### Task 0: Add gws to global settings permissions

The skill needs to run gws commands in ad-hoc conversations (e.g. "what's on
my calendar?"), not just through the `/book-meeting` command. Add `Bash(gws:*)`
to global settings so gws calls don't prompt for permission.

**Files:**
- Modify: `claude-config/settings.json`

- [ ] **Step 1: Read current settings.json**

Read the file to find the existing `permissions.allow` array.

- [ ] **Step 2: Add gws permission**

Add `"Bash(gws:*)"` to the `permissions.allow` array. If the pattern doesn't
work (tested in Chunk 2, Task 3 Step 2), adjust to `"Bash(gws calendar:*)"`.

- [ ] **Step 3: Commit**

```bash
git add claude-config/settings.json
git commit -m "feat: add gws calendar permission to global settings"
```

---

## Chunk 1: Skill — `gws-calendar`

### Task 1: Create the references file

Reference doc with detailed gws calendar CLI examples and JSON response shapes.
The skill SKILL.md links to this; Claude loads it on demand.

**Files:**
- Create: `claude-config/skills/gws-calendar/references/gws-calendar-api.md`

- [ ] **Step 1: Create the references directory and file**

Write the following content to `claude-config/skills/gws-calendar/references/gws-calendar-api.md`:

```markdown
# gws Calendar API Reference

## Helpers

### +agenda — Show upcoming events

```bash
# Today's events
gws calendar +agenda --today

# Today's events in table format
gws calendar +agenda --today --format table

# This week
gws calendar +agenda --week

# Next 5 days
gws calendar +agenda --days 5

# Specific calendar
gws calendar +agenda --today --calendar 'user@agilebits.com'

# Override timezone
gws calendar +agenda --today --timezone America/Los_Angeles
```

### +insert — Create an event

```bash
# Basic event
gws calendar +insert \
  --summary 'Harun / Mat' \
  --start '2026-04-16T14:00:00-04:00' \
  --end '2026-04-16T14:25:00-04:00'

# With attendee
gws calendar +insert \
  --summary 'Harun / Mat' \
  --start '2026-04-16T14:00:00-04:00' \
  --end '2026-04-16T14:25:00-04:00' \
  --attendee 'harun.derya@agilebits.com'

# With description
gws calendar +insert \
  --summary 'Harun / Mat' \
  --start '2026-04-16T14:00:00-04:00' \
  --end '2026-04-16T14:25:00-04:00' \
  --attendee 'harun.derya@agilebits.com' \
  --description 'Discuss Q2 roadmap alignment'

# With Google Meet (fallback when Zoom unavailable)
gws calendar +insert \
  --summary 'Harun / Mat' \
  --start '2026-04-16T14:00:00-04:00' \
  --end '2026-04-16T14:25:00-04:00' \
  --attendee 'harun.derya@agilebits.com' \
  --meet
```

**+insert response** (JSON):
```json
{
  "id": "abc123eventid",
  "summary": "Harun / Mat",
  "start": {"dateTime": "2026-04-16T14:00:00-04:00", "timeZone": "America/New_York"},
  "end": {"dateTime": "2026-04-16T14:25:00-04:00", "timeZone": "America/New_York"},
  "attendees": [{"email": "harun.derya@agilebits.com", "responseStatus": "needsAction"}],
  "htmlLink": "https://www.google.com/calendar/event?eid=..."
}
```

## Resource Methods

### freebusy query — Check availability

```bash
gws calendar freebusy query --json '{
  "timeMin": "2026-04-16T00:00:00Z",
  "timeMax": "2026-04-16T23:59:59Z",
  "items": [
    {"id": "mat.pataki@agilebits.com"},
    {"id": "harun.derya@agilebits.com"}
  ]
}'
```

**Response:**
```json
{
  "calendars": {
    "mat.pataki@agilebits.com": {
      "busy": [
        {"start": "2026-04-16T13:00:00Z", "end": "2026-04-16T14:00:00Z"}
      ]
    },
    "harun.derya@agilebits.com": {
      "busy": [
        {"start": "2026-04-16T15:00:00Z", "end": "2026-04-16T16:00:00Z"}
      ]
    }
  },
  "timeMin": "2026-04-16T00:00:00Z",
  "timeMax": "2026-04-16T23:59:59Z"
}
```

**Important:** FreeBusy times are always UTC. Convert to local time zones for
display and slot calculation.

### calendars get — Read calendar metadata (including time zone)

```bash
gws calendar calendars get --params '{"calendarId": "harun.derya@agilebits.com"}'
```

**Response (key fields):**
```json
{
  "id": "harun.derya@agilebits.com",
  "summary": "harun.derya@agilebits.com",
  "timeZone": "America/Toronto"
}
```

### settings list — Read authenticated user's settings

```bash
gws calendar settings list
```

Returns array of settings. Key entries:
- `{"id": "timezone", "value": "America/New_York"}` — Mat's time zone

### events list — Read events with filters

```bash
# Standard event listing
gws calendar events list --params '{
  "calendarId": "harun.derya@agilebits.com",
  "timeMin": "2026-04-16T00:00:00Z",
  "timeMax": "2026-04-16T23:59:59Z",
  "singleEvents": true,
  "orderBy": "startTime"
}'

# OOO and focus time only
gws calendar events list --params '{
  "calendarId": "harun.derya@agilebits.com",
  "timeMin": "2026-04-16T00:00:00Z",
  "timeMax": "2026-04-21T23:59:59Z",
  "eventTypes": ["outOfOffice", "focusTime"],
  "singleEvents": true
}'
```

### events get — Read a specific event

```bash
gws calendar events get --params '{"calendarId": "primary", "eventId": "abc123eventid"}'
```

### events insert — Create an event (raw method)

Use when `+insert` helper is insufficient (e.g. need conferenceData or
extended properties).

```bash
gws calendar events insert --params '{"calendarId": "primary"}' --json '{
  "summary": "Harun Derya / Mat",
  "start": {"dateTime": "2026-04-16T14:00:00-04:00"},
  "end": {"dateTime": "2026-04-16T14:25:00-04:00"},
  "attendees": [{"email": "harun.derya@agilebits.com"}],
  "description": "Optional description"
}'
```

### events update — Modify an existing event

```bash
# Move a meeting to a new time
gws calendar events update --params '{"calendarId": "primary", "eventId": "abc123eventid"}' \
  --json '{
    "start": {"dateTime": "2026-04-17T15:00:00-04:00"},
    "end": {"dateTime": "2026-04-17T15:25:00-04:00"}
  }'
```

### events patch — Partial update (e.g. add attendee)

```bash
gws calendar events patch --params '{"calendarId": "primary", "eventId": "abc123eventid"}' \
  --json '{
    "attendees": [
      {"email": "harun.derya@agilebits.com"},
      {"email": "new.person@agilebits.com"}
    ]
  }'
```

Note: `patch` merges fields; `update` replaces the entire resource. Prefer
`patch` for adding attendees or changing a single field.

### events delete — Remove an event

```bash
gws calendar events delete --params '{"calendarId": "primary", "eventId": "abc123eventid"}'
```

Returns empty response on success.
```

- [ ] **Step 2: Review the file, verify formatting is correct**

Read the file back and confirm all code blocks are properly closed and the
markdown renders correctly.

- [ ] **Step 3: Commit**

```bash
git add claude-config/skills/gws-calendar/references/gws-calendar-api.md
git commit -m "feat: add gws-calendar API reference doc"
```

---

### Task 2: Create the skill SKILL.md

Main skill file. Lean — links to the references doc for detailed examples.

**Files:**
- Create: `claude-config/skills/gws-calendar/SKILL.md`

- [ ] **Step 1: Create SKILL.md**

```markdown
---
name: gws-calendar
description: Use the gws CLI for Google Calendar operations. Use when user mentions calendar, schedule, free, busy, meeting, book, agenda, "what's on my calendar", "when am I free", or any calendar-related query. Also invoked by the /book-meeting command.
---

# gws Calendar

Use the `gws` CLI to interact with Google Calendar. Auth is pre-configured
(`gws auth login --scopes calendar`).

## Quick Operations

| Task | Command |
|------|---------|
| Today's agenda | `gws calendar +agenda --today` |
| This week | `gws calendar +agenda --week --format table` |
| Next N days | `gws calendar +agenda --days N` |
| Create event | `gws calendar +insert --summary '...' --start '...' --end '...' --attendee '...'` |

## Checking Availability

Use `freebusy query` to check multiple people at once. Times in the request and
response are **always UTC**.

## Time Zone Handling

- **Attendee's zone:** `gws calendar calendars get --params '{"calendarId": "user@agilebits.com"}'` → `timeZone` field
- **Mat's zone:** `gws calendar settings list` → entry with `"id": "timezone"`
- **Do not hardcode time zones.** Always read them at runtime.
- FreeBusy returns UTC. Events include zone info in `start.timeZone` / `end.timeZone`.
- Use RFC 3339 format for all timestamps: `2026-04-16T14:00:00-04:00`

## Event Type Filters

Query OOO, focus time, and working location events:
```bash
gws calendar events list --params '{
  "calendarId": "user@agilebits.com",
  "eventTypes": ["outOfOffice", "focusTime", "workingLocation"],
  "singleEvents": true,
  "timeMin": "...",
  "timeMax": "..."
}'
```

## Modifying Events

- **Move:** `events update` with new start/end
- **Add attendee:** `events patch` with full attendees list
- **Cancel:** `events delete` with calendarId + eventId

## Limitations

- **No Zoom links via API.** Zoom add-on only works in the browser UI. Events
  are created without video links. Attendees add Zoom from Calendar web UI.
- **No directory lookup.** `directory.readonly` scope blocked by org. Must ask
  for attendee emails directly.
- **No cross-user working hours.** Google doesn't expose this. Default to
  10am-5pm in the attendee's calendar time zone.

## Reference

Detailed command examples and JSON response shapes:
[gws-calendar-api.md](references/gws-calendar-api.md)
```

- [ ] **Step 2: Commit**

```bash
git add claude-config/skills/gws-calendar/SKILL.md
git commit -m "feat: add gws-calendar skill"
```

---

## Chunk 2: Command — `/book-meeting`

### Task 3: Create the command

The scheduling workflow with permissions, rules, and heuristics.

**Files:**
- Create: `claude-config/commands/book-meeting.md`

- [ ] **Step 1: Create the command file**

```markdown
---
id: book-meeting
aliases: [bm]
tags:
  - calendar
  - scheduling
permissions:
  - "Bash(gws:*)"
  - "Bash(date:*)"
  - "Read"
  - "Grep"
  - "Glob"
---

# /book-meeting

Book a meeting between Mat and a colleague. Finds a mutually free slot that
respects both parties' time, then creates a calendar event.

## Usage

```
/book-meeting [attendee-email] [options]
```

User may also say things like:
- "book a meeting with harun.derya@agilebits.com"
- "schedule 50 min with andrew.bredow@agilebits.com to discuss roadmap"
- "find time with cindy.lau@agilebits.com this week, it's urgent"

## Workflow

### 1. Parse the request

Extract from the user's message:
- **Attendee email** — required. If not provided, ask.
- **Attendee name** — for the event title. Infer from email prefix
  (e.g. `harun.derya` → `Harun Derya`). Confirm with Mat if unsure.
- **Duration** — default: 25 min. If user says "long meeting" or "1 hour": 50 min.
- **Urgency** — if user says "urgent" or "today": search includes today.
- **Topic** — if mentioned, use for event description.

### 2. Gather calendar data

Run these as parallel Bash tool calls in a single message:

```bash
# Attendee's time zone
gws calendar calendars get --params '{"calendarId": "ATTENDEE_EMAIL"}'

# Mat's time zone
gws calendar settings list

# Attendee's OOO and focus time (search window)
# Note: workingLocation is omitted — it indicates where someone is working,
# not whether they're busy. It doesn't block scheduling.
gws calendar events list --params '{
  "calendarId": "ATTENDEE_EMAIL",
  "eventTypes": ["outOfOffice", "focusTime"],
  "singleEvents": true,
  "timeMin": "SEARCH_START",
  "timeMax": "SEARCH_END"
}'

# FreeBusy for both (search window)
gws calendar freebusy query --json '{
  "timeMin": "SEARCH_START",
  "timeMax": "SEARCH_END",
  "items": [
    {"id": "mat.pataki@agilebits.com"},
    {"id": "ATTENDEE_EMAIL"}
  ]
}'
```

### 3. Find slots

- **Booking window:** 10:00-17:00 in each person's time zone.
- **Search window:** Next 5 business days (Mon-Fri). Urgent: include today.
- Compute the intersection of both booking windows in UTC.
- Subtract all busy blocks from both calendars.
- Subtract OOO and focus time blocks.
- Remaining gaps ≥ meeting duration are candidate slots.

### 4. Rank and filter slots

**Preferences (in order):**
1. Afternoon slots for Mat (after 13:00 in Mat's zone)
2. Earlier dates first
3. Earlier times second (within afternoon preference)

**Kindness checks — apply to every candidate:**

**Hard rules (skip the slot):**
- Overlaps any busy block → skip
- Outside 10:00-17:00 in either person's zone → skip
- Overlaps OOO or focus time → skip

**Soft rules (flag to Mat instead of auto-booking):**
- **Last open block:** Attendee has only one free block ≥30 min left that day
  → flag: "This is [name]'s only open slot today. Still book it?"
- **Lunch slot:** 12:00-13:00 in attendee's zone
  → flag: "This is [name]'s lunch hour. OK to book?"
- **Stacking:** Attendee already has 3+ back-to-back meetings (no gap >15 min)
  → flag: "[name] already has N meetings in a row. Add another?"
- **Mat's morning:** Slot is before 13:00 in Mat's zone and afternoon slots
  exist → skip (prefer afternoon). If no afternoon slots exist across the
  entire search window, allow morning slots.

### 5. Confirm with Mat

Present the proposed slot:

> **Proposed:** Harun Derya / Mat
> **When:** Wednesday Apr 16, 2:00 – 2:25 PM ET
> **Duration:** 25 min
> **Note:** No video link — add Zoom from Calendar web UI
>
> Book it?

Wait for approval. If Mat says no, offer the next best slot.

### 6. Book the event

```bash
gws calendar +insert \
  --summary 'Harun Derya / Mat' \
  --start '2026-04-16T14:00:00-04:00' \
  --end '2026-04-16T14:25:00-04:00' \
  --attendee 'harun.derya@agilebits.com' \
  --description 'Topic if provided'
```

### 7. Report

> Booked: **Harun Derya / Mat**
> Wednesday Apr 16, 2:00 – 2:25 PM ET
> Invite sent to harun.derya@agilebits.com
> No video link — add Zoom from the Calendar web UI.

## Scheduling Defaults

| Setting | Default | Override |
|---------|---------|---------|
| Duration | 25 min (ends at :25 or :55) | "long" / "1 hour" → 50 min |
| Booking window | 10:00-17:00 each person's zone | Mat can override per-person |
| Search window | Next 5 business days (Mon-Fri) | "urgent" → include today |
| Morning preference | Prefer after 13:00 Mat's zone | Mornings only if no PM slots |
| Business days | Mon-Fri, no holiday awareness | — |

## Scope

- **V1: One-off meetings, single attendee.**
- Recurring events: create the first occurrence, suggest Mat sets up recurrence
  from Calendar UI.
- Multi-attendee: not yet supported. Book separately or ask Mat to handle in UI.
```

- [ ] **Step 2: Validate permission syntax**

Test that `Bash(gws:*)` actually grants gws commands without prompting.
Create a quick test: invoke `/book-meeting` and try running
`gws calendar +agenda --today`. If it prompts for permission, try alternative
patterns: `Bash(gws calendar:*)`, `Bash(gws *)`.

Adjust the command frontmatter based on what works.

- [ ] **Step 3: Commit**

```bash
git add claude-config/commands/book-meeting.md
git commit -m "feat: add /book-meeting command"
```

---

## Chunk 3: Validation

### Task 4: End-to-end test

Test the full flow without actually sending an invite.

- [ ] **Step 1: Test the skill — ad-hoc calendar query**

Invoke the skill by asking "what's on my calendar today?" in a new session.
Verify it uses `gws calendar +agenda --today` and returns results.

- [ ] **Step 2: Test the command — dry run booking**

Invoke `/book-meeting` with a known colleague email. Walk through the full
workflow up to the confirmation step. Verify:
- Email is accepted
- Time zone is read correctly
- FreeBusy data is fetched
- Slot is proposed with correct formatting
- Confirmation prompt appears

Do NOT confirm the booking — decline and verify the flow handles rejection
gracefully (offers next slot or exits).

- [ ] **Step 3: Test the command — actual booking + cleanup**

Run `/book-meeting` with Mat's own email (mat.pataki@agilebits.com) as the
attendee. Confirm the booking. Verify:
- Event appears on the calendar
- Title format is correct
- Duration is 25 min (ends at :25 or :55)
- Event can be deleted afterward via `gws calendar events delete`

Clean up the test event.

- [ ] **Step 4: Test permission grant**

Verify that gws commands run without prompting for permission when invoked
through the `/book-meeting` command. If any command prompts, adjust the
permission pattern in the command frontmatter.

- [ ] **Step 5: Commit any fixes**

```bash
git add -p  # stage only relevant changes
git commit -m "fix: adjust book-meeting command after validation"
```
