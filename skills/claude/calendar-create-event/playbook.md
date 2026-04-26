# Calendar Create Event Playbook

Use this playbook for creating reminders, recurring events, and `.ics` fallback files.

## Decision order

1. Prefer direct event creation if the auth path actually supports Calendar writes.
2. If the direct Calendar API path fails due to missing delegation or blocked auth, switch to `.ics` fallback immediately.
3. If the user wants repeated reminders for one obligation, prefer one recurring event instead of many separate events.

## Google Workspace Calendar fallback

- The Google Workspace helper may support Gmail or Admin SDK tasks while Calendar remains undelegated.
- If `https://www.googleapis.com/auth/calendar` returns `401 unauthorized_client`, do not keep retrying.
- In that case, create an importable `.ics` file instead.

## Recurrence defaults

For repeated reminders about the same deadline:

- Monthly reminders should usually be one `VEVENT` with:
  - `RRULE:FREQ=MONTHLY;COUNT=<n>`
- Use separate events only if the user explicitly wants separate acceptances, different descriptions, different attendees, or irregular dates.

Example:

```ics
BEGIN:VEVENT
UID:example-1@local
DTSTAMP:20260422T000000Z
DTSTART;TZID=America/New_York:20300915T090000
DTEND;TZID=America/New_York:20300915T091500
SUMMARY:Example recurring reminder
RRULE:FREQ=MONTHLY;COUNT=10
BEGIN:VALARM
ACTION:DISPLAY
DESCRIPTION:Example recurring reminder
TRIGGER:-PT0M
END:VALARM
END:VEVENT
```

## `.ics` minimum structure

```ics
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Local Skill//Calendar Create Event//EN
CALSCALE:GREGORIAN
METHOD:PUBLISH
BEGIN:VEVENT
...
END:VEVENT
END:VCALENDAR
```

Recommended event fields:

- `UID`
- `DTSTAMP`
- `DTSTART`
- `DTEND`
- `SUMMARY`
- `DESCRIPTION`
- `RRULE` when recurring
- `ORGANIZER`
- `ATTENDEE` lines when the user wants guests
- `VALARM` when a reminder should appear on import

## Attendee caveat

Including attendees in an `.ics` file is useful, but importing the file does not always cause Google Calendar or other providers to send invitation emails automatically.

Tell the user this plainly when you use `.ics` fallback.

## Output checklist

Before finishing, confirm:

- title is correct
- timezone is correct
- first occurrence is correct
- recurrence count/rule is correct
- attendees are correct
- file path is easy to access
