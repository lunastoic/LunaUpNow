# AlarmKit Honesty Notes

What we actually know about AlarmKit, verified against the **installed SDK**
(`AlarmKit.framework`, iOS 26.5 SDK, module version 2303.5.3, Xcode 26.6) and
Apple's published material — versus what is unknown and must be measured on a
physical iPhone.

## Verified from the SDK interface (facts)

- **App-supplied alarm IDs.** `AlarmManager.schedule(id:configuration:)` takes
  a `UUID` we choose. This is the foundation of the escalation design: the
  primary alarm uses the `AlarmConfig` UUID; follow-up alerts use IDs derived
  deterministically from the session UUID (`LinkedAlarmID.escalationID`), so
  they are stable, linkable, deduplicatable, and cancellable.
- **Schedules.** `Alarm.Schedule` supports `.fixed(Date)` (one-shot) and
  `.relative(time:repeats:)` with `.never` or `.weekly([Locale.Weekday])`.
  Follow-up Wake Guard alerts use `.fixed` dates; the primary alarm uses
  `.relative` with weekly recurrence.
- **A follow-up AlarmKit alert CAN be scheduled from the wake flow.** There is
  no API restriction on scheduling while another alarm is alerting; scheduling
  is an async call available whenever the app process runs (including when
  opened via the alert's custom action). *Reliability when the app is opened
  from the alert still needs device confirmation.*
- **There is a system alarm limit.** `AlarmManager.AlarmError.maximumLimitReached`
  is a real error case. The limit's value is not published. Consequence: the
  escalation plan is hard-capped (4 secondary alerts per session), deduped by
  deterministic ID, and reconciled/cleaned on every app activation.
- **Alert presentation is system-owned.** `AlarmPresentation.Alert` gives us a
  title and ONE optional secondary button (`.countdown` or `.custom`
  behavior). `stopButton` is **deprecated as of iOS 26.1** — the system always
  renders its own Stop affordance. We cannot remove Stop. Therefore the app
  must treat "user pressed Stop without opening the app" as *session still
  unresolved*, which the controller handles by backfilling/restoring sessions
  on next activation.
- **Custom action opens the app.** `secondaryButtonBehavior = .custom` plus a
  `LiveActivityIntent` (`secondaryIntent`) runs in the app process; with
  `openAppWhenRun = true` it opens the app into the Wake Guard flow.
- **Sound.** `AlarmConfiguration` accepts an `AlertConfiguration.AlertSound`
  (default or a named bundled sound). No duration or looping parameters exist.
- **State observation.** `AlarmManager.alarms` and `alarmUpdates` (an
  `AsyncSequence`) let the app reconcile expected vs. actual system alarms;
  `Alarm.State` is `scheduled / countdown / paused / alerting`.
- **Authorization.** `NSAlarmKitUsageDescription` + `requestAuthorization()`;
  state can be `denied` — the UI surfaces this instead of failing silently.

## NOT promised by any API (do not claim)

- **There is NO documented duration for how long an unanswered alert keeps
  sounding.** Nothing in the SDK interface or the AlarmKit documentation
  specifies it. For reference, Apple's own Clock alarms ring for ~15 minutes,
  then pause and re-ring in cycles; developer-forum threads on AlarmKit sound
  repetition confirm the behavior is undocumented. Measure it on hardware
  (see DEVICE_TEST_CHECKLIST.md) and do not market anything stronger.
- **No API guarantees continuous sound for 3 hours.** The product promise is:
  *"One alarm begins a persistent multi-stage wake session that stays
  unresolved until completed or expired."* The 3-hour Heavy-Sleeper/Nuclear
  window is enforced by persisted session state + sparse follow-up alerts,
  never by one long sound.
- **Terminated-app behavior is only partially knowable.** AlarmKit alerts are
  delivered by the system, so the primary alarm should fire with the app
  killed — but the Wake Guard *session logic* only advances when our process
  runs. The design accounts for this: session start is the scheduled wake
  time, and on next launch the controller restores or backfills the session
  (including marking it Missed if the window fully elapsed). Confirm on device.
- **Simulator results are not evidence** for lock-screen alerts, Silent Mode,
  Focus breakthrough, alert duration, or terminated-app delivery.

## Design consequences implemented

| Requirement | Implementation |
|---|---|
| One user-created alarm | `AlarmConfig` → single `AlarmManager.schedule` with the alarm's UUID |
| Persistent multi-stage session | `WakeGuardSession` (Codable, persisted every mutation, restored on relaunch) |
| Escalation | `AlarmEscalationCoordinating` protocol; AlarmKit impl schedules ≤4 derived `.fixed` alerts + optional local-notification reminders (reminders never replace the alarm) |
| Duplicate prevention | Deterministic derived IDs + check of `manager.alarms` before scheduling |
| Cleanup | Cancel on resolution; `reconcile()` on every app activation removes orphans |
| Expiry | Engine marks `missed` (nothing completed) or `followUpFailed` (partial) at `maxExpiration`; cap is 3 h (`WakeGuardConfiguration.absoluteMaxWindow`) |

Sources: [Apple — Scheduling an alarm with AlarmKit](https://developer.apple.com/documentation/AlarmKit/scheduling-an-alarm-with-alarmkit),
[WWDC25 — Wake up to the AlarmKit API](https://developer.apple.com/videos/play/wwdc2025/230/),
[Apple Developer Forums — AlarmKit sound repetition](https://developer.apple.com/forums/thread/806697),
installed `arm64e-apple-ios.swiftinterface` of AlarmKit.framework (iOS 26.5 SDK).
