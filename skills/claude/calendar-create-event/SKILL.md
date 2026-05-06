---
name: calendar-create-event
description: Create calendar events, reminders, recurring series, or .ics fallback files for Calendar workflows. Use when the user asks to create calendar events, reminders, invites, recurring reminders, or importable .ics files.
argument-hint: "[what event or reminder series to create, including date/time, attendees, recurrence, and whether direct creation or .ics fallback is acceptable]"
allowed-tools: Bash Read Write Edit Glob Grep
user-invocable: true
---

# Calendar Create Event

Use this skill when the user wants calendar events created, especially reminders, guest invites, recurring schedules, or a local `.ics` file they can import.

1. Parse the request into concrete calendar inputs:
   - target calendar/account
   - event title
   - start date/time
   - timezone
   - duration
   - attendees
   - recurrence
   - alarms/reminders
   - direct-creation vs `.ics` fallback preference

2. Prefer direct calendar creation if the available integration/auth path supports it.
   - If using a Google Workspace service-account flow, test the Calendar scope once.
   - If the Calendar scope is blocked or undelegated, do not keep retrying. Switch to `.ics` fallback.

3. Prefer one recurring event over many separate events when the reminders describe the same obligation.
   - Monthly reminders for the same deadline should usually be one event with an `RRULE`, not 10 standalone `VEVENT`s.
   - Only create separate events if the user explicitly asks for them.

4. For `.ics` fallback:
   - Use Write or Edit to create a valid iCalendar file.
   - Use one `VEVENT` plus `RRULE` for recurring series whenever possible.
   - Include `UID`, `DTSTAMP`, `SUMMARY`, `DESCRIPTION`, `ORGANIZER`, attendee lines if requested, and `VALARM` when reminders are wanted.
   - Put the file somewhere convenient, usually `~/Downloads`, unless the user asked for a different location.

5. Keep the process efficient.
   - Do not repeatedly inspect the same auth failure.
   - Do not create many standalone events when a recurring series is cleaner.
   - Verify recurrence count, first occurrence, timezone, and attendee list before finishing.

6. When using `.ics`, explicitly tell the user that importing usually adds the event(s) locally, but guest invitations may not be emailed automatically after import.

7. Consult [playbook.md](playbook.md) for recurrence rules, `.ics` patterns, and Google Workspace Calendar fallback guidance.

8. Report the result clearly:
   - whether the event was created directly or via `.ics`
   - title
   - first occurrence
   - recurrence rule or count
   - attendees
   - file path if an `.ics` file was written

## Task

$ARGUMENTS
