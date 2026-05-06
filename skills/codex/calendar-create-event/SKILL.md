---
name: calendar-create-event
description: Create calendar events, reminders, recurring series, or .ics fallback files for Calendar workflows. Use when the user asks to create calendar events, reminders, invites, recurring reminders, or importable .ics files.
---

# Calendar Create Event

Use this skill when the user wants calendar events created, especially reminders, guest invites, recurring schedules, or a local `.ics` file they can import.

1. Extract the actual scheduling intent first:
   - calendar/account to use
   - title
   - date and time
   - timezone
   - duration
   - attendees
   - recurrence
   - reminders/alarms
   - whether the user wants direct creation or an `.ics` file

2. Prefer direct calendar creation if the available account/auth path supports it.
   - For Google Workspace service-account flows, verify the needed Calendar scope works before doing deeper work.
   - If the Calendar API scope is blocked or undelegated, stop retrying and switch to `.ics` fallback.

3. When a user wants many reminders for the same obligation, default to one recurring event rather than many separate events.
   - Example: monthly reminders for 10 months should usually be one recurring series with 10 occurrences.
   - Only create separate standalone events if the user explicitly asks for separate events.

4. If using `.ics` fallback:
   - Create a valid iCalendar file with explicit timezone data.
   - Use one `VEVENT` plus `RRULE` for recurring series whenever possible.
   - Include `UID`, `DTSTAMP`, `SUMMARY`, `DESCRIPTION`, `ORGANIZER`, attendee lines when requested, and `VALARM` if the user wants reminders.
   - Put the file somewhere easy to access, usually `~/Downloads`, unless the user asked for a different location.

5. Keep the workflow efficient.
   - Do not probe APIs repeatedly once you know the auth path is blocked.
   - Do not create 10 separate events when one recurring rule solves the problem.
   - Verify the final dates, recurrence count, and timezone before finishing.

6. Call out the import caveat when using `.ics`.
   - Importing an `.ics` usually adds the events locally.
   - Guest invitations may not be emailed automatically by the calendar provider after import.

7. Use the shared guidance in [playbook.md](playbook.md) for recurrence, `.ics` structure, and Google Workspace Calendar fallback behavior.

Output format:
- Say whether the result was direct calendar creation or `.ics` fallback.
- Report the event title, first occurrence, recurrence rule or count, attendees, and final file path if applicable.
