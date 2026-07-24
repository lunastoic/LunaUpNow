# Physical-iPhone Test Checklist — Wake Guard

Simulator results do **not** count for anything on this list. Run on a real
iPhone (iOS 26.1+), signed with the app's team, AlarmKit permission granted.
Record actual observed behavior next to each item; Nuclear Mode is not
"production-ready" until every item has a real result written down.

## Primary alarm delivery

- [ ] Alarm fires at the scheduled time with the phone **locked** (screen off).
- [ ] Alarm breaks through **Silent Mode** (mute switch on).
- [ ] Alarm breaks through an active **Focus** (Do Not Disturb, Sleep Focus).
- [ ] Alarm fires with the app **force-quit** (swiped away in app switcher).
- [ ] Alarm fires after a device **restart** without opening the app first.

## Alert behavior with no user interaction

- [ ] Measure how long the alert actually keeps sounding when completely
      ignored (expect ~15 min ring/pause cycles like Clock, but **measure it** —
      it is undocumented). Record: continuous ring time, pause length, number
      of cycles, total time until the system gives up.
- [ ] What remains on the lock screen after the sound stops?
- [ ] Does the alert survive pressing a volume button / side button once?

## Alarm actions

- [ ] Secondary button ("I'm Up — Start Challenge") opens the app directly
      into the Wake Guard session screen from the lock screen (Face ID path).
- [ ] System **Stop** button dismisses the sound WITHOUT completing Wake
      Guard; on next app open the session is restored, still unresolved, with
      the elapsed time counted from the scheduled wake time.

## Follow-up (escalation) scheduling

- [ ] With a session unresolved, derived follow-up alerts (`+10 min` etc.)
      actually fire as full AlarmKit alerts.
- [ ] Follow-up alerts fire when the app was opened from the alarm and then
      **backgrounded** again.
- [ ] Follow-up alerts fire when the app is **terminated** between stages.
- [ ] No duplicate follow-up alerts appear after repeatedly opening/closing
      the app mid-session (reconciliation works; count alarms in the system).
- [ ] `maximumLimitReached` is not hit with 2 armed alarms + 4 escalations
      (note the observed system limit if you find it).

## Session lifecycle across termination

- [ ] Complete Stage 1, force-quit the app, wait past the Stage 2 delay,
      reopen: Stage 2 is unlocked, timings correct, questions identical.
- [ ] Sleep through everything for the full window (use a short custom window
      for sanity, then one real 3-hour Nuclear run): session is marked
      **Missed**, and every pending escalation alert is gone afterwards.
- [ ] Complete all stages: success screen appears ONLY after the final stage,
      and all pending escalation alerts + reminder notifications are cancelled
      (verify none fire afterwards).

## Three-hour Nuclear run (the big one)

- [ ] Real overnight test: Nuclear preset, phone locked, do not touch it.
      Verify: primary rings, escalation alerts at +10/+25/+60/+120 min ring,
      session shows Missed at +3 h, no stray alerts after +3 h.
- [ ] Real completion test: answer every stage; total experience matches the
      in-app timeline; History entry is `Completed`.

## Honest-marketing gate

- [ ] Everything above recorded with real numbers.
- [ ] Any claim in App Store copy or in-app text matches observed behavior —
      in particular, nothing implies continuous sound for the full window.
