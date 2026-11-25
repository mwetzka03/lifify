# Changes in 0.6.0

[English](#english) · [Deutsch](#deutsch)

## English

### Overview

Version 0.6.0 first improves the code base (part A) and then adds new features
(part B). Part B is complete. From part A, the rebuild of two screens and part
of the method splitting are still open (see the last section).

### 0.6.0: Testable calendar access (A1)

- **What:** All access to the system calendar and Reminders now goes through
  the `CalendarGateway` protocol. The app uses `EventKitCalendarGateway`. Tests
  use a stand-in that records every call.
- **Why:** The paths that rewrite or delete real calendar events had no tests.
- **Effect:** No visible change. New tests cover the event rewrite after
  checking off, `WorkoutCalendarSync.apply` and `cleanup`, abstinence bonuses
  through `settle` and a relapse, the calendar import, and restoring full and
  Health backups.
- **Side effects:** Tests can no longer reach a real calendar. When several
  events move at once, their calendar rewrites now run one after another
  instead of in parallel. The duplicated recurrence translation is now shared.

### 0.6.0: Leaner screens (A2, in progress)

- **What:** The depot and the challenge board calculate through screen models
  (`PortfolioScreenModel`, `ChallengeBoardModel`). A booking row resolves its
  category and sale result once per render.
- **Why:** The depot repeated its calculations for every row. Every challenge
  card searched the completions of all challenges.
- **Effect:** Same values and same look, with faster first opens. Release build
  in the iPhone 17 simulator with 5,000 bookings, 30 holdings, 1,200 lots, 365
  prices per holding, 100 challenges, and 3,000 completions:

  | Screen | Before (median) | After (median) |
  | --- | ---: | ---: |
  | Depot | 1.9 s | 0.5 s |
  | Challenges, run 1 | 1.8 s | 0.6 s |
  | Challenges, run 2 | 3.6 s | 0.35 s |

- **Limits:** Simulator runs vary widely, so only clear differences count. The
  finance overview, transactions, and data management showed no measurable
  change. An extra forecast cache for the overview brought no gain and was
  removed again.
- **Measuring:** `ScreenPerformanceTests` is skipped in normal test runs and
  starts with `TEST_RUNNER_LIFIFY_MEASURE=1`.

### 0.6.0: Old group column removed (A3)

- **What:** Database schema V4 removes `ChallengeItem.groupID`. Before the
  column is dropped, the migration copies a group that exists only there into
  `groupIDsRaw`.
- **Why:** Group membership was stored twice.
- **Deviation from the plan:** `groupIDsRaw` stays, because it is the current
  source of all group memberships. Removing it would lose them. No other
  column turned out to be unused and safe to remove.
- **Effect:** No visible change. A database written by the real 0.5.5 code is
  now a test fixture with invented data. It opens with all data and groups.
- **Tests changed:** The single-group test now checks `groupIDs`. The old
  normalization test was replaced by the migration tests, because a record
  with only the old column can no longer exist after the migration.

### 0.6.0: Readable documents (A5)

- **What:** Long passages in `FINANCE.md` are now lists. The setup screen says
  Health (workouts and meals) instead of Training for a partial restore.
- **Why:** The rules were hard to scan, and the area has been called Health
  since 0.5.5.
- **Effect:** The wording of every finance rule is unchanged. A script compared
  all words before and after the reformatting.

### 0.6.0: Developer mode no longer changes real coins (A6)

- **What:** While developer mode shows another day, Lifify records coin
  bookings, check-offs, purchases, freezes, abstinence bonuses, and the
  birthday bonus. Back on the real day, at launch, or when the mode is turned
  off, exactly these changes are undone.
- **Why:** Simulated days used to pay coins permanently.
- **Effect:** Developer mode can be used for testing without changing the real
  wallet. Bonuses can be earned again on their real day.
- **Today:** Meal rewards now follow the simulated day.
- **Deliberately on the real clock:** The cleanup of past training events
  stays on the real date, so a simulated day can never delete real events from
  the iOS calendar.
- **Limits:** Meals entered on a simulated day stay, only their coins and
  fast-food charges are undone. A real booking removed during a simulation is
  not restored. A backup made during a simulation contains the simulated
  bookings as normal data.

### 0.6.0: Face ID for Finance (A7)

- **What:** The Finance tab unlocks with Face ID or the device passcode and
  locks again when the app goes to the background. The switch is under
  Settings, Finance, and is on by default. A second switch decides whether
  finance widgets may show amounts (off by default).
- **Why:** Financial data should stay private when someone else holds the
  unlocked phone.
- **Effect:** While locked, the finance screens are not built at all.
- **Added safeguards:** Turning the lock off or showing amounts in widgets asks
  for Face ID. A backup never carries these switches.
- **Limits:** Only the Finance tab is locked, as agreed. Home and the finance
  settings still show their content. A device without a passcode cannot be
  locked, so Finance stays open there.

### 0.6.0: Reference test for money paths (A8)

- **What:** `MoneyReferenceTests` runs bank import, Trade Republic statement and
  live session, bank notices, home budget, and forecasts on fixed data at a
  fixed date. It compares the full result with a stored reference.
- **Why:** The long finance methods are split next, and their results must stay
  the same.
- **Effect:** No visible change. `FinanceClock` makes the time fixable in tests.
  Tests no longer load live prices.
- **Limits:** The reference covers the main paths. Rarely used repair paths for
  older Trade Republic imports are only partly covered, so they stay unsplit
  until they have their own tests.

### 0.6.0: Progressive overload (B11)

- **What:** Each exercise in a running workout shows a suggested weight. It
  rises by an adjustable step (default 2.5 kg) when the last session reached
  every target rep, and stays the same otherwise. The plan shows the volume of
  each exercise per session.
- **Why:** The next weight should not have to be worked out by hand.
- **Effect:** The suggestion is applied only with a tap. The existing hint after
  three successful workouts stays and takes priority.

### 0.6.0: Meal favorites (B12)

- **What:** A heart marks a meal as a favorite. Favorites and recently eaten
  meals appear above the day's meals and are entered again with one tap.
- **Why:** Regular meals should not have to be typed or photographed each time.
- **Effect:** A new entry copies name, nutrients, and kind, but no photo. A
  repeated fast-food meal is charged again like any new one. Favorites are part
  of full and Health backups.

### 0.6.0: Monthly review and subscription detection (B4, B5)

- **What:** Finance, More now has a monthly review and subscription suggestions.
  The review compares the last finished period with up to six earlier ones per
  category, largest deviation first. It follows the chosen period mode. An
  optional notification opens it when a period ends.
- **Subscriptions:** Repeated payments to the same payee, within 10 % of the
  usual amount, at a weekly, biweekly, monthly, or yearly rhythm, with at least
  three payments, are suggested as fixed costs. Dismissed suggestions stay
  dismissed and are part of the backup.
- **Why:** Unusual spending and forgotten subscriptions should be easy to spot.
- **Effect:** Adding a suggestion creates the fixed cost and links its past
  payments. A subscription whose payments have stopped is not suggested.
- **Tests changed:** The navigation test now expects the two new links.

### 0.6.0: Budget warnings (B3)

- **What:** A local notification appears when a variable cost or budget pool
  reaches 80 % and 100 %, and when today's budget is exceeded. Thresholds and
  switches are under Settings, Finance.
- **Why:** An overspent budget should be noticed while it can still be changed.
- **Effect:** The check runs after every saved booking, including Shortcuts and
  imports. Each threshold notifies once per period. Only the running period
  counts, and several warnings arrive as one notification.

### 0.6.0: Dividend overview and forecast (B6)

- **What:** Finance, More now lists received dividends per position, month, and
  year, plus a forecast of the next twelve months.
- **Why:** Dividend income was only visible as single bookings.
- **Effect:** The forecast repeats each payment of the last twelve months one
  year later, using its dividend per share and the shares held then, including
  future savings plan shares. Accumulating ETFs pay nothing and do not appear.
- **Tests changed:** The navigation test expects the new link.

### 0.6.0: Optional return scenario (B7)

- **What:** A switch under Settings, Finance, Depot lets ETFs grow in future
  forecast periods at their own historic return: 10 years, else 5 years, else
  3 %. The screen lists each position's rate and basis, and the ETF detection
  can be corrected by hand.
- **Why:** A forecast with flat prices understates a long-term ETF depot.
- **Effect:** Off by default, and then every forecast stays exactly as before.
  Past periods and the running period never change. Values with the scenario
  are marked. Stocks, crypto, and other positions keep today's price.
- **Limits:** Past returns are no guarantee. Returns come from Yahoo Finance in
  the listing's currency.

### 0.6.0: Depot shares, design and deep analysis (B8)

- **What:** The shares screen now uses the app's styles and has a switch between
  Normal and Deep analysis. Deep analysis breaks ETFs into their companies and
  shows each company's share of the whole depot.
- **Data:** Xtrackers and VanEck files are downloaded at most once a week. Index
  ETFs from iShares and Amundi use the Xtrackers fund on the same index. For
  anything else, a CSV or Excel file can be imported by hand and takes priority.
- **Deviation from the plan:** The iShares website no longer offers a direct
  holdings download, so Xtrackers replaces iShares as the index stand-in.
- **Open:** iShares MSCI World Small Cap and iShares Space Technologies have no
  automatic source and need a manual import.
- **Effect:** Entries below 0.1 % are combined into Other. Leveraged ETFs count
  with their leverage, which is explained under the list.

### 0.6.0: Siri and Shortcuts (B2)

- **What:** New actions check off a challenge, log a meal, and read the remaining
  budget. They work by voice and in the Shortcuts app.
- **Why:** Small daily entries should not need the app to be opened.
- **Effect:** Sport with a linked training and abstinence cannot be checked off
  this way. A check-off never removes an existing one. A meal with a favorite's
  name takes its nutrients. The budget answer needs an unlocked device.

### 0.6.0: Apple Health (B10)

- **What:** An optional switch under Settings, Health connects Apple Health. It
  reads weight, steps, active energy, and resting pulse, and saves finished
  workouts. The Health tab shows today's values and a short history as numbers.
- **Why:** Body data and training should not have to be kept twice.
- **Effect:** Without permission, everything works as before. A newer weight
  updates the body data and so the calorie target. Each workout is saved once.
- **Setup:** The app now needs the HealthKit capability. See the setup steps for
  the Apple Developer account.
- **Not built:** Sleep stays out until the owner decides.

### B1 and B9: Widgets and workout Live Activity

- **Widgets:** Daily budget, Today (interactive), Coins & Streak, Portfolio, Next workout, Overview, and three Lock Screen widgets. Why: the plan for 0.6.0. Effect: key values are visible without opening the app.
- **Data path changed from the plan:** the database stays where it is. The app writes a small snapshot file into the App Group. Why: moving the store risks real data, and a widget writing to it could bypass the booking rules. Effect: no migration; widgets show the state of the last app update.
- **Check-off in a widget:** the tap is queued and disappears from the widget at once. The app books it with all rules the next time it runs. Effect: coins and streak change only after the app was opened.
- **Finance lock:** with the lock on, amounts are not even written to the snapshot unless "show finance values in widgets" is on.
- **Sport with a linked training** cannot be checked off in a widget. A tap opens the training and never replaces a running session.
- **Live Activity:** plan, exercise, set, session time, and rest timer on the Lock Screen and in the Dynamic Island, for running workouts only.
- **Setup:** the App Group `group.com.mwetzka03.lifify` and the target `com.mwetzka03.lifify.widgets` must exist in the Apple Developer account for a device build.

### A8: Data screen, naming, and what is still open

- **Data screen:** it no longer keeps 20 live queries. It reads the data only when a backup is made. Why: the queries served only the export. Effect: same backup, lighter screen.
- **Meal recognition:** `thinking` is now `disablesThinking`, which is what the flag does. The request is unchanged.
- **Still open from A8 and A2:** `DashboardView` and `TransactionsView` are not rebuilt, and about 160 methods stay over 30 lines, mostly in Trade Republic, backup, and views. Why: they touch money and backup paths and should change only after the first test on a real iPhone.

### Fix: Finance summary after editing a plan row

- **What:** The finance summary now recalculates when the amount, account, schedule, or state of a fixed cost, income forecast, budget, shopping item, split, or account changes. Before, it noticed only a new or removed row.
- **Why:** After editing, for example, the amount of a fixed cost, the summary kept the old value until another change happened.
- **Effect:** The summary is current right after saving. The booking list reacts the same way to changed accounts. A rename alone does not trigger a recalculation.

### Fix: Database stays in the app's folder

- **What:** The database path is now fixed to the app's own folder (`Application Support/default.store`).
- **Why:** Found on the iPhone. With the new App Group, SwiftData copied the database into the group container on its own and used that copy. The archive and recovery steps still looked in the app folder.
- **Effect:** The app uses its original database again. A copy from the first 0.6.0 launch stays unused in the App Group; nothing was deleted. A test pins the path.

### Owner feedback: Steps under Training

- **What:** A Steps area under Training, between the plans and the history: today, average of 7 and 30 days, best day, and a bar chart of 7 or 30 days with the average as a line. It replaces the Apple Health card above the tabs.
- **Why:** The owner found the card unhelpful and wants the steps where training is.
- **Effect:** Averages leave out today and days without data. Lifify now reads only weight and steps; active energy and resting pulse are no longer read. Writing finished workouts to Apple Health is unchanged and is now named in the switch's text.

### Owner feedback: Subscriptions, dividends, and the deep analysis

- **Subscriptions:** The suggestions moved from More to the top of the fixed costs, folded by default. Why: they belong where fixed costs are made.
- **Dividends:** They moved from More into Income, folded under the income forecasts. The list shows only positions that still pay; sold funds appear only in the received total. The forecast is only shown and does not count in any forecast or balance.
- **Deep analysis chart:** The chart combines everything below 0.5 % into Other; the list keeps 0.1 %. Why: the pie was unreadable with many thin slices.
- **Missing fund splits:** Trade Republic names funds without the provider, for example "Rare Earth & Strategic Metals USD (Acc)". Funds are now found by ISIN first. Effect: AI & Big Data, Rare Earth, Space Innovators, and World ex USA are split again. iShares World Small Cap and Space Technologies still need a manual import.

### Owner feedback: Calorie note and daily briefing

- **Calorie note:** At 20:00 the calorie challenge reports the day against the goal instead of "still waiting for a check": under the deficit target it praises and says the kcal left, when building muscle it says the kcal still missing. It is rescheduled after each change of the meals.
- **Daily briefing:** The salary line is gone. Why: the owner finds it useless every day.

### Owner feedback: Depot gains in future periods

- **What:** In a future period, a position's gain is the forecast value minus today's purchase cost plus every savings plan amount until the period end. "Today" shows the growth from today's value plus the new money. Depot screen and the depot tile both use it.
- **Why:** With the return scenario on, the value grew while the gain stayed at today's figure.
- **Effect:** With the scenario, the gains grow with the forecast. Without it they stay at today's gain, as before. Today and past periods are unchanged.

### Owner feedback: Step pages and the home activity card

- **Step pages:** A swipe on the step chart, or its arrows, shows the 7 or 30 days before; the line shows that page's average. Lifify now reads one year of steps for this.
- **Home:** Under the calendar, a card shows the steps and the planned trainings of the chosen day, week, or month. Week and month show the sum and the daily average. Trainings come from calendar events with linked plans, directly or through their challenge, and show a check once a session of that plan finished that day.
- **Why:** The owner wants to look back and see activity next to the calendar. Effect: a moved or deleted event changes the card at once.

### Owner feedback: Steps in the Overview widget

- **What:** The large Overview widget shows today's steps under the next training, with the time they were read.
- **Why:** Requested by the owner. A widget cannot read Apple Health itself, so the app reads today's steps whenever it comes to the front and writes them into the widget data.
- **Effect:** The number is as fresh as the last app start; the time says so. With Apple Health off, or on a new day before the app ran, the line stays away.

### Owner feedback: iShares holdings load by themselves

- **What:** iShares is a third provider. Its holdings come as CSV from BlackRock's product data service, the same file the fund page offers. iShares MSCI World Small Cap and iShares Space Technologies are mapped by ISIN.
- **Why:** Both needed a manual import before.
- **Effect:** All of the owner's funds are split automatically. Only fund identifiers are sent. README names the new source under privacy.

### Owner feedback: Dividends in the income forecast (switch)

- **What:** A switch "Dividends in income forecast" under Settings, Finance, Portfolio, off by default. When on, each expected dividend after today counts as planned income in the period's income, projected balance, and events, on the account of the position's last payment.
- **Why:** The owner wants the dividends in the forecast, but only after turning it on.
- **Effect:** Off changes nothing; the money reference test is unchanged. On, the forecast and the projected balance grow by the expected dividends. The switch is in the backup.

### Owner feedback: Position details per period, plan purchases at forecast price

- **Details per period:** A position's details show value, quantity, and lots as of the selected period's last day. Past periods leave out later lots; future periods add each expected savings plan purchase as "Savings plan (forecast)", which cannot be edited.
- **Forecast price:** With the return scenario, each future plan execution of an ETF buys at the price expected on its day, so later executions buy fewer shares. Without the scenario nothing changes.
- **Why:** The details showed today's lots and value in every period, and plan shares were bought at today's price even when the forecast price had grown.

### Owner feedback: Step goal with its own challenge

- **What:** A daily step goal in setup and under Settings, Health (0 = off). With Apple Health on, it becomes a daily challenge worth 20 coins with streak and freezes. It checks itself off when Apple Health reports the goal and cannot be checked by hand or put into a time slot. At 20:00 a note says the steps read last and how many are left.
- **Why:** Requested by the owner; this settles the open proposal of automatic challenges from Health values for steps.
- **Effect:** The app reads the steps when it comes to the front and books every reached day since the challenge began, so a day is booked late if the app was not opened. The goal is in the full backup.

### Owner feedback: Booking and steps in the background

- **Bank notices:** The Shortcuts action no longer opens Lifify. It books in the background, updates budget alerts and widget amounts before it ends, and answers like "12,50 € gebucht: REWE". The booking rules are unchanged.
- **Steps:** Lifify watches the step count through Apple Health's background delivery, about once an hour. Each update books reached step-challenge days, refreshes the widget's steps, and reschedules the evening note. New entitlement: HealthKit background delivery, already in the owner's profile.
- **README:** The Shortcuts guide now says which triggers iOS offers (Wallet, message, email) instead of a push trigger that does not exist.

### Owner decision: The unused transfer question is gone

- **What:** The import question "Is this a transfer?" is removed: `ImportTransferChoice`, the review's transfer list, its section in the review sheet, the code that applied the answers, and the two builders `transferChoice` and `transferMatch`.
- **Why:** The import had not asked it for a long time; own-account transfers are linked automatically. The owner confirmed he only knows the duplicate-booking question.
- **Effect:** No visible change. The money reference was re-recorded; the diff contains only the removed count fields, the empty section header, and the hand-made answers of the removed path. All other amounts and bookings are identical. Nothing stored or in a backup changed.

### Owner feedback: Importing older months later

- **What:** An import from Settings books rows dated before the account's oldest booking directly. The opening balance of every touched account moves to the new first day and drops by exactly those bookings.
- **Why:** The owner imported a 90-day export in setup and then the full year. The 658 older rows ended up as review questions, and the opening stayed in August.
- **Effect:** Older months can be added at any time; every later balance and today's stand stay the same. Days inside the known range keep the duplicate review. Test: `ImportBackfillTests`.

### Owner feedback: Saveback is cashback

- **What:** Trade Republic Saveback is booked as cashback income on the depot, not as a purchase from the Trade Republic account. Its shares carry no purchase cost, like a portfolio gift, so their whole value shows green. The session still reads Saveback like a buy to size the shares and rewrites it before the cash is reconciled; existing bookings are rewritten at launch (`SavebackRepair`).
- **Why:** The 2 Nov Saveback of 15 € showed as "Kauf: MSCI World" and lowered the Trade Republic balance.
- **Effect:** Trade Republic cash is no longer charged for Saveback. Until the next Trade Republic refresh, an existing balance adjustment can leave its stand 15 € higher; a refresh reconciles it. Test: `SavebackRepairTests`.

### Owner feedback: Share list in the app style

- **What:** The rows of the share list (normal and deep analysis) use the card color of the chosen style; the selected share adds a light tint.
- **Why:** Each row set its own background only for the selection and left the others to the system color, so the list was black in dark mode.

### Owner feedback: Live balance pin at the moment of reading

- **What:** The Trade Republic balance adjustment (the stand read from the session) is dated at the moment of reading, not at midnight.
- **Why:** At midnight, every trade booked later that day was added to a stand that already contained it.
- **Effect:** Only bookings after the reading change the stand. The money reference changed only in the time of that adjustment (00:00 to the fixed test time); all amounts are identical. Test: `LiveBalancePinTests`.

### Owner feedback: Income and expense lists in the app style

- **What:** The total and the booking rows under Income and Expenses sit in a styled section with the card color of the chosen style.
- **Why:** They stood outside any section and showed the plain system color, black in dark mode.

### Owner feedback: Interest forecast on the depot's cash account

- **What:** A switch "Interest forecast on cash account" with a yearly rate (2.5 % unless changed) under Settings, Finance, Portfolio, off by default. When on, each future month end's projected balance of the trade checking account (else Trade Republic) earns a twelfth of the rate, paid on the next first; earlier payouts raise later balances, so it compounds.
- **Why:** Requested by the owner; booked interest existed, forecast interest did not.
- **Effect:** Off changes nothing. On, the forecast income, projected balance, and events contain "Interest (forecast)". Both settings are in the full backup. Test: `CashInterestTests`.

### Owner decision: One rules file, app lock dropped

- **What:** The lasting parts of the 0.6.0 work plan (working together, workflow, technical guardrails, confirmed rules, decisions, open work) joined the rules in both languages. The rules file is now CLAUDE.md (formerly RULES.md), so Claude Code reads it at every start; the finished plan is gone. The planned app lock with Screen Time (B13) is dropped.
- **Why:** Most of the 0.6.0 plan is done. The app lock needs Family Controls, which the owner's free personal developer team cannot get.
- **Effect:** No code change. CLAUDE.md is the one place for project rules.

### Owner decision: All documents in Documentation, one file per area

- **What:** The folder Changes Documentation is now Documentation, with English file names. FINANZEN.md is FINANCE.md, ERNAEHRUNG.md is HEALTH.md (now with training, steps, and Apple Health), and CHALLENGES.md and GENERAL.md are new. Each explains what its area can do and how it works, in both languages. FEATURES.md is gone; its content is split into these files. Only README.md and CLAUDE.md stay at the top.
- **Why:** One place for documentation, sorted by the app's areas.
- **Effect:** All links in README, CLAUDE.md, and the changelogs point to the new paths.

### Owner feedback: Reminders list for challenges

- **What:** New challenges are created as reminders in a list chosen under Settings, Calendar sync. Automatic picks a list named To-Do, else the system default. Existing reminders keep their list. The choice is in the full backup.
- **Why:** Challenges landed in the shopping list, the system default on the owner's devices.
- **Effect:** With a To-Do list present, nothing needs to be set. Test: `ReminderListChoiceTests`.

### Owner feedback: Finance polish

- **Income forecasts:** Expected dividends and forecast interest of the selected period are entries among the income forecasts. The folded twelve-month dividend block is gone.
- **Forms:** All 38 forms use the shared `AppForm`, so their rows take the style's card color instead of the system gray.
- **Fixed costs:** The savings plan card and the costs form one rounded card; the period line is its header.
- **Variable costs:** An icon can be chosen and shows in the list.
- **Plan names:** Savings plans that only carried an ISIN get the fund's name from Yahoo Finance; a later Trade Republic sync no longer overwrites a real name with the ISIN.

### Owner feedback: Depot details and challenge fixes

- **Depot lots:** Each purchase lot in a holding's details shows its gain or loss at today's price, green or red. Gifts and cashback count from a cost of zero; sales show none. Logic: `HoldingLotGain` in LififyFinance. Test: `LotGainTests`.
- **Deep analysis:** A spinner shows while the analysis is computed, and a capsule while fund compositions load, so the screen no longer looks frozen.
- **Challenge from a calendar series:** After adopting, the full challenge form opens, so coins and the other fields can be set.
- **Freezes at streak 0:** A missed period at streak 0 without any progress spends no freeze. A started period still uses one. Why: the owner saw freezes vanish without a streak to protect. Tests: `aZeroStreakSpendsNoFreeze`, nutrition scenario updated.
- **Pinning:** Pins of deleted challenges filled the limit, so sport and automatic challenges could not be pinned. Stale pins are now pruned before pinning (`ChallengePinStore.prune`). Test: `ChallengePinPruneTests`.
- **Dismissing suggestions:** Challenge suggestions get "Dismiss", like fixed-cost suggestions. Storage: new link kind `recommendationRejection` in the existing link table, no schema change; it is part of the challenge backup scope, and old backups simply have none. Test: `RecommendationRejectionTests`.

### Owner feedback: Training plans and weekly rotation

- **Copy:** A plan's context menu has "Duplicate". The copy gets new IDs for plan, exercises, and sets, so calendar links and history stay with the original; the editor opens on the copy. Test: `aCopySharesNoIDsButKeepsTheContent`.
- **Order:** Plans are sorted by name (number-aware) instead of by last change. Only the shown order changes; the stored file is unchanged. Test: `plansSortByNameNumberAware`.
- **Tiles:** A tile shows every exercise icon that fits its width and a "+n" badge for the rest, instead of always three (`OverlapStrip`). Test: `theIconStripShowsAllWhenThereIsRoomAndABadgeOtherwise`.
- **Home and widget:** With several plans on the same recurring events, each plan is due once per week. Each event now shows one plan, finished plans on their day first, then the open ones, instead of every plan at every event. A single day still sees its whole week. The widget's next training follows the same rule. Test: `threePlansOnThreeWeeklyEventsShowEachPlanOnce`.

### Owner feedback: Steps by hour

- **Day view:** The step chart has a third range, "Day", with one bar per hour and the day's total. Arrows and swipes page through earlier days. Why: the owner wanted to see when in the day the steps came. Effect: Apple Health is asked for hourly sums of the shown day only; nothing is stored. Tests: `theDayViewFillsAllHoursAndStaysSilentUntilAllowed` (24 hours, the 23-hour clock-change day, silent until allowed).

## Deutsch

### Überblick

Version 0.6.0 verbessert zuerst die Codebasis (Teil A) und ergänzt danach neue
Funktionen (Teil B). Teil B ist fertig. Aus Teil A sind der Umbau von zwei
Screens und ein Teil der Methoden-Zerlegung noch offen (siehe letzter Abschnitt).

### 0.6.0: Testbarer Kalenderzugriff (A1)

- **Was:** Alle Zugriffe auf den Systemkalender und die Erinnerungen laufen
  jetzt über das Protokoll `CalendarGateway`. Die App nutzt
  `EventKitCalendarGateway`, Tests eine Attrappe, die jeden Aufruf aufzeichnet.
- **Warum:** Die Pfade, die echte Kalendertermine umschreiben oder löschen,
  hatten keine Tests.
- **Auswirkung:** Sichtbar ändert sich nichts. Neue Tests decken das
  Umschreiben nach dem Abhaken, `WorkoutCalendarSync.apply` und `cleanup`,
  Abstinenz-Boni über `settle` und Rückfall, den Kalenderimport sowie die
  Wiederherstellung von Gesamt- und Gesundheits-Backup ab.
- **Nebenwirkungen:** Tests erreichen keinen echten Kalender mehr. Verschieben
  sich mehrere Termine gleichzeitig, werden sie im Kalender jetzt nacheinander
  statt parallel umgeschrieben. Die doppelte Übersetzung der Wiederholungen ist
  zusammengeführt.

### 0.6.0: Schlankere Screens (A2, in Arbeit)

- **Was:** Depot und Challenge-Übersicht rechnen über Screen-Modelle
  (`PortfolioScreenModel`, `ChallengeBoardModel`). Eine Buchungszeile ermittelt
  Kategorie und Verkaufsergebnis nur noch einmal pro Darstellung.
- **Warum:** Das Depot wiederholte seine Berechnungen für jede Zeile. Jede
  Challenge-Karte durchsuchte die Abschlüsse aller Challenges.
- **Auswirkung:** Gleiche Werte und gleiches Aussehen, aber schnellere erste
  Aufrufe. Release-Build im iPhone-17-Simulator mit 5.000 Buchungen, 30
  Positionen, 1.200 Lots, 365 Kursen je Position, 100 Challenges und 3.000
  Abschlüssen:

  | Screen | Vorher (Median) | Nachher (Median) |
  | --- | ---: | ---: |
  | Depot | 1,9 s | 0,5 s |
  | Challenges, Lauf 1 | 1,8 s | 0,6 s |
  | Challenges, Lauf 2 | 3,6 s | 0,35 s |

- **Grenzen:** Simulatorläufe schwanken stark, deshalb zählen nur deutliche
  Unterschiede. Finanzübersicht, Buchungen und Datenverwaltung zeigten keine
  messbare Änderung. Ein zusätzlicher Prognose-Zwischenspeicher für die
  Übersicht brachte nichts und wurde wieder entfernt.
- **Messen:** `ScreenPerformanceTests` wird in normalen Testläufen übersprungen
  und startet mit `TEST_RUNNER_LIFIFY_MEASURE=1`.

### 0.6.0: Alte Gruppenspalte entfernt (A3)

- **Was:** Das Datenbankschema V4 entfernt `ChallengeItem.groupID`. Bevor die
  Spalte wegfällt, kopiert die Migration eine Gruppe, die nur dort steht, nach
  `groupIDsRaw`.
- **Warum:** Die Gruppenzugehörigkeit lag doppelt vor.
- **Abweichung vom Plan:** `groupIDsRaw` bleibt, weil diese Spalte die aktuelle
  Quelle aller Gruppenzugehörigkeiten ist. Ohne sie gingen sie verloren. Keine
  weitere Spalte erwies sich als ungenutzt und sicher entfernbar.
- **Auswirkung:** Sichtbar ändert sich nichts. Eine mit dem echten 0.5.5-Code
  geschriebene Datenbank mit erfundenen Daten ist jetzt Testbestand. Sie öffnet
  mit allen Daten und Gruppen.
- **Geänderte Tests:** Der Test zur Einzelgruppe prüft jetzt `groupIDs`. Der
  alte Normalisierungstest wurde durch die Migrationstests ersetzt, weil es
  nach der Migration keinen Eintrag mehr gibt, der nur die alte Spalte kennt.

### 0.6.0: Lesbare Dokumente (A5)

- **Was:** Lange Passagen in `FINANCE.md` sind jetzt Listen. Die Einrichtung
  nennt beim teilweisen Wiederherstellen Gesundheit (Trainings und Mahlzeiten)
  statt Training.
- **Warum:** Die Regeln waren schwer zu überblicken, und der Bereich heißt seit
  0.5.5 Gesundheit.
- **Auswirkung:** Der Wortlaut aller Finanzregeln bleibt gleich. Ein Skript hat
  alle Wörter vor und nach der Umformatierung verglichen.

### 0.6.0: Entwicklermodus verändert keine echten Coins mehr (A6)

- **Was:** Solange der Entwicklermodus einen anderen Tag zeigt, merkt sich
  Lifify Coin-Buchungen, Abhaken, Käufe, Freezes, Abstinenz-Boni und den
  Geburtstagsbonus. Zurück auf dem echten Tag, beim Start oder beim Ausschalten
  des Modus werden genau diese Änderungen rückgängig gemacht.
- **Warum:** Simulierte Tage haben bisher dauerhaft Coins ausgezahlt.
- **Auswirkung:** Der Entwicklermodus lässt sich zum Testen nutzen, ohne das
  echte Wallet zu verändern. Boni lassen sich an ihrem echten Tag wieder
  verdienen.
- **Heute:** Mahlzeiten-Belohnungen folgen jetzt dem simulierten Tag.
- **Bewusst auf der echten Uhr:** Das Aufräumen vergangener Trainingstermine
  bleibt beim echten Datum, damit ein simulierter Tag nie echte Termine aus dem
  iOS-Kalender löscht.
- **Grenzen:** Mahlzeiten, die an einem simulierten Tag eingetragen wurden,
  bleiben, nur ihre Coins und Fast-Food-Abbuchungen werden zurückgenommen. Eine
  echte Buchung, die während der Simulation entfernt wird, kommt nicht zurück.
  Ein Backup aus einer laufenden Simulation enthält die simulierten Buchungen
  als normale Daten.

### 0.6.0: Face ID für Finanzen (A7)

- **Was:** Der Tab Finanzen wird mit Face ID oder dem Gerätecode entsperrt und
  sperrt sich wieder, wenn die App in den Hintergrund geht. Der Schalter liegt
  unter Einstellungen, Finanzen, und ist standardmäßig an. Ein zweiter Schalter
  legt fest, ob Finanz-Widgets Beträge zeigen dürfen (standardmäßig aus).
- **Warum:** Finanzdaten sollen privat bleiben, wenn jemand anderes das
  entsperrte iPhone in der Hand hat.
- **Auswirkung:** Solange gesperrt ist, werden die Finanz-Screens gar nicht
  aufgebaut.
- **Zusätzliche Absicherung:** Das Ausschalten der Sperre und das Anzeigen von
  Beträgen in Widgets verlangen Face ID. Ein Backup enthält diese Schalter nie.
- **Grenzen:** Gesperrt ist wie vereinbart nur der Tab Finanzen. Home und die
  Finanz-Einstellungen zeigen ihre Inhalte weiter. Ein Gerät ohne Code lässt
  sich nicht sperren, dort bleibt Finanzen offen.

### 0.6.0: Referenztest für die Geld-Pfade (A8)

- **Was:** `MoneyReferenceTests` führt Bankimport, Trade-Republic-Auszug und
  Live-Sitzung, Bankmitteilungen, Home-Budget und Prognosen mit festen Daten an
  einem festen Datum aus. Das gesamte Ergebnis wird mit einer gespeicherten
  Referenz verglichen.
- **Warum:** Als Nächstes werden die langen Finanzmethoden zerlegt, und ihre
  Ergebnisse müssen gleich bleiben.
- **Auswirkung:** Sichtbar ändert sich nichts. `FinanceClock` macht die Zeit in
  Tests festlegbar. Tests laden keine Live-Kurse mehr.
- **Grenzen:** Die Referenz deckt die Hauptpfade ab. Selten genutzte
  Reparaturpfade für ältere Trade-Republic-Importe sind nur teilweise erfasst
  und bleiben unzerlegt, bis sie eigene Tests haben.

### 0.6.0: Progressive Overload (B11)

- **Was:** Jede Übung im laufenden Training zeigt einen Gewichtsvorschlag. Er
  steigt um eine einstellbare Stufe (Standard 2,5 kg), wenn im letzten Training
  alle Zielwiederholungen geschafft wurden, sonst bleibt er gleich. Der Plan
  zeigt das Volumen jeder Übung pro Training.
- **Warum:** Das nächste Gewicht soll man nicht von Hand ausrechnen müssen.
- **Auswirkung:** Der Vorschlag wird nur per Tipp übernommen. Der bisherige
  Hinweis nach drei erfolgreichen Trainings bleibt und hat Vorrang.

### 0.6.0: Mahlzeiten-Favoriten (B12)

- **Was:** Ein Herz markiert eine Mahlzeit als Favorit. Favoriten und zuletzt
  gegessene Mahlzeiten stehen über den Mahlzeiten des Tages und lassen sich mit
  einem Tipp erneut eintragen.
- **Warum:** Regelmäßige Mahlzeiten sollen nicht jedes Mal neu getippt oder
  fotografiert werden.
- **Auswirkung:** Ein neuer Eintrag übernimmt Name, Nährwerte und Art, aber kein
  Foto. Eine wiederholte Fast-Food-Mahlzeit wird wie jede neue abgebucht.
  Favoriten sind Teil des Gesamt- und Gesundheits-Backups.

### 0.6.0: Monatsrückblick und Abo-Erkennung (B4, B5)

- **Was:** Unter Finanzen, Weitere Bereiche gibt es jetzt den Monatsrückblick und
  Abo-Vorschläge. Der Rückblick vergleicht den letzten abgeschlossenen Zeitraum
  je Kategorie mit bis zu sechs früheren, die größte Abweichung zuerst. Er folgt
  dem gewählten Zeitraum. Eine optionale Mitteilung öffnet ihn zum Zeitraumende.
- **Abos:** Wiederkehrende Zahlungen an denselben Empfänger, höchstens 10 % vom
  üblichen Betrag entfernt, wöchentlich, zweiwöchentlich, monatlich oder
  jährlich, mit mindestens drei Zahlungen, werden als Fixkosten vorgeschlagen.
  Abgelehnte Vorschläge bleiben weg und sind Teil des Backups.
- **Warum:** Ungewöhnliche Ausgaben und vergessene Abos sollen leicht auffallen.
- **Auswirkung:** Ein angenommener Vorschlag legt die Fixkosten an und verknüpft
  die bisherigen Zahlungen. Ein Abo, dessen Zahlungen aufgehört haben, wird nicht
  vorgeschlagen.
- **Geänderte Tests:** Der Navigationstest erwartet die zwei neuen Links.

### 0.6.0: Budget-Warnungen (B3)

- **Was:** Eine lokale Mitteilung erscheint, wenn eine variable Kostenposition
  oder ein Budgetpool 80 % und 100 % erreicht und wenn das Tagesbudget
  überschritten ist. Schwellen und Schalter liegen unter Einstellungen, Finanzen.
- **Warum:** Ein überzogenes Budget soll auffallen, solange man noch reagieren
  kann.
- **Auswirkung:** Die Prüfung läuft nach jeder gespeicherten Buchung, auch aus
  Kurzbefehlen und Importen. Jede Schwelle meldet sich einmal pro Zeitraum. Nur
  der laufende Zeitraum zählt, mehrere Warnungen kommen als eine Mitteilung.

### 0.6.0: Dividenden-Übersicht und Prognose (B6)

- **Was:** Unter Finanzen, Weitere Bereiche stehen jetzt die erhaltenen
  Dividenden je Position, Monat und Jahr, dazu eine Prognose der nächsten zwölf
  Monate.
- **Warum:** Dividenden waren bisher nur als einzelne Buchungen sichtbar.
- **Auswirkung:** Die Prognose wiederholt jede Zahlung der letzten zwölf Monate
  ein Jahr später, mit ihrer Dividende je Stück und dem dann gehaltenen Bestand,
  inklusive künftiger Sparplan-Stücke. Thesaurierende ETFs zahlen nichts und
  erscheinen nicht.
- **Geänderte Tests:** Der Navigationstest erwartet den neuen Link.

### 0.6.0: Optionales Renditeszenario (B7)

- **Was:** Ein Schalter unter Einstellungen, Finanzen, Depot lässt ETFs in
  künftigen Prognosezeiträumen mit ihrer eigenen historischen Rendite wachsen:
  10 Jahre, sonst 5 Jahre, sonst 3 %. Die Seite zeigt Satz und Grundlage jeder
  Position, die ETF-Erkennung lässt sich von Hand korrigieren.
- **Warum:** Eine Prognose mit festen Kursen unterschätzt ein langfristiges
  ETF-Depot.
- **Auswirkung:** Standardmäßig aus, dann bleibt jede Prognose exakt wie bisher.
  Vergangene Zeiträume und der laufende ändern sich nie. Werte mit Szenario sind
  gekennzeichnet. Aktien, Krypto und Sonstiges bleiben beim heutigen Kurs.
- **Grenzen:** Vergangene Renditen sind keine Garantie. Die Renditen stammen von
  Yahoo Finance in der Währung des Handelsplatzes.

### 0.6.0: Depot-Anteile, Design und Tiefenanalyse (B8)

- **Was:** Die Anteile-Ansicht nutzt jetzt die Stile der App und hat einen
  Umschalter zwischen Normal und Tiefenanalyse. Die Tiefenanalyse bricht ETFs in
  ihre Unternehmen auf und zeigt deren Anteil am gesamten Depot.
- **Daten:** Dateien von Xtrackers und VanEck werden höchstens einmal pro Woche
  geladen. Index-ETFs von iShares und Amundi nutzen den Xtrackers-Fonds auf
  denselben Index. Für alles andere lässt sich eine CSV- oder Excel-Datei von
  Hand importieren, sie hat Vorrang.
- **Abweichung vom Plan:** Die iShares-Seite bietet keinen direkten Download der
  Bestände mehr, deshalb ersetzt Xtrackers iShares als Index-Stellvertreter.
- **Offen:** iShares MSCI World Small Cap und iShares Space Technologies haben
  keine automatische Quelle und brauchen einen manuellen Import.
- **Auswirkung:** Einträge unter 0,1 % stehen zusammen unter Sonstige. Hebel-ETFs
  zählen mit ihrem Hebel, das wird unter der Liste erklärt.

### 0.6.0: Siri und Kurzbefehle (B2)

- **Was:** Neue Aktionen haken eine Challenge ab, tragen eine Mahlzeit ein und
  nennen das Restbudget. Sie funktionieren per Sprache und in der Kurzbefehle-App.
- **Warum:** Kleine tägliche Einträge sollen ohne Öffnen der App gehen.
- **Auswirkung:** Sport mit verknüpftem Training und Abstinenz lassen sich so
  nicht abhaken. Ein Abhaken entfernt nie einen vorhandenen Haken. Eine Mahlzeit
  mit dem Namen eines Favoriten übernimmt dessen Nährwerte. Die Budget-Antwort
  braucht ein entsperrtes Gerät.

### 0.6.0: Apple Health (B10)

- **Was:** Ein optionaler Schalter unter Einstellungen, Gesundheit verbindet
  Apple Health. Gelesen werden Gewicht, Schritte, aktive Energie und Ruhepuls,
  beendete Trainings werden als Workouts gesichert. Der Gesundheit-Tab zeigt
  Tageswerte und einen kurzen Verlauf als Zahlen.
- **Warum:** Körperdaten und Training sollen nicht doppelt gepflegt werden.
- **Auswirkung:** Ohne Freigabe funktioniert alles wie bisher. Ein neueres Gewicht
  aktualisiert die Körperdaten und damit das Kalorienziel. Jedes Training wird
  einmal gesichert.
- **Einrichtung:** Die App braucht jetzt die HealthKit-Berechtigung. Siehe die
  Schritte für das Apple-Developer-Konto.
- **Nicht gebaut:** Schlaf bleibt draußen, bis der Eigentümer entschieden hat.

### B1 und B9: Widgets und Live Activity fürs Training

- **Widgets:** Tagesbudget, Heute (interaktiv), Coins & Streak, Depot, Nächstes Training, Überblick und drei Widgets für den Sperrbildschirm. Warum: Plan für 0.6.0. Auswirkung: Die wichtigsten Werte sind ohne Öffnen der App sichtbar.
- **Datenweg abweichend vom Plan:** Die Datenbank bleibt, wo sie ist. Die App schreibt eine kleine Snapshot-Datei in die App Group. Warum: Der Umzug des Stores gefährdet echte Daten, und ein schreibendes Widget könnte die Buchungsregeln umgehen. Auswirkung: keine Migration; Widgets zeigen den Stand der letzten App-Aktualisierung.
- **Abhaken im Widget:** Der Tipp wird vorgemerkt und verschwindet sofort aus dem Widget. Die App bucht ihn mit allen Regeln, sobald sie das nächste Mal läuft. Auswirkung: Coins und Streak ändern sich erst nach dem Öffnen der App.
- **Finanzsperre:** Bei aktiver Sperre landen Beträge gar nicht erst im Snapshot, außer „Finanzwerte in Widgets zeigen“ ist an.
- **Sport mit verknüpftem Training** ist im Widget nicht abhakbar. Ein Tipp öffnet das Training und ersetzt nie eine laufende Session.
- **Live Activity:** Plan, Übung, Satz, Trainingszeit und Pausen-Timer auf Sperrbildschirm und Dynamic Island, nur für laufende Trainings.
- **Einrichtung:** Die App Group `group.com.mwetzka03.lifify` und das Target `com.mwetzka03.lifify.widgets` müssen für den Build aufs iPhone im Apple-Developer-Konto vorhanden sein.

### A8: Daten-Screen, Benennung und was noch offen ist

- **Daten-Screen:** Er hält keine 20 Live-Abfragen mehr, sondern liest die Daten erst beim Erstellen einer Sicherung. Warum: Die Abfragen dienten nur dem Export. Auswirkung: gleiche Sicherung, leichterer Screen.
- **Mahlzeitenerkennung:** `thinking` heißt jetzt `disablesThinking`, denn genau das tut der Schalter. Die Anfrage ist unverändert.
- **Offen aus A8 und A2:** `DashboardView` und `TransactionsView` sind nicht umgebaut, und rund 160 Methoden bleiben über 30 Zeilen, vor allem bei Trade Republic, Backup und in Views. Warum: Sie betreffen Geld- und Backup-Pfade und sollen sich erst nach dem ersten Test auf einem echten iPhone ändern.

### Fehlerbehebung: Finanzübersicht nach dem Bearbeiten

- **Was:** Die Finanzübersicht rechnet neu, wenn sich Betrag, Konto, Rhythmus oder Status einer Fixkosten, Einnahmeprognose, eines Budgets, Einkaufs, Splits oder Kontos ändert. Vorher bemerkte sie nur neue oder gelöschte Einträge.
- **Warum:** Nach dem Bearbeiten, etwa des Betrags einer Fixkosten, zeigte die Übersicht den alten Wert, bis sich etwas anderes änderte.
- **Auswirkung:** Die Übersicht ist direkt nach dem Speichern aktuell. Die Buchungsliste reagiert ebenso auf geänderte Konten. Eine reine Umbenennung löst keine Neuberechnung aus.

### Fehlerbehebung: Datenbank bleibt im App-Ordner

- **Was:** Der Pfad der Datenbank ist jetzt fest auf den eigenen App-Ordner gelegt (`Application Support/default.store`).
- **Warum:** Auf dem iPhone gefunden. Mit der neuen App Group hat SwiftData die Datenbank selbstständig in den Gruppen-Container kopiert und diese Kopie genutzt. Archiv und Wiederherstellung suchten weiter im App-Ordner.
- **Auswirkung:** Die App nutzt wieder ihre ursprüngliche Datenbank. Eine Kopie vom ersten Start von 0.6.0 bleibt ungenutzt in der App Group liegen; gelöscht wurde nichts. Ein Test sichert den Pfad.

### Rückmeldung des Eigentümers: Schritte unter Training

- **Was:** Ein Bereich Schritte unter Training, zwischen den Plänen und dem Verlauf: heute, Durchschnitt über 7 und 30 Tage, bester Tag und ein Balkendiagramm über 7 oder 30 Tage mit dem Durchschnitt als Linie. Er ersetzt die Apple-Health-Karte über den Tabs.
- **Warum:** Der Eigentümer fand die Karte wenig hilfreich und will die Schritte beim Training.
- **Auswirkung:** Durchschnitte lassen heute und Tage ohne Daten weg. Lifify liest nur noch Gewicht und Schritte; aktive Energie und Ruhepuls werden nicht mehr gelesen. Das Schreiben beendeter Trainings nach Apple Health bleibt und steht jetzt im Text des Schalters.

### Rückmeldung des Eigentümers: Abos, Dividenden und Tiefenanalyse

- **Abo-Vorschläge:** Sie stehen nicht mehr unter Weitere Bereiche, sondern oben in den Fixkosten, standardmäßig eingeklappt. Warum: Dort entstehen Fixkosten.
- **Dividenden:** Sie stehen nicht mehr unter Weitere Bereiche, sondern eingeklappt unter den Einnahmeprognosen in Einnahmen. Die Liste zeigt nur Positionen, die noch zahlen; verkaufte Fonds stehen nur im Erhaltenen. Die Prognose wird nur angezeigt und zählt in keine Prognose und keinen Saldo.
- **Grafik der Tiefenanalyse:** Die Grafik fasst alles unter 0,5 % zu Sonstige zusammen; die Liste bleibt bei 0,1 %. Warum: Mit vielen dünnen Stücken war die Grafik nicht lesbar.
- **Fehlende Aufteilungen:** Trade Republic benennt Fonds ohne Anbieter, etwa „Rare Earth & Strategic Metals USD (Acc)“. Fonds werden jetzt zuerst über die ISIN gefunden. Auswirkung: AI & Big Data, Rare Earth, Space Innovators und World ex USA werden wieder aufgeteilt. iShares World Small Cap und Space Technologies brauchen weiter einen manuellen Import.

### Rückmeldung des Eigentümers: Kalorien-Mitteilung und Tagesbriefing

- **Kalorien-Mitteilung:** Um 20:00 Uhr meldet die Kalorien-Challenge den Stand gegenüber dem Ziel statt „wartet noch auf den Haken“: Im Defizit lobt sie und nennt die verbleibenden kcal, beim Aufbau die noch fehlenden. Sie wird nach jeder Änderung der Mahlzeiten neu geplant.
- **Tagesbriefing:** Die Zeile zum Gehalt entfällt. Warum: Sie bringt dem Eigentümer täglich nichts.

### Rückmeldung des Eigentümers: Depot-Gewinne in künftigen Zeiträumen

- **Was:** In einem künftigen Zeitraum ist der Gewinn einer Position der Prognosewert minus heutigem Einstand plus allen Sparplan-Beträgen bis zum Zeitraumende. „Heute“ zeigt das Wachstum ab dem heutigen Wert plus dem neuen Geld. Depot-Ansicht und Depot-Kachel nutzen beide diese Rechnung.
- **Warum:** Mit Renditeszenario wuchs der Wert, der Gewinn blieb aber beim heutigen Stand.
- **Auswirkung:** Mit Szenario wachsen die Gewinne mit der Prognose. Ohne Szenario bleiben sie wie bisher beim heutigen Gewinn. Heute und vergangene Zeiträume sind unverändert.

### Rückmeldung des Eigentümers: Schritte blättern und Aktivität auf der Startseite

- **Schritte blättern:** Ein Wisch über das Diagramm oder die Pfeile zeigt die 7 oder 30 Tage davor; die Linie zeigt den Durchschnitt dieser Seite. Dafür liest Lifify jetzt ein Jahr Schritte.
- **Startseite:** Unter dem Kalender zeigt eine Karte Schritte und geplante Trainings des gewählten Tages, der Woche oder des Monats. Woche und Monat zeigen Summe und Tagesdurchschnitt. Trainings kommen aus Kalenderterminen mit verknüpftem Plan, direkt oder über die Challenge, und bekommen einen Haken, sobald an dem Tag eine Session des Plans beendet wurde.
- **Warum:** Der Eigentümer will zurückblättern und die Aktivität neben dem Kalender sehen. Auswirkung: Ein verschobener oder gelöschter Termin ändert die Karte sofort.

### Rückmeldung des Eigentümers: Schritte im Widget Überblick

- **Was:** Das große Widget Überblick zeigt unter dem nächsten Training die heutigen Schritte mit der Uhrzeit, zu der sie gelesen wurden.
- **Warum:** Wunsch des Eigentümers. Ein Widget kann Apple Health nicht selbst lesen. Deshalb liest die App die heutigen Schritte bei jedem Öffnen und schreibt sie in die Widget-Daten.
- **Auswirkung:** Die Zahl ist so aktuell wie der letzte App-Start; die Uhrzeit zeigt das. Ist Apple Health aus oder lief die App an einem neuen Tag noch nicht, fehlt die Zeile.

### Rückmeldung des Eigentümers: iShares-Zusammensetzungen laden automatisch

- **Was:** iShares ist ein dritter Anbieter. Die Bestände kommen als CSV vom Produktdatendienst von BlackRock, dieselbe Datei, die die Fondsseite anbietet. iShares MSCI World Small Cap und iShares Space Technologies sind über die ISIN zugeordnet.
- **Warum:** Beide brauchten bisher einen manuellen Import.
- **Auswirkung:** Alle Fonds des Eigentümers werden automatisch aufgeteilt. Gesendet werden nur Fonds-Kennungen. Die README nennt die neue Quelle unter Datenschutz.

### Rückmeldung des Eigentümers: Dividenden in der Einnahmeprognose (Schalter)

- **Was:** Ein Schalter „Dividenden in Einnahmeprognose“ unter Einstellungen, Finanzen, Depot, standardmäßig aus. Ist er an, zählt jede erwartete Dividende nach heute als geplante Einnahme in Einnahmen, prognostiziertem Saldo und Ereignissen des Zeitraums, auf dem Konto der letzten Zahlung dieser Position.
- **Warum:** Der Eigentümer will die Dividenden in der Prognose, aber erst nach dem Einschalten.
- **Auswirkung:** Aus ändert nichts; der Referenztest der Geldrechnung ist unverändert. An wachsen Prognose und prognostizierter Saldo um die erwarteten Dividenden. Der Schalter ist im Backup.

### Rückmeldung des Eigentümers: Positionsdetails je Zeitraum, Sparplan zum Prognosekurs

- **Details je Zeitraum:** Die Details einer Position zeigen Wert, Stückzahl und Einzelpositionen zum letzten Tag des gewählten Zeitraums. Vergangene Zeiträume lassen spätere Einzelpositionen weg; künftige zeigen zusätzlich jeden erwarteten Sparplan-Kauf als „Sparplan (Prognose)“, der nicht bearbeitbar ist.
- **Prognosekurs:** Mit Renditeszenario kauft jede künftige Sparplan-Ausführung eines ETFs zum für ihren Tag erwarteten Kurs; spätere Ausführungen kaufen weniger Stücke. Ohne Szenario ändert sich nichts.
- **Warum:** Die Details zeigten in jedem Zeitraum die heutigen Einzelpositionen und den heutigen Wert, und Sparplan-Stücke wurden zum heutigen Kurs gekauft, auch wenn der Prognosekurs gestiegen war.

### Rückmeldung des Eigentümers: Schrittziel mit eigener Challenge

- **Was:** Ein tägliches Schrittziel in der Einrichtung und unter Einstellungen, Gesundheit (0 = aus). Mit Apple Health wird daraus eine tägliche Challenge über 20 Coins mit Streak und Freezes. Sie hakt sich selbst ab, wenn Apple Health das Ziel meldet, und lässt sich weder von Hand abhaken noch in einen Termin legen. Um 20:00 Uhr nennt eine Mitteilung die zuletzt gelesenen Schritte und den Rest bis zum Ziel.
- **Warum:** Wunsch des Eigentümers; damit ist der offene Vorschlag automatischer Challenges aus Health-Werten für Schritte entschieden.
- **Auswirkung:** Die App liest die Schritte beim Öffnen und bucht jeden erreichten Tag seit Beginn der Challenge nach; ohne Öffnen wird ein Tag also später gebucht. Das Ziel ist im Gesamt-Backup.

### Rückmeldung des Eigentümers: Buchen und Schritte im Hintergrund

- **Bankmitteilungen:** Die Kurzbefehl-Aktion öffnet Lifify nicht mehr. Sie bucht im Hintergrund, aktualisiert Budget-Warnungen und Widget-Beträge, bevor sie endet, und antwortet etwa mit „12,50 € gebucht: REWE“. Die Buchungsregeln sind unverändert.
- **Schritte:** Lifify beobachtet die Schritte über die Hintergrund-Zustellung von Apple Health, etwa einmal pro Stunde. Jede Meldung bucht erreichte Tage der Schritt-Challenge, aktualisiert die Schritte im Widget und plant die Abendmitteilung neu. Neues Entitlement: HealthKit-Hintergrund-Zustellung, im Profil des Eigentümers schon enthalten.
- **README:** Die Kurzbefehl-Anleitung nennt jetzt die Auslöser, die iOS anbietet (Wallet, Nachricht, E-Mail), statt eines Push-Auslösers, den es nicht gibt.

### Entscheidung des Eigentümers: Die ungenutzte Umbuchungs-Rückfrage ist entfernt

- **Was:** Die Import-Rückfrage „Ist das eine Umbuchung?“ ist entfernt: `ImportTransferChoice`, die Umbuchungsliste im Prüfbogen, ihr Abschnitt in der Prüfansicht, der Code, der die Antworten anwendete, und die beiden Bausteine `transferChoice` und `transferMatch`.
- **Warum:** Der Import stellte sie seit Langem nicht mehr; Umbuchungen zwischen eigenen Konten werden automatisch verknüpft. Der Eigentümer kennt nur die Rückfrage zu doppelten Buchungen.
- **Auswirkung:** Sichtbar ändert sich nichts. Die Geld-Referenz wurde neu aufgezeichnet; der Unterschied enthält nur die entfernten Zählerfelder, die leere Abschnittsüberschrift und die von Hand gebauten Antworten des entfernten Wegs. Alle übrigen Beträge und Buchungen sind identisch. Am Speicher und am Backup ändert sich nichts.

### Rückmeldung des Eigentümers: Ältere Monate nachträglich importieren

- **Was:** Ein Import aus den Einstellungen bucht Zeilen vor der ältesten Buchung des Kontos direkt. Der Eröffnungssaldo jedes betroffenen Kontos rückt auf den neuen ersten Tag und sinkt um genau diese Buchungen.
- **Warum:** Der Eigentümer hatte in der Einrichtung einen 90-Tage-Export und danach das ganze Jahr importiert. Die 658 älteren Zeilen landeten als Rückfragen, und der Eröffnungssaldo blieb im August.
- **Auswirkung:** Ältere Monate lassen sich jederzeit ergänzen; jeder spätere Stand und der heutige Kontostand bleiben gleich. Tage im bekannten Zeitraum behalten die Duplikat-Prüfung. Test: `ImportBackfillTests`.

### Rückmeldung des Eigentümers: Saveback ist Cashback

- **Was:** Trade-Republic-Saveback wird als Cashback-Einnahme im Depot gebucht, nicht als Kauf vom Trade-Republic-Konto. Die Stücke haben keinen Einstand, wie ein Depotgeschenk, ihr ganzer Wert erscheint also grün. Die Sitzung liest Saveback weiter wie einen Kauf, um die Stücke zu bestimmen, und schreibt es vor dem Kontoabgleich um; bestehende Buchungen werden beim Start umgeschrieben (`SavebackRepair`).
- **Warum:** Das Saveback vom 2. November über 15 € stand als „Kauf: MSCI World“ und senkte den Trade-Republic-Saldo.
- **Auswirkung:** Das Trade-Republic-Konto wird für Saveback nicht mehr belastet. Bis zur nächsten Trade-Republic-Aktualisierung kann eine bestehende Saldo-Korrektur den Stand um 15 € zu hoch lassen; eine Aktualisierung gleicht das aus. Test: `SavebackRepairTests`.

### Rückmeldung des Eigentümers: Anteile-Liste im App-Stil

- **Was:** Die Zeilen der Anteile-Liste (Normal und Tiefenanalyse) nutzen die Kartenfarbe des gewählten Stils; der gewählte Anteil bekommt eine leichte Tönung.
- **Warum:** Jede Zeile setzte ihren Hintergrund nur für die Auswahl und überließ die übrigen der Systemfarbe, deshalb war die Liste im Dunkelmodus schwarz.

### Rückmeldung des Eigentümers: Saldo-Korrektur zum Auslesezeitpunkt

- **Was:** Die Trade-Republic-Saldo-Korrektur (der aus der Sitzung gelesene Stand) wird auf den Zeitpunkt des Auslesens datiert, nicht auf Mitternacht.
- **Warum:** Um Mitternacht kam jeder später am selben Tag gebuchte Handel noch auf einen Stand, der ihn schon enthielt.
- **Auswirkung:** Nur Buchungen nach dem Auslesen ändern den Stand. Die Geld-Referenz änderte sich nur in der Uhrzeit dieser Korrektur (0:00 auf die feste Testzeit); alle Beträge sind gleich. Test: `LiveBalancePinTests`.

### Rückmeldung des Eigentümers: Einnahmen- und Ausgabenlisten im App-Stil

- **Was:** Summe und Buchungszeilen unter Einnahmen und Ausgaben stehen in einem gestylten Abschnitt mit der Kartenfarbe des gewählten Stils.
- **Warum:** Sie standen außerhalb jedes Abschnitts und zeigten die Systemfarbe, im Dunkelmodus schwarz.

### Rückmeldung des Eigentümers: Zinsprognose für das Depot-Verrechnungskonto

- **Was:** Ein Schalter „Zinsprognose Verrechnungskonto“ mit Zinssatz pro Jahr (2,5 %, solange nicht geändert) unter Einstellungen, Finanzen, Depot, standardmäßig aus. Ist er an, bekommt der prognostizierte Monatsend-Stand des Girokontos für Käufe (sonst Trade Republic) ein Zwölftel des Satzes, ausgezahlt am nächsten Monatsersten; frühere Auszahlungen erhöhen spätere Stände, es entsteht Zinseszins.
- **Warum:** Wunsch des Eigentümers; gebuchte Zinsen gab es, Prognosezinsen nicht.
- **Auswirkung:** Aus ändert nichts. An enthalten Einnahmeprognose, prognostizierter Saldo und Ereignisse „Zinsen (Prognose)“. Beide Einstellungen sind im Gesamt-Backup. Test: `CashInterestTests`.

### Entscheidung des Eigentümers: Eine Regeldatei, App-Sperre verworfen

- **Was:** Die bleibenden Teile des Arbeitsplans für 0.6.0 (Zusammenarbeit, Arbeitsweise, technische Leitplanken, bestätigte Regeln, Entscheidungen, offene Arbeit) stehen zweisprachig bei den Regeln. Die Regeldatei heißt jetzt CLAUDE.md (vorher RULES.md), damit Claude Code sie bei jedem Start liest; der erledigte Plan entfällt. Die geplante App-Sperre über Bildschirmzeit (B13) ist verworfen.
- **Warum:** Der Plan für 0.6.0 ist weitgehend umgesetzt. Die App-Sperre braucht Family Controls, die das kostenlose persönliche Entwicklerteam des Eigentümers nicht bekommt.
- **Auswirkung:** Keine Code-Änderung. Die CLAUDE.md ist der eine Ort für Projektregeln.

### Entscheidung des Eigentümers: Alle Dokumente in Documentation, eine Datei je Bereich

- **Was:** Der Ordner Changes Documentation heißt jetzt Documentation, mit englischen Dateinamen. FINANZEN.md heißt FINANCE.md, ERNAEHRUNG.md heißt HEALTH.md (jetzt mit Training, Schritten und Apple Health), und CHALLENGES.md und GENERAL.md sind neu. Jede erklärt zweisprachig, was ihr Bereich kann und wie er funktioniert. FEATURES.md entfällt; ihr Inhalt ist auf diese Dateien verteilt. Nur README.md und CLAUDE.md bleiben oben.
- **Warum:** Ein Ort für die Doku, nach den Bereichen der App sortiert.
- **Auswirkung:** Alle Links in README, CLAUDE.md und den Changelogs zeigen auf die neuen Pfade.

### Rückmeldung des Eigentümers: Erinnerungsliste für Challenges

- **Was:** Neue Challenges entstehen als Erinnerung in der Liste, die unter Einstellungen, Kalender-Sync gewählt ist. Automatisch nimmt eine Liste namens To-Do, sonst die Standardliste. Bestehende Erinnerungen bleiben in ihrer Liste. Die Wahl ist im Gesamt-Backup.
- **Warum:** Challenges landeten in der Einkaufsliste, der Standardliste auf den Geräten des Eigentümers.
- **Auswirkung:** Gibt es eine To-Do-Liste, muss nichts eingestellt werden. Test: `ReminderListChoiceTests`.

### Rückmeldung des Eigentümers: Feinschliff Finanzen

- **Einnahmeprognosen:** Erwartete Dividenden und Prognosezinsen des gewählten Zeitraums stehen als Einträge bei den Einnahmeprognosen. Der eingeklappte Zwölf-Monats-Block entfällt.
- **Formulare:** Alle 38 Formulare nutzen das gemeinsame `AppForm`, ihre Zeilen haben die Kartenfarbe des Stils statt Systemgrau.
- **Fixkosten:** Sparplan-Karte und Kosten bilden eine abgerundete Karte; die Zeitraumzeile ist ihre Überschrift.
- **Variable Kosten:** Ein Symbol ist wählbar und erscheint in der Liste.
- **Plan-Namen:** Sparpläne, die nur eine ISIN trugen, bekommen den Fondsnamen von Yahoo Finance; ein späterer Trade-Republic-Abgleich überschreibt einen echten Namen nicht mehr mit der ISIN.

### Rückmeldung des Eigentümers: Depotdetails und Challenge-Korrekturen

- **Depot-Einzelkäufe:** Jeder Kauf in der Detailansicht einer Position zeigt Gewinn oder Verlust zum heutigen Kurs, grün oder rot. Geschenke und Cashback zählen ab Einstand null; Verkäufe zeigen nichts. Logik: `HoldingLotGain` in LififyFinance. Test: `LotGainTests`.
- **Tiefenanalyse:** Während der Berechnung dreht ein Ladezeichen, beim Laden der Fondszusammensetzungen eine Kapsel, damit die Ansicht nicht eingefroren wirkt.
- **Challenge aus einer Kalenderserie:** Nach dem Übernehmen öffnet sich das volle Challenge-Formular, damit Coins und die übrigen Felder gesetzt werden.
- **Freezes bei Streak 0:** Ein verpasster Zeitraum bei Streak 0 ohne Fortschritt verbraucht keinen Freeze. Ein angefangener Zeitraum nutzt weiter einen. Warum: Der Eigentümer sah Freezes verschwinden, ohne dass ein Streak zu schützen war. Tests: `aZeroStreakSpendsNoFreeze`, Ernährungs-Szenario angepasst.
- **Anpinnen:** Pins gelöschter Challenges füllten das Limit, daher ließen sich Sport- und automatische Challenges nicht anpinnen. Veraltete Pins werden vor dem Anpinnen entfernt (`ChallengePinStore.prune`). Test: `ChallengePinPruneTests`.
- **Vorschläge ablehnen:** Challenge-Vorschläge bekommen „Ablehnen“ wie die Fixkosten-Vorschläge. Speicher: neue Verknüpfungsart `recommendationRejection` in der bestehenden Verknüpfungstabelle, keine Schemaänderung; sie gehört zum Challenge-Backup, alte Backups haben einfach keine. Test: `RecommendationRejectionTests`.

### Rückmeldung des Eigentümers: Trainingspläne und Wochenrotation

- **Kopieren:** Das Kontextmenü eines Plans hat „Kopieren“. Die Kopie bekommt neue IDs für Plan, Übungen und Sätze, Kalenderverknüpfungen und Verlauf bleiben am Original; der Editor öffnet die Kopie. Test: `aCopySharesNoIDsButKeepsTheContent`.
- **Reihenfolge:** Pläne sind nach Namen sortiert (mit Zahlen in natürlicher Reihenfolge) statt nach letzter Änderung. Nur die Anzeige ändert sich, die gespeicherte Datei nicht. Test: `plansSortByNameNumberAware`.
- **Kacheln:** Eine Kachel zeigt alle Übungssymbole, die in ihre Breite passen, und für den Rest ein „+n“, statt immer drei (`OverlapStrip`). Test: `theIconStripShowsAllWhenThereIsRoomAndABadgeOtherwise`.
- **Home und Widget:** Hängen mehrere Pläne an denselben wiederkehrenden Terminen, ist jeder Plan einmal pro Woche fällig. Jeder Termin zeigt jetzt einen Plan, erledigte an ihrem Tag zuerst, dann die offenen, statt aller Pläne an jedem Termin. Auch ein einzelner Tag kennt seine ganze Woche. Das nächste Training im Widget folgt derselben Regel. Test: `threePlansOnThreeWeeklyEventsShowEachPlanOnce`.

### Rückmeldung des Eigentümers: Schritte nach Stunden

- **Tagesansicht:** Das Schrittdiagramm hat einen dritten Zeitraum „Tag“ mit einem Balken je Stunde und der Tagessumme. Pfeile und Wischen blättern zu früheren Tagen. Warum: Der Eigentümer wollte sehen, wann am Tag die Schritte anfielen. Auswirkung: Apple Health wird nur nach den Stundensummen des gezeigten Tages gefragt; gespeichert wird nichts. Tests: `theDayViewFillsAllHoursAndStaysSilentUntilAllowed` (24 Stunden, der 23-Stunden-Tag der Zeitumstellung, still bis zur Freigabe).
