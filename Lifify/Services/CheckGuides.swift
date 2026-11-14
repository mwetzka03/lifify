import Foundation

struct CheckGuide: Equatable {
    var methods: String
    var german: String
    var english: String
}

/// How to read each developer check: which methods it calls, and what the measured line means.
enum CheckGuides {
    static func guide(named name: String) -> CheckGuide? {
        catalog[name]
    }

    private static let catalog: [String: CheckGuide] = [
        "Multiplikator ersetzt die niedrigere Stufe": g(
            "StreakSettings.factor(forStreak:configured:)",
            "Die drei Zahlen sind die Faktoren für Serie 12 mit Stufen bei 5 und 10, für Serie 7 und für Serie 12 ohne Zehnerstufe. Es gilt nur die höchste erreichte Stufe, nicht die Summe der Stufen darunter.",
            "The three numbers are the factors for a streak of 12 with steps at 5 and 10, for a streak of 7, and for a streak of 12 without a step at 10. Only the highest reached step applies, not the sum of the steps below it."
        ),
        "Challenge-Name im Kalender": g(
            "LinkCaption.challenge(_:)",
            "Die Messung ist der Beschriftungstext. Darin muss der Name der Challenge stehen, auf Deutsch oder Englisch.",
            "The reading is the caption. It has to contain the challenge name, in German or in English."
        ),
        "Kalendereintrag in der Challenge": g(
            "LinkCaption.calendar(titles:count:singleDate:)",
            "Die Messung ist die Beschriftung aus Titel und Datum. Beide müssen im Text stehen.",
            "The reading is the caption built from the title and the date. Both have to appear in the text."
        ),
        "Entwicklertag behält die Uhrzeit": g(
            "AppClock.combining(day:time:calendar:), AppClock.combining(stamp:time:calendar:), NotificationTiming.components(for:followsDeviceTimeZone:calendar:)",
            "Die Messung nennt Tag, Monat und Uhrzeit des zusammengelegten Augenblicks, danach die Wanduhr und die feste Zeitzone. Nur das Datum kommt vom Entwicklertag. Stunde, Minute und Sekunde bleiben von der echten Uhr. Eine Uhrzeit ohne Zeitzone folgt dem Gerät, eine gesetzte Zeitzone bleibt der Augenblick.",
            "The reading names the day, month, and clock time of the combined instant, then the wall clock and the fixed time zone. Only the date comes from the developer day. Hour, minute, and second stay from the real clock. A time without a time zone follows the device, and a set time zone stays the instant."
        ),
        "Challenge zieht ihre Kalendereinträge nach": g(
            "WorkoutLinkRules.applyChallenges(_:previous:calendar:)",
            "Die Zahl ist die Anzahl der Termine, nachdem die Challenge neu verknüpft wurde. Es müssen ihre Termine sein, einschließlich der Geschwister, nicht nur ein einzelner Termin.",
            "The number is how many events remain after the challenge is newly linked. They have to be its events, including the siblings, not only a single event."
        ),
        "Kalendereintrag zieht Challenge und Geschwister nach": g(
            "WorkoutLinkRules.applyEvents(_:previous:calendar:)",
            "Die Messung zählt Challenges und Termine im nächsten Stand. Die Challenge und beide Termine derselben Challenge müssen enthalten sein.",
            "The reading counts challenges and events in the next snapshot. The challenge and both events of the same challenge have to be included."
        ),
        "Challenge lösen entfernt nur ihre Termine": g(
            "WorkoutLinkRules.applyChallenges(_:previous:calendar:)",
            "Verglichen werden der Stand, der die fremde Challenge behält, und der Stand ohne Challenge. Übrig bleibt der Termin, der keiner Challenge gehört. Die eigenen Termine sind weg.",
            "The check compares the snapshot that keeps the other challenge with the snapshot that keeps none. The event that belongs to no challenge stays. The owned events are gone."
        ),
        "Einen Termin abwählen löst die Challenge": g(
            "WorkoutLinkRules.applyEvents(_:previous:calendar:)",
            "Die Zahlen sind Challenges und Termine, nachdem die eigenen Termine abgewählt wurden. Die Challenge fällt mit heraus, weil kein eigener Termin mehr gewählt ist.",
            "The numbers are challenges and events after the owned events are cleared. The challenge drops out, because none of its events stays selected."
        ),
        "Manuelle und fremde Termine bleiben draußen": g(
            "WorkoutLinkRules.close(challenges:events:calendar:)",
            "Die Zahl ist die Größe der geschlossenen Terminmenge. Manuelle Termine und Termine einer anderen Challenge dürfen nicht darin liegen.",
            "The number is the size of the closed event set. Manual events and events of another challenge must stay out of it."
        ),
        "Offene Woche zählt beliebige Tage": g(
            "ChallengeService.status(for:endingOn:completions:events:streakState:usesStoredState:)",
            "Serie ist die fortlaufende Serie. Der Bruch ist erledigte Tage gegen die verlangte Quote. Die Quote darf an beliebigen Tagen der offenen Woche erfüllt sein, nicht an einem festen Wochentag.",
            "Streak is the running streak. The fraction is completed days against the required quota. The quota may be met on any days of the open week, not on one fixed weekday."
        ),
        "Mehr Tage als die Woche verlangt zählen mit": g(
            "ChallengeService.status(for:endingOn:completions:events:streakState:usesStoredState:)",
            "Serie und der Bruch erledigt gegen verlangt bleiben über der Quote. Zusätzliche Erledigungen gehen nicht verloren und senken die Serie nicht.",
            "The streak and the done-against-required fraction stay above the quota. Extra completions are not dropped and do not lower the streak."
        ),
        "Freeze hält die angefangene Serie": g(
            "ChallengeService.status(for:endingOn:completions:events:streakState:usesStoredState:)",
            "Die Serie bleibt über 0, obwohl die Woche ohne Erledigung endet. Die Zahl der verbrauchten Freezes steigt um eins.",
            "The streak stays above 0 even though the week ends without a completion. The number of spent freezes rises by one."
        ),
        "Dritte verpasste Woche setzt die Serie auf 0": g(
            "ChallengeService.status(for:endingOn:completions:events:streakState:usesStoredState:)",
            "Die Serie ist 0. Es ist kein Freeze mehr übrig, also setzt die nächste verpasste Woche die Serie zurück. Die Zahl daneben ist die Anzahl der schon verbrauchten Freezes.",
            "The streak is 0. No freeze is left, so the next missed week resets the streak. The number beside it is how many freezes are already spent."
        ),
        "Einmal im Monat, Freeze hält den Folgemonat": g(
            "ChallengeService.status(for:endingOn:completions:events:streakState:usesStoredState:)",
            "Offen ist die Serie im erfüllten Monat. Danach ist die Serie im Folgemonat, und Freezes zählt den verbrauchten Freeze. Der Folgemonat bleibt in der Serie, obwohl er selbst keine Erledigung hat.",
            "Open is the streak in the month that was met. After that is the streak in the following month, and freezes counts the spent freeze. The following month stays in the streak even though it has no completion of its own."
        ),
        "Tägliche Serie zählt jeden Tag": g(
            "ChallengeService.status(for:endingOn:completions:events:streakState:usesStoredState:)",
            "Die Serie entspricht der Zahl der aufeinanderfolgenden erledigten Tage. Der Bruch ist der heutige Stand gegen die tägliche Quote.",
            "The streak matches the number of consecutive completed days. The fraction is today’s progress against the daily quota."
        ),
        "Standardwerte bleiben, bis eine Stufe geändert wird": g(
            "StreakSettings.merging(_:)",
            "Die Zahl ist der Faktor der Fünferstufe nach dem Mischen. Sie trägt den neuen Wert. Die übrigen Standardstufen bleiben unverändert.",
            "The number is the factor of the step at 5 after the merge. It carries the new value. The other default steps stay unchanged."
        ),
        "Standard-Multiplikator skaliert die Basis-Belohnung": g(
            "ChallengeService.status(for:endingOn:completions:events:streakState:usesStoredState:), StreakSettings.factor(forStreak:configured:)",
            "Serie ist die erreichte Länge, Faktor der Standardfaktor dieser Länge, Coins die Basis mal diesen Faktor, gerundet. Ohne eigene Stufen gilt die eingebaute Tabelle.",
            "Streak is the reached length, factor is the default factor for that length, and coins are the base times that factor, rounded. Without custom steps, the built-in table applies."
        ),
        "Freeze-Preis ist ein ganzzahliger Faktor": g(
            "StreakSettings.price(rewardCoins:factor:), StreakSettings.wholeFactor(from:)",
            "Die ersten beiden Zahlen sind die Preise für 10 und für 20 Basis-Coins. Beide sind ganze Coins. Die dritte Zahl ist der Faktor, den der Text ergeben hat.",
            "The first two numbers are the prices for 10 and for 20 base coins. Both are whole coins. The third number is the factor the text produced."
        ),
        "Wiederkehrend bleibt aktiv und wird heute grau": g(
            "ChallengeHistory.staysOnActiveList(recurrence:hasCompletion:), ChallengeHistory.dimsActiveRow(recurrence:completedToday:)",
            "Die Messung sagt, ob die wöchentliche Challenge aktiv bleibt und ob die einmalige nach der Erledigung die aktive Liste verlässt. Wiederkehrend bleibt, einmalig mit Erledigung nicht.",
            "The reading says whether the weekly challenge stays active and whether the one-time challenge leaves the active list after a completion. A repeating one stays, and a one-time one with a completion does not."
        ),
        "Verlauf gruppiert erledigte Challenges nach Tag": g(
            "ChallengeHistory.grouped(completions:calendar:)",
            "Tage ist die Anzahl der Gruppen. Heute ist die Anzahl der Einträge in der heutigen Gruppe. Erledigungen desselben Tages liegen zusammen, ein anderer Tag ist eine eigene Gruppe.",
            "Days is the number of groups. Today is how many entries sit in today’s group. Completions from the same day stay together, and another day is its own group."
        ),
        "Fällig folgt täglich, wöchentlich, monatlich, jährlich und einmalig": g(
            "ChallengeService.isDue(_:on:)",
            "Die Messung zeigt, ob die wöchentliche Challenge an ihrem Wochentag fällig ist. Dieselbe Methode prüft täglich, monatlich, jährlich und einmalig. Nur der passende Tag gilt.",
            "The reading shows whether the weekly challenge is due on its weekday. The same method checks daily, monthly, yearly, and one-time. Only the matching day counts."
        ),
        "Ohne Streak bleibt die Basis-Belohnung": g(
            "ChallengeService.projectedCoins(challenge:on:completions:events:)",
            "Die Zahl ist die ausgezahlten Coins. Ohne Serie sind sie genau die Basis-Belohnung, hier 15.",
            "The number is the coins that would be paid. Without a streak they are exactly the base reward, here 15."
        ),
        "Gleiche Kalendertitel werden zusammengezählt": g(
            "LinkCaption.countedTitles(_:)",
            "Die Messung ist eine Beschriftung. Derselbe Titel steht einmal, mit der Anzahl. Ein anderer Titel steht daneben.",
            "The reading is one caption. The same title appears once, with its count. A different title sits beside it."
        ),
        "Sync umfasst ein Jahr voraus und 30 Tage zurück": g(
            "CalendarSyncWindow.contains(_:around:calendar:), CalendarSyncWindow.pastDays, CalendarSyncWindow.futureDays",
            "Die Messung ist zurück/voraus in Tagen. Zurück sind 30, voraus 365. Das ist das Fenster, in dem der Kalenderabgleich Termine sucht.",
            "The reading is back/ahead in days. Back is 30, and ahead is 365. That is the window in which calendar sync looks for events."
        ),
        "Neue Serientermine behalten die Challenge": g(
            "CalendarSeriesLink.links(externalIdentifier:events:)",
            "Die Messung sagt, ob ein neuer Termin derselben Serie die Challenge der Serie trägt. Sie muss dieselbe sein wie bei den schon verknüpften Terminen.",
            "The reading says whether a new event in the same series carries the series’ challenge. It has to be the same one as on the events that are already linked."
        ),
        "Sync löscht nur verschwundene Termine im Jahresfenster": g(
            "CalendarSyncWindow.removesImportedEvent(start:externalIdentifier:matched:around:calendar:)",
            "Die Messung sagt, dass der alte Termin gespeichert bleibt. Gelöscht wird nur, was im Fenster lag und dort verschwunden ist. Älteres bleibt.",
            "The reading says that the old event stays stored. Sync deletes only what sat inside the window and disappeared there. Older events stay."
        ),
        "Termin im Jahresfenster hängt an Challenge und Training": g(
            "CalendarSyncWindow.contains(_:around:calendar:), WorkoutLinkRules.close(challenges:events:calendar:)",
            "Die Zahl ist die Anzahl der Termine nach dem Schließen. Ein Termin im Fenster darf zugleich an Challenge und Training hängen und bleibt dann erhalten.",
            "The number is how many events remain after closing. An event inside the window may belong to a challenge and a workout at once, and then it stays."
        ),
        "Termin im nächsten Jahr hängt am Training": g(
            "WorkoutLinkRules.close(challenges:events:calendar:)",
            "Die Zahl ist die geschlossene Terminmenge. Ein Termin im nächsten Jahr bleibt drin, solange er im Jahresfenster des Abgleichs liegt.",
            "The number is the closed event set. An event next year stays in it as long as it falls inside the one-year sync window."
        ),
        "Training rastet auf fünf Minuten ein": g(
            "WorkoutCalendarSync.clock(_:), WorkoutCalendarSync.duration(seconds:)",
            "Die Zahl ist die gerundete Uhrzeit als Sekunden seit der Referenz. Sie liegt auf einem Vielfachen von fünf Minuten. Eine Dauer von 0 Sekunden wird 5 Minuten, 450 Sekunden werden 10 Minuten.",
            "The number is the rounded clock time as seconds since the reference date. It sits on a multiple of five minutes. A duration of 0 seconds becomes 5 minutes, and 450 seconds become 10 minutes."
        ),
        "Timer zählt Tage, Stunden, Minuten und Sekunden": g(
            "AbstinenceRules.clock(_:)",
            "Die Messung ist Stunden, Minuten und Sekunden einer Spanne von 3661 Sekunden, also 1:01:01. Eine negative Spanne wird 0. Ein Tag plus diese Spanne trägt die Tage getrennt.",
            "The reading is hours, minutes, and seconds of a span of 3661 seconds, which is 1:01:01. A negative span becomes 0. A day plus that span keeps the days separate."
        ),
        "Schwer zahlt mehr als leicht, ein Faktor bleibt editierbar": g(
            "AbstinenceRules.defaultMultipliers, AbstinenceRules.merging(_:defaults:), AbstinenceRules.bonusCoins(base:multiplier:)",
            "Halb und anderthalb sind die Coins aus Basis 10 mal Faktor 0,5 und 1,5. Schwierigkeit schwer hat in der Standardtabelle einen höheren Faktor als leicht. Ein gesetzter Faktor bleibt der gesetzte Wert.",
            "Half and one-and-a-half are the coins from a base of 10 times the factors 0.5 and 1.5. Hard has a higher factor than easy in the default table. A factor that was set stays the value that was set."
        ),
        "Boni sitzen auf 1, 2, 4, 8, 24 und 72 Stunden, dann 7, 14, 30 Tage und 1 Jahr": g(
            "AbstinenceRules.reached(start:now:calendar:)",
            "Die Messung sagt, ob 72 Stunden erreicht sind. Dieselbe Methode prüft die Stufen davor und danach. Die Abstände bleiben 1, 2, 4, 8, 24 und 72 Stunden, dann 7, 14 und 30 Tage und 1 Jahr.",
            "The reading says whether 72 hours is reached. The same method checks the steps before and after it. The gaps stay 1, 2, 4, 8, 24, and 72 hours, then 7, 14, and 30 days, and 1 year."
        ),
        "Ein Lauf zahlt jeden Tag und jede Stufe einmal, ein Rückfall startet die Boni neu": g(
            "AbstinenceRules.plan(start:now:completedDays:awarded:calendar:), AbstinenceRules.dayStarts(from:through:calendar:)",
            "Tage ist die Zahl der Tageszahlungen im ersten Lauf, Stufen die noch offenen Bonusstufen, neu die Stufen nach dem Rückfall. Ein Lauf zahlt jeden Tag und jede Stufe nur einmal. Nach dem Rückfall sind die Stufen wieder offen.",
            "Days is how many day payments the first run has, steps are the bonus steps still open, and new is the steps after the relapse. One run pays each day and each step only once. After the relapse the steps are open again."
        ),
        "Eine Ausnahme ändert den Timer nicht": g(
            "AbstinenceRules.plan(start:now:completedDays:awarded:calendar:)",
            "Die Zahl ist die Anzahl der Stufen vor und nach der Ausnahme. Start und Stufenzahl bleiben gleich. Eine verknüpfte Belohnung dokumentiert die Ausnahme und setzt den Timer nicht zurück.",
            "The number is how many steps there are before and after the exception. The start and the step count stay the same. A linked reward records the exception and does not reset the timer."
        ),
        "In zwei Stunden passen vier Challenges à 30 Minuten": g(
            "ChallengeTimeRules.fitCount(minutes:slotMinutes:), ChallengeTimeRules.allowsTime(_:)",
            "Die erste Zahl ist, wie viele Challenges von 30 Minuten in 120 Minuten passen. Vier passen, die fünfte nicht. Sport und Abstinenz bekommen keine Dauer, eine Gewohnheit schon.",
            "The first number is how many challenges of 30 minutes fit into 120 minutes. Four fit, and the fifth does not. Sport and abstinence do not take a duration, and a habit does."
        ),
        "Der Termin behält den Slot, bis die echte Dauer steht": g(
            "ChallengeTimeRules.displayedMinutes(planned:linked:completed:)",
            "Gehalten ist die Dauer, solange noch keine echte Zeit eingetragen ist: der Slot bleibt 120 Minuten, auch bei einer einzelnen Challenge. Teil ist 90 Minuten, wenn drei echte Dauern von 20 Minuten und eine offene Schätzung von 30 Minuten zusammenkommen.",
            "Kept is the duration while no actual time has been entered: the slot stays 120 minutes, even for a single challenge. Partial is 90 minutes when three actual durations of 20 minutes meet one open estimate of 30 minutes."
        ),
        "Vorschläge beginnen bei der ältesten Challenge": g(
            "ChallengeTimeRules.offeredSuggestions(candidates:already:)",
            "Die Zahl ist die Anzahl der Vorschläge. Die älteste angebotene Challenge steht zuerst, mit oder ohne Dauer. Eine ausgeschaltete Challenge fehlt.",
            "The number is how many suggestions there are. The oldest offered challenge comes first, with or without a duration. A switched-off challenge is missing."
        ),
        "Das Tagesbriefing nennt Termine, Coins, Belohnung, Gehalt und Ausgaben": g(
            "DailyBriefing.text(events:challenges:rewards:salary:expenses:)",
            "Die Messung ist der Briefingtext. Er nennt die übergebenen Beispiele zu Terminen, Challenges mit Coins, Belohnungen, Gehalt und Ausgaben und bleibt kürzer als 500 Zeichen.",
            "The reading is the briefing text. It names the given examples for events, challenges with coins, rewards, salary, and expenses, and it stays shorter than 500 characters."
        ),
        "Auf der Startseite steht nur der Abstinenz-Bonus von heute": g(
            "AbstinenceRules.currentNotices(_:on:calendar:), AbstinenceCheer.body(challenge:milestone:coins:), AbstinenceCheer.title(for:)",
            "Die Kennungen sind die Mitteilungen, die heute schon erreicht sind: der frühe Bonus und der Bonus der anderen Challenge. Die spätere Stufe desselben Tages fehlt. Daneben steht der Titel der Mitteilung zum ganzen Tag.",
            "The identifiers are the notices already reached today: the early bonus and the other challenge’s bonus. The later step on the same day is missing. Beside them is the title of the whole-day notice."
        ),
        "Offene Challenges bekommen einen Abendstups und die Uhrzeit": g(
            "ChallengeNudgePlan.clocks(from:calendar:), ChallengeNudgePlan.requests(days:now:calendar:)",
            "Die Messung nennt die Uhrzeiten, die übrig bleiben. Um 16:00 sind das der Abendstups um 20:00 und der Termin um 18:30. Ein Termin, der selbst um 20:00 liegt, setzt den Abendstups nicht ein zweites Mal.",
            "The reading names the times that remain. At 16:00 those are the evening nudge at 20:00 and the event at 18:30. An event that is itself at 20:00 does not schedule the evening nudge a second time."
        ),
        "Eine Serie wird nur am letzten Tag gewarnt": g(
            "ChallengeNudgePlan.endsToday(recurrence:on:calendar:), ChallengeNudgePlan.streakWarning(id:title:streak:atRisk:recurrence:on:now:calendar:), BirthdayCheer.nextFire(birth:awardedYear:now:calendar:)",
            "Die Warnung gibt es am Sonntag, dem letzten Tag einer Woche, und nicht am Montag. Der Geburtstagsbonus liegt um 9:00 und nennt 500 Coins. Ist 9:00 schon vorbei, rutscht er ins nächste Jahr.",
            "The warning exists on Sunday, the last day of a week, and not on Monday. The birthday bonus is at 9:00 and names 500 coins. Once 9:00 has passed, it moves to the next year."
        ),
        "Ein Termin darf höchstens eine Woche in der Vergangenheit liegen": g(
            "ChallengeTimeRules.canAssign(start:now:keepingSelection:calendar:)",
            "Acht Tage zurück dürfen nicht neu zugeordnet werden. Sechs Tage zurück und ein Termin in der Zukunft dürfen es. Eine schon gewählte Zuordnung bleibt auch dann, wenn der Termin älter als eine Woche ist.",
            "Eight days back may not be newly assigned. Six days back and an event in the future may. A selection that is already kept stays even when the event is older than a week."
        ),
        "Sport und Abstinenz stehen separat, der Rest in einem Topf": g(
            "ChallengeCategoryStore.make(challenges:customs:)",
            "Die Messung listet die Abschnittskennungen. Sport und Abstinenz haben je einen eigenen Abschnitt. Alle anderen Kategorien teilen sich einen.",
            "The reading lists the section identifiers. Sport and abstinence each have their own section. Every other category shares one."
        ),
        "Das Briefing hat von Montag bis Sonntag eine eigene Uhrzeit": g(
            "BriefingSchedule.clock(weekday:overrides:fallback:), BriefingSchedule.weekdays",
            "Die Messung ist die Montagszeit, 7:30. Sonntag hat keinen eigenen Wert und wird 8:00. Eine Uhrzeit über 23:59 wird auf 23:59 begrenzt. Die Wochentage laufen von Montag bis Sonntag.",
            "The reading is Monday’s time, 7:30. Sunday has no value of its own and becomes 8:00. A clock past 23:59 is capped at 23:59. The weekdays run from Monday through Sunday."
        ),
        "Zwei Shop-Kacheln teilen sich eine Reihe": g(
            "ShopRows.pairs(_:)",
            "Die Zahl ist die Anzahl der Reihen für fünf Kacheln. Die ersten beiden Reihen enthalten je zwei Kacheln, die letzte die übrige Kachel.",
            "The number is how many rows five tiles make. The first two rows contain two tiles each, and the last row contains the leftover tile."
        ),
        "Eine Abstinenz steht unter Abgeschlossen als ein Eintrag": g(
            "ChallengeHistory.abstinenceSpans(_:calendar:)",
            "Die Zahl ist die Anzahl der abgeschlossenen Spannen. Mehrere Tage derselben Abstinenz werden ein Eintrag, nicht ein Eintrag je Tag.",
            "The number is how many finished spans there are. Several days of the same abstinence become one entry, not one entry per day."
        ),
        "Geburtstag zahlt 500 Coins einmal an diesem Tag": g(
            "BirthdayBonus.coins, BirthdayBonus.isDue(birth:on:awardedYear:calendar:), BirthdayBonus.observed(birth:in:calendar:)",
            "Die Messung sagt, ob der 8.11. heute fällig ist. Es sind 500 Coins, und nur einmal in diesem Jahr. Der 29. Februar fällt in einem normalen Jahr auf den 28.",
            "The reading says whether 8 November is due today. It is 500 coins, and only once that year. 29 February falls on the 28th in an ordinary year."
        ),
        "Der Geburtstagsbonus gilt im nächsten Jahr wieder": g(
            "BirthdayBonus.isDue(birth:on:awardedYear:calendar:)",
            "Die Messung sagt, ob der Bonus am 8.11.2027 wieder fällig ist, obwohl das Jahr 2026 schon vergeben wurde. Er gilt im nächsten Jahr wieder.",
            "The reading says whether the bonus is due again on 8 Nov 2027, even though 2026 was already awarded. It applies again the next year."
        ),
        "Manuelle Buchung blendet Depot und Sparplan aus": g(
            "BookingCategory.manualChoices",
            "Die Messung listet die Kategorien der manuellen Buchung. Depotkauf, Depotverkauf und Sparplan fehlen. Die übrigen Namen sind die Texte aus der App.",
            "The reading lists the categories of a manual booking. Portfolio buy, portfolio sale, and savings plan are missing. The other names are the texts from the app."
        ),
        "Buchungsfeld und Betrag nutzen dieselben Kategorien": g(
            "Money.cents(from:), BookingCategory.manualChoices",
            "Die erste Zahl ist 19,99 Euro als Cent, also 1999. Daneben stehen dieselben sieben manuellen Kategorien. Depot und Sparplan sind nicht dabei. 1.250,50 Euro werden 125050 Cent.",
            "The first number is 19.99 euro as cents, which is 1999. Beside it are the same seven manual categories. Portfolio and savings plan are not among them. 1,250.50 euro becomes 125050 cents."
        ),
        "Die Symbolauswahl enthält Hanfblatt und Zigarette": g(
            "SymbolCatalog.choices(), AppSymbol.assetName(in:)",
            "Die Messung listet die Symbolnamen. symbol.hemp-leaf und symbol.cigarette zeigen auf die Vorlagen hemp-leaf und cigarette. Kein Name kommt doppelt vor.",
            "The reading lists the symbol names. symbol.hemp-leaf and symbol.cigarette point at the hemp-leaf and cigarette templates. No name appears twice."
        ),
        "Gesundheit, Einstellungen und Glasflächen zeigen dieselben Titel": g(
            "HealthScreen.sectionTitles(), SettingsDirectory.rows(), AppChrome.glassScreens, AppChrome.version",
            "Vor dem Schrägstrich stehen die Titel, die Gesundheit zeigt. Dahinter steht die Version 0.4.0. Die Einstellungen beginnen mit Nutzereinstellungen. Ohne Schlüssel bleibt der Satz, dass die Erkennung nicht verbunden ist.",
            "Before the slash are the titles Health shows. After it is version 0.4.0. Settings start with User settings. Without a key the sentence still says recognition is not connected."
        ),
        "Hell und Dunkel haben eigene Flächen": g(
            "AppLook.modesDiffer(palette:), AppLook.canvasTop(_:palette:), AppLook.cardFill(_:palette:)",
            "Die beiden Zahlen sind die Helligkeit der oberen Fläche in Hell und in Dunkel. Hell liegt über 0,75, Dunkel unter 0,2. Die Karten sind deckend, die dunkle Karte ist dunkel und die helle Karte ist hell.",
            "The two numbers are the brightness of the top wash in light and in dark. Light is above 0.75, and dark is below 0.2. The cards are opaque, the dark card is dark, and the light card is light."
        ),
        "Testkategorien starten eingeklappt": g(
            "CheckResultList.groups(from:), CheckResultList.startsCollapsed",
            "Jede Gruppe zeigt Titel und bestandene Prüfungen. Die Kategorien stehen alphabetisch. In der Kategorie kommen zuerst die Unit-Prüfungen, danach die Integration, jeweils alphabetisch. Shop zählt 2/3, weil Mango fehlschlägt. Mango steht hinter Zeta, obwohl der Name im Alphabet früher kommt.",
            "Each group shows its title and how many checks passed. The categories are alphabetical. Inside a category the unit checks come first, then integration, each alphabetical. Shop counts 2/3 because Mango fails. Mango is listed after Zeta even though its name comes first in the alphabet."
        ),
        "Die Briefingtage stehen nebeneinander": g(
            "BriefingWeek.abbreviation(_:), BriefingSchedule.delivers(master:weekday:flags:), BriefingSchedule.isSelected(weekday:flags:)",
            "Die Messung ist die Reihe Mo bis So. Ein abgewählter Montag liefert keine Mitteilung. Ein Tag ohne gespeicherten Schalter bleibt an. Der Hauptschalter aus liefert gar nichts.",
            "The reading is the row from Mo through Su. A Monday that is turned off delivers no notification. A day without a stored switch stays on. The master switch off delivers nothing."
        ),
        "Die Version steht unter dem Entwicklermodus": g(
            "GeneralSettingsOrder.sections",
            "Die Messung ist appearance, briefing, developer, version. Die Version steht ganz zuletzt. Name und Körpermaße liegen unter Nutzereinstellungen.",
            "The reading is appearance, briefing, developer, version. The version is last of all. Name and body measures live under User settings."
        ),
        "Weitere Einstellungen starten geschlossen": g(
            "EditorCopy.moreSettings, EditorCopy.moreStartsClosed, ReminderSyncPreference.isEnabled",
            "Die Messung ist die Beschriftung Weitere Einstellungen. Die Gruppe startet zu. Eine neue Challenge sichert sich standardmäßig in Apple Erinnerungen. Ein fehlender Schalter gilt als an und schreibt nichts.",
            "The reading is the More settings label. That group starts closed. A new challenge saves to Apple Reminders by default. A missing switch counts as on and writes nothing."
        ),
        "Konten, Buchungen und Schulden zeigen ihre Namen": g(
            "AccountKind.label, LedgerKind.label, DebtDirection.label",
            "Die Messung listet die Beschriftungen der Kontoarten, Buchungsarten und Schuldenrichtungen. Keine davon ist leer, und sie sind die Texte, die in der App stehen.",
            "The reading lists the labels of the account kinds, booking kinds, and debt directions. None of them is empty, and they are the texts that appear in the app."
        ),
        "Saldo-Anker, Oberspartopf und Depotwert": g(
            "FinanceService.balance(for:entries:holdings:), FinanceService.totalBalance(accounts:entries:holdings:)",
            "Giro 9800 Cent ist der Anker von 10000 Cent minus der Ausgabe von 200 Cent am Tag danach. Die Ausgabe von 500 Cent am Tag davor zählt nicht, weil sie vor dem Anker liegt. Depot 300 Cent sind 2 Stück mal 150 Cent. Die Summe 15100 Cent ist Giro 9800 plus Spartopf 5000 plus Depot 300. Die Spargruppe mit 99999 Cent fehlt absichtlich. 9800 plus 300 allein wären 10100 und wären falsch.",
            "Checking at 9800 cents is the anchor of 10000 cents minus the 200 cent expense on the day after it. The 500 cent expense on the day before does not count, because it is before the anchor. The portfolio at 300 cents is 2 shares times 150 cents. The total of 15100 cents is checking 9800 plus the savings pot 5000 plus the portfolio 300. The savings group of 99999 cents is left out on purpose. 9800 plus 300 alone would be 10100 and would be wrong."
        ),
        "Fälligkeit und Bankarbeitstage": g(
            "CalendarService.isBankingDay(_:), CalendarService.dueDate(year:month:day:rule:), CalendarService.chargeDays(for:)",
            "Erster 2 ist der erste Bankarbeitstag im Januar 2026. Der 1. Januar ist ein Feiertag, der 2. ein Freitag. Letzter 29 ist der letzte Bankarbeitstag im Mai 2026. Der 31. Mai ist ein Sonntag und der 30. ein Samstag, also bleibt Freitag der 29. Der Sprung vom 1. Mai auf den 4. Mai gehört zur Prüfung der Sparplan-Abbuchung, nicht hierher.",
            "First 2 is the first banking day in January 2026. 1 January is a holiday, and the 2nd is a Friday. Last 29 is the last banking day in May 2026. 31 May is a Sunday and the 30th is a Saturday, so Friday the 29th remains. The jump from 1 May to 4 May belongs to the savings-plan charge check, not to this one."
        ),
        "Wiederholungen und Sparplan-Abbuchung": g(
            "CalendarService.nextOccurrences(firstDate:cadence:rule:day:endDate:through:), CalendarService.savingsPlanDates(cadence:from:through:), CalendarService.savingsPlanScheduleText(cadence:)",
            "Monatlich sind es drei Termine am 15. Wöchentlich sind es vier. Mai [4] heißt: die Abbuchung im Mai 2026 landet am 4. Der 1. Mai ist ein Feiertag und der 2. ein Samstag, der nächste Bankarbeitstag ist Montag der 4.",
            "Monthly means three occurrences on the 15th. Weekly means four. May [4] means the May 2026 charge lands on the 4th. 1 May is a holiday and the 2nd is a Saturday, so the next banking day is Monday the 4th."
        ),
        "Restbudget, Anteil und Zeitraum": g(
            "HomeBudgetSnapshot.remaining, VariableBudgetAccounts.share(total:accountID:targets:), CalendarService.periodKey(for:mode:startDay:)",
            "Die Messung ist der Rest als Geldbetrag. Geplant sind 1000 Cent, ausgegeben 2500 Cent, der Rest ist minus 1500 Cent. Ein Anteil von 100 auf drei Konten wird 34, 33 und 33. März bleibt ein Zeitraum, April ein anderer, das Jahr ist 2026.",
            "The reading is the remainder as an amount of money. Planned is 1000 cents, spent is 2500 cents, and the remainder is minus 1500 cents. A share of 100 across three accounts becomes 34, 33, and 33. March stays one period, April another, and the year is 2026."
        ),
        "Übertrag, Einkauf und Ausgabengruppe": g(
            "FinanceService.poolCarry(pool:currentPeriodKey:splits:), FinanceService.shoppingBias(shopping:entries:period:), CalendarService.splitCounts(in:splitKey:pool:)",
            "Übertrag 6000 Cent ist ein Topf von 10000 Cent minus 4000 Cent Ausgabe in der Vorperiode. Eine Ausgabe von 15000 Cent ergibt minus 5000. Ohne Skalierung ist der Übertrag 0. Geplant 199 Cent ist die offene Einkaufsposition. Die Gruppenzeile ändert die Buchung von minus 800 Cent nicht.",
            "Carry of 6000 cents is a pool of 10000 cents minus 4000 cents spent in the previous period. Spending of 15000 cents produces minus 5000. Without scaling, the carry is 0. Planned 199 cents is the open shopping item. The group line does not change the booking of minus 800 cents."
        ),
        "Einstand und Sortierung im Depot": g(
            "HoldingMaintenance.averagePurchaseCents(for:)",
            "Die Zahl ist der durchschnittliche Kaufpreis in Cent. Zwei Stück zu 500 Cent und ein Verkauf von einem Stück lassen ein Stück zu 500 Cent. Die Sortiernamen Wert, Kauf und A–Z und die Einheiten Prozent und Euro sind nicht leer.",
            "The number is the average purchase price in cents. Two shares at 500 cents and a sale of one share leave one share at 500 cents. The sort names value, purchase, and A–Z, and the units percent and euro, are not empty."
        ),
        "Kaufveränderung und Depotkauf": g(
            "holdingPerformance(_:), PortfolioCashFlow.isSecurityPurchase(_:portfolioIDs:), ExternalIncome.countsInHomeBudget(_:accounts:)",
            "Wert 300 Cent ist Menge 2 mal Kurs 150. Kauf 100 Cent ist der gespeicherte Kaufpreis je Stück, nicht der Tageskurs. Die Tagesänderung fehlt, weil kein Vortageskurs gespeichert ist. Ein Transfer aufs Depot zählt als Depotkauf, eine Umbuchung auf ein anderes Konto nicht.",
            "Value 300 cents is quantity 2 times a price of 150. Purchase 100 cents is the stored purchase price per share, not the day’s price. The day change is missing because no previous close is stored. A transfer onto the portfolio counts as a portfolio buy, and a transfer to another account does not."
        ),
        "CSV und CAMT zeigen die Buchung": g(
            "BankImportService.parseCSV(_:), BankImportService.parseCAMT(data:)",
            "CSV 1 ist eine Zeile über minus 1250 Cent mit dem Titel Bäcker. CAMT minus 1999 Cent ist die Zahlung Cafe. Dieselbe CSV-Zeile bekommt denselben Fingerabdruck.",
            "CSV 1 is one row of minus 1250 cents titled Baker. CAMT minus 1999 cents is the Cafe payment. The same CSV row gets the same fingerprint."
        ),
        "Fingerabdruck und Import-Hinweise": g(
            "BankImportService.makeFingerprint(date:amount:title:iban:), BankImportService.parseDocument(data:fileExtension:), BankImportService.parseCSV(_:)",
            "Die Messung ist der Hinweis zum leeren PDF. PDF-Dateien gehören in den separaten Trade-Republic-Import. Eine CSV ohne erkannte Spalten nennt ihren eigenen Hinweis. Dieselbe Buchung ergibt denselben Fingerabdruck aus 64 Zeichen, ein anderer Betrag einen anderen.",
            "The reading is the message for the empty PDF. PDF files belong in the separate Trade Republic import. A CSV without recognized columns names its own message. The same booking produces the same 64-character fingerprint, and a different amount produces another."
        ),
        "Sicherung behält das Konto": g(
            "LififyBackup Codable, BackupScope.exportFilenamePrefix",
            "Die Messung listet die Dateinamen-Kürzel Lifify, Lifify-Finanzen, Lifify-Challenges und Lifify-Training. Das kodierte Konto kommt mit demselben Namen und derselben Kennung wieder heraus.",
            "The reading lists the file-name prefixes Lifify, Lifify-Finanzen, Lifify-Challenges, and Lifify-Training. The encoded account comes back out with the same name and the same identifier."
        ),
        "Löschen und Zurücksetzen sagen, was bleibt": g(
            "DestructiveAction.deleteData, DestructiveAction.resetApp, DestructiveAction.deleteFinance",
            "Die Messung ist der Titel des vollständigen Zurücksetzens. Löschen, Zurücksetzen und Finanzen löschen unterscheiden im Text, welche Daten bleiben und dass die Ersteinrichtung danach wieder kommt.",
            "The reading is the title of the full reset. Delete, reset, and delete finance distinguish in the message which data stays and that initial setup comes back afterwards."
        ),
        "Wallet und Einlösbarkeit": g(
            "ChallengeService.walletBalance(transactions:), ShopCopy.notEnough",
            "Die Zahl ist das Guthaben: 10 plus 5 minus 3 ergibt 12 Coins. Der Preis 25 liegt darüber, also ist die Belohnung nicht einlösbar und der Hinweis nennt die fehlenden Coins.",
            "The number is the balance: 10 plus 5 minus 3 is 12 coins. The price of 25 is above that, so the reward cannot be redeemed and the message names the missing coins."
        ),
        "Der Shop nennt fehlende Coins": g(
            "ChallengeService.walletBalance(transactions:), ShopCopy.notEnough, ShopCopy.oneTime, ShopCopy.repeatable",
            "Guthaben 12 und Preis 25 zeigen, dass die Coins nicht reichen. Der Hinweistext fehlt nicht. Einmalig und mehrmals bleiben zwei verschiedene Arten.",
            "Balance 12 and price 25 show that the coins are not enough. The message is present. One-time and repeatable stay two different kinds."
        ),
        "Trainingssatz, Übungsname und Klingelton": g(
            "WorkoutProgress.metPlan(_:), WorkoutProgress.volume(of:), ExerciseName.formatted(_:)",
            "Die Messung ist der lesbare Übungsname Barbell Squat. Zwei erfüllte Sätze erfüllen den Plan, ein zu kurzer Satz nicht. Das Volumen der erledigten Sätze ist 10 Kilogramm mal 8 Wiederholungen, also 80. Der Klingelton Alarm ist der Ton mit der Kennung 1005.",
            "The reading is the readable exercise name Barbell Squat. Two completed sets meet the plan, and a short set does not. The volume of the completed sets is 10 kilograms times 8 reps, which is 80. The chime Alarm is the tone with identifier 1005."
        ),
        "Die Leiste zeigt fünf Bereiche": g(
            "AppTabs.items()",
            "Die Messung listet die fünf Tabtitel: Home, Finanzen, Challenges, Gesundheit und Einstellungen. Es gibt kein Bucketlist-Tab und kein vision-Symbol.",
            "The reading lists the five tab titles: Home, Finance, Challenges, Health, and Settings. There is no bucket-list tab and no vision symbol."
        ),
        "Tabs, Einrichtung und Weitere Bereiche": g(
            "OnboardingSteps.title, AppTabs.items(), FinanceMoreDirectory.rows",
            "Die Messung listet die drei Links unter Weitere Bereiche. Die Zeilen nutzen die Schrift body, die Überschrift headline, 14 Punkt Abstand und höchstens 8 Punkt zur nächsten Sektion. Finanzen liegt auf derselben Fläche.",
            "The reading lists the three links under More. The rows use the body font, the heading uses headline, 14 points of padding, and at most 8 points before the next section. Finance sits on the same wash."
        ),
        "Entwicklertag und Schalter": g(
            "AppClock.combining(day:time:calendar:), DeveloperCopy.toggle",
            "Die Messung ist die Beschriftung Entwicklermodus. Der Speicherschlüssel ist lifify.developerMode. Der 8.11.2026 behält die Uhrzeit 7:30:15.",
            "The reading is the Developer mode label. The storage key is lifify.developerMode. 8 Nov 2026 keeps the clock time 7:30:15."
        ),
        "Challenges und Gesundheit nutzen ein Kartenraster": g(
            "CardBoard.challengeColumns(), CardBoard.healthSymbol(matching:), HealthScreen.sectionTitles()",
            "Die Messung nennt die Symbole figure.run und fork.knife, die Dauer-Beschriftung und die Kontoblasen. Ein einzelner Plan oder der dritte Plan nimmt die ganze Reihe ein. Die Shop-Kapsel ist 36 Punkt hoch.",
            "The reading names the symbols figure.run and fork.knife, the duration caption, and the account bubbles. One plan, or the third plan, takes the whole row. The shop capsule is 36 points tall."
        ),
        "Die erste und die letzte Zeile runden die Kachel": g(
            "ListCardEdge.edge(index:count:)",
            "Die Messung lautet top, middle, bottom, single. Oben rundet nur den Anfang, die Mitte bleibt eckig, unten rundet das Ende, und eine einzelne Zeile rundet beide Seiten.",
            "The reading says top, middle, bottom, single. The top rounds only the start, the middle stays square, the bottom rounds the end, and a single row rounds both sides."
        ),
        "Die Kalorien folgen Körper und Ziel": g(
            "NutritionPlan.dayTarget(weightKg:heightCm:age:sex:goal:trained:), NutritionPlan.restingCalories(weightKg:heightCm:age:sex:)",
            "Die vier Zahlen sind die Tagesziele in kcal: Frau 30/165/70 beim Fett verlieren, dieselbe Person beim Halten, Mann 25/180/80 beim Muskelaufbau, und dieselbe Frau ohne Geschlechtsangabe beim Halten. Ohne Gewicht gibt es kein Ziel.",
            "The four numbers are the daily targets in kcal: a woman of 30/165/70 losing fat, the same person maintaining, a man of 25/180/80 building muscle, and the same woman with sex unspecified while maintaining. Without a weight there is no target."
        ),
        "Fast Food kostet Coins und ein sauberer Tag zahlt": g(
            "MealScore.coins(eaten:target:kinds:), MealScore.fastFoodPrice, MealScore.buysFastFood(_:)",
            "Die Messung ist 25, 30, 20, 0. 25 ist der Shop-Preis von Fast Food. 30 sind die Coins eines sauberen Tags unter dem Ziel, 20 die Coins eines Fast-Food-Tags unter dem Ziel, und 0 ein Tag darüber.",
            "The reading is 25, 30, 20, 0. 25 is the shop price of fast food. 30 is the coins of a clean day under the target, 20 the coins of a fast-food day under the target, and 0 a day over it."
        ),
        "Höchstens vier Challenges bleiben angepinnt": g(
            "ChallengePinStore.kept(_:adding:limit:), ChallengePinStore.removed(_:_:)",
            "Die Messung ist 4, 3. Vier angepinnte Challenges nehmen keine fünfte auf. Löst man eine, bleiben drei.",
            "The reading is 4, 3. Four pinned challenges do not take a fifth. Unpinning one leaves three."
        ),
        "Eine gekoppelte Sport-Challenge lässt sich nicht abhaken": g(
            "ChallengeCheckoff.allowsHand(category:linkedWorkouts:)",
            "Die Messung lautet sport, other. Sport mit einem verknüpften Training lässt sich nicht von Hand abhaken. Sport ohne Training und Sonstiges mit einem Training lassen sich abhaken.",
            "The reading says sport, other. Sport with one linked workout cannot be checked off by hand. Sport without a workout, and Other with one workout, can."
        ),
        "Schlüssel, Depot und Ernährung folgen derselben Regel": g(
            "MealRecognition.connected(hasKey:), DepotLoad.shouldSpin(ready:opened:), NutritionLedger.challengeMark",
            "Die Messung ist ready, 25, 4. Ein Schlüssel verbindet die Erkennung, ein fehlender nicht. Eine bereite Depotansicht zeigt die Ladekachel nicht wieder. Fast Food kostet 25 Coins, und höchstens vier Challenges bleiben angepinnt.",
            "The reading is ready, 25, 4. A key connects recognition, and a missing one does not. A ready portfolio does not show the loading card again. Fast food costs 25 coins, and at most four challenges stay pinned."
        ),
        "Eine leere Kategorie zeigt keinen Haken": g(
            "ChallengeBoard.showsCategory(unpinned:), ChallengeBoard.showsCheckCircle(allowsHand:)",
            "Die Messung ist 0, weg. Null ungepinnte Challenges verstecken die Kategorie und den Anlegen-Knopf. Eine übrige Challenge zeigt die Kategorie. Ein gesperrter Hakenkreis bleibt weg, ein normaler bleibt da.",
            "The reading is 0, weg. Zero unpinned challenges hide the category and the create button. One remaining challenge shows the category. A locked check circle stays away, and a normal one stays."
        ),
        "Ein Ziel entscheidet die Ernährungs-Coins": g(
            "MealScore.coins(eaten:target:kinds:goal:), MealScore.balance(afterRemoving:from:), ChallengeCheckoff.allowsHand(category:linkedWorkouts:followsNutrition:), NutritionCopy.challengeTitle(for:)",
            "Die Messung ist 0, -20. 0 ist die Zahlung über dem Ziel beim Fett verlieren. -20 ist der Stand, wenn 20 bereits ausgezahlte Coins von einem Stand von 0 wieder abgezogen werden.",
            "The reading is 0, -20. 0 is the payment when lose fat goes over the target. -20 is the balance when 20 coins already paid are taken back from a balance of 0."
        ),
        "Der Kalender öffnet beim heutigen Tag": g(
            "AgendaScroll.todayIndex(in:today:calendar:), ChallengeTimeRules.remaining(slotMinutes:linkedMinutes:), EventGroupName.title(event:day:), EventOffer.enabled(stored:)",
            "Die Messung ist 30, 45. 30 ist die Position des heutigen Tags, darüber liegt die Vergangenheit. 45 ist die übrige Zeit, wenn von 120 Minuten schon 75 Minuten verplant sind.",
            "The reading is 30, 45. 30 is today’s position, with the past above it. 45 is the time left when 75 minutes of a 120-minute slot are already planned."
        ),
        "Eiweiß, Kohlenhydrate und Fett stehen groß": g(
            "NutrientGuide.headlines, NutrientGuide.daily(_:weightKg:sex:goal:calorieTarget:)",
            "Die Messung ist 112, 30. 112 g Eiweiß sind der Tageswert bei 70 kg und Fett verlieren. 30 g sind die Ballaststoffe. Kohlenhydrate und Fett stehen mit Eiweiß in der großen Reihe.",
            "The reading is 112, 30. 112 g of protein is the daily amount at 70 kg while losing fat. 30 g is the fiber. Carbohydrate and fat sit with protein in the large row."
        ),
        "Profil, Galerie und Kaloriendefizit": g(
            "SettingsDirectory.rows(), MealCapture.keepsInLibrary(_:), NutritionCopy.calorieChallenge, ChallengeCreateMenu.labels",
            "Die Messung ist Profil, aus, Kaloriendefizit. Die erste Einstellungszeile heißt Nutzereinstellungen. Eine Aufnahme mit ausgeschaltetem Schalter bleibt aus der Galerie. Die Challenge heißt Kaloriendefizit, und das Plus hat vier Einträge.",
            "The reading is Profil, aus, Kaloriendefizit. The first settings row is named User settings. A new photo with the switch off stays out of the library. The challenge is named Calorie deficit, and the plus menu has four entries."
        ),
        "Ein Trainingstag hebt das Kalorienziel": g(
            "NutritionPlan.trained(on:sessions:calendar:), NutritionPlan.dayTarget(weightKg:heightCm:age:sex:goal:trained:), NutritionPlan.onDay(_:meals:), SettingsDirectory.rows(), DepotLoad.showsBoard(ready:)",
            "Die Messung ist 1698, 600, user. 1698 ist das Ziel mit Training, 600 sind die Kalorien nur von diesem Tag, und user sagt, dass das Profil zuerst steht. 250 kcal kommen nur an einem Tag mit abgeschlossenem Training dazu.",
            "The reading is 1698, 600, user. 1698 is the target with a workout, 600 is the calories from that day only, and user says the profile comes first. 250 kcal are added only on a day with a finished workout."
        ),
        "Vier Stile haben je eine helle und eine dunkle Fläche": g(
            "AppLook.modesDiffer(palette:), AppLook.accent(_:palette:)",
            "Jeder Stil, Grün, Blau, Bordeaux und Violett, hat eine helle Fläche über 0,75 und eine dunkle unter 0,2. Die Karten sind deckend. Blau ist blauer, Bordeaux röter und Violett tiefer als Grün.",
            "Each style, green, blue, bordeaux, and violet, has a light wash above 0.75 and a dark wash below 0.2. The cards are opaque. Blue is bluer, bordeaux is redder, and violet is deeper than green."
        ),
        "Jede Prüfung erklärt ihre Schritte": g(
            "CheckStories.isComplete(_:), CheckGuides.guide(named:)",
            "Die Messung nennt die Prüfungen, denen eine Erklärung fehlt. Sie ist leer, wenn jede andere Prüfung einen Text, die Methoden, eine Lesart der Messung und mindestens zwei Schritte mit einer Swift-Datei hat.",
            "The reading names the checks that lack an explanation. It is empty when every other check has a text, the methods, a reading of the measurement, and at least two steps with a Swift file."
        ),
    ]

    private static func g(_ methods: String, _ german: String, _ english: String) -> CheckGuide {
        CheckGuide(methods: methods, german: german, english: english)
    }
}
