## What this changes

<!-- One or two sentences. -->

## Why

<!-- What went wrong, or what was missing. For a bug: what the actual failure
     was - the error text, or what silently did nothing. -->

## How it was verified

<!-- Not "it should work". What did you run, and what did it print?

     If you added or changed a check, say how you confirmed it fires: break the
     thing on purpose and show that it caught it. A guard nobody has seen fail
     is not known to work. -->

## Checklist

- [ ] `./scripts/doctor.ps1 -Repo` passes
- [ ] Every `.ps1` I touched parses under Windows PowerShell 5.1
- [ ] Shell files are still LF and BOM-less; `.cmd` files are still CRLF
- [ ] Comments explain **why**, not what
- [ ] If I ported code from another project, THIRD-PARTY-NOTICES.md says so
