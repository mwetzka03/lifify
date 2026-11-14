import Foundation

struct CheckStep: Equatable {
    var german: String
    var english: String
    var source: String
    var text: String { L(german, english) }
}

struct CheckStory: Equatable {
    var german: String
    var english: String
    var steps: [CheckStep]
    var summary: String { L(german, english) }
}

/// What each developer-test does, step by step, and which file it reads.
enum CheckStories {
    static func stepTitle(_ number: Int) -> String {
        L("Schritt \(number)", "Step \(number)")
    }

    static func sourceLine(_ file: String) -> String {
        L("Gelesen aus \(file)", "Read from \(file)")
    }

    static func expectedLine(_ text: String) -> String {
        L("Erwartet: \(text)", "Expected: \(text)")
    }

    static func actualLine(_ text: String) -> String {
        L("Ergebnis: \(text)", "Actual: \(text)")
    }

    static func filesLine(_ files: [String]) -> String {
        var unique: [String] = []
        for file in files where !unique.contains(file) {
            unique.append(file)
        }
        let list = unique.joined(separator: ", ")
        return L("Wichtige Dateien: \(list)", "Important files: \(list)")
    }

    static func methodsLine(_ name: String) -> String {
        guard let guide = CheckGuides.guide(named: name) else { return "" }
        return L("Methoden: \(guide.methods)", "Methods: \(guide.methods)")
    }

    static func readingGuide(_ name: String) -> String {
        guard let guide = CheckGuides.guide(named: name) else { return "" }
        return L(guide.german, guide.english)
    }

    static func story(named name: String) -> CheckStory {
        catalog[name] ?? CheckStory(german: name, english: name, steps: [])
    }

    static func isComplete(_ name: String) -> Bool {
        guard let story = catalog[name], !story.german.isEmpty, story.steps.count >= 2 else { return false }
        guard let guide = CheckGuides.guide(named: name),
              !guide.methods.isEmpty,
              !guide.german.isEmpty,
              !guide.english.isEmpty
        else { return false }
        return story.steps.allSatisfy { step in
            !step.german.isEmpty && !step.english.isEmpty && step.source.hasSuffix(".swift")
        }
    }

    private static func make(
        _ german: String,
        _ english: String,
        _ steps: (String, String, String)...
    ) -> CheckStory {
        CheckStory(
            german: german,
            english: english,
            steps: steps.map { CheckStep(german: $0.0, english: $0.1, source: $0.2) }
        )
    }

    private static let catalog: [String: CheckStory] = [
        "Multiplikator ersetzt die niedrigere Stufe": make(
            "Bei einer Serie gilt der Faktor der höchsten erreichten Stufe, nicht die Summe der Stufen darunter.",
            "A streak uses the factor of the highest reached step, not the sum of the lower steps.",
            ("Serie 12 mit Stufen bei 5 und 10 ergibt 1,2.", "A streak of 12 with steps at 5 and 10 yields 1.2.", "StreakSettings.swift"),
            ("Serie 7 bleibt bei 1,1, und ohne Zehnerstufe bleibt auch Serie 12 bei 1,1.", "A streak of 7 stays at 1.1, and without a step at 10 a streak of 12 stays at 1.1 too.", "StreakSettings.swift"),
        ),
        "Challenge-Name im Kalender": make(
            "Ein verknüpfter Kalendereintrag nennt den Namen der Challenge.",
            "A linked calendar entry names the challenge.",
            ("Die Beschriftung für die Challenge Gym wird gebaut.", "The caption for the challenge Gym is built.", "LinkCaption.swift"),
            ("Der Text enthält den Namen Gym auf Deutsch oder Englisch.", "The text contains the name Gym in German or English.", "LififyChecks.swift"),
        ),
        "Kalendereintrag in der Challenge": make(
            "Eine Challenge nennt den verknüpften Termin mit Titel und Datum.",
            "A challenge names the linked event with its title and date.",
            ("Für den Termin Gym am 25.10.2026 wird die Beschriftung gebaut.", "The caption is built for the event Gym on 25 Oct 2026.", "LinkCaption.swift"),
            ("Der Text enthält Titel und das numerische Datum.", "The text contains the title and the numeric date.", "LififyChecks.swift"),
        ),
        "Entwicklertag behält die Uhrzeit": make(
            "Der simulierte Tag ersetzt nur das Datum. Stunde, Minute und Sekunde bleiben.",
            "The simulated day replaces only the date. Hour, minute, and second stay.",
            ("Der 2.11.2026 wird mit der Uhrzeit 16:05:09 zusammengelegt.", "2 Nov 2026 is combined with the time 16:05:09.", "AppClock.swift"),
            ("Jahr, Monat und Tag kommen vom gewählten Tag, die Uhrzeit von der echten Uhr.", "Year, month, and day come from the chosen day, and the clock time stays.", "LififyChecks.swift"),
            ("Der 2.11.2026 bleibt in Berlin und in New York derselbe Tag um 16:05:09. Eine Uhrzeit ohne Zeitzone folgt dem Gerät, eine gesetzte Zeitzone bleibt der Augenblick.", "2 Nov 2026 stays the same day at 16:05:09 in Berlin and in New York. A time without a time zone follows the device, and a set time zone stays the instant.", "AppClock.swift"),
        ),
        "Challenge zieht ihre Kalendereinträge nach": make(
            "Wenn eine Challenge neu verknüpft wird, kommen ihre Termine mit.",
            "When a challenge is newly linked, its events come with it.",
            ("Eine Challenge und ihre Kalenderverknüpfung werden angelegt.", "A challenge and its calendar link are created.", "WorkoutLinkRules.swift"),
            ("Nach dem Ziehen enthält der nächste Stand die Termine dieser Challenge.", "After the pull, the next snapshot contains that challenge’s events.", "LififyChecks.swift"),
        ),
        "Kalendereintrag zieht Challenge und Geschwister nach": make(
            "Ein übernommener Termin holt die Challenge und die anderen Termine derselben Challenge.",
            "An adopted event pulls the challenge and the other events of the same challenge.",
            ("Zwei Termine derselben Challenge liegen im Kalender.", "Two events of the same challenge are on the calendar.", "WorkoutLinkRules.swift"),
            ("Der nächste Stand enthält die Challenge und beide Termine.", "The next snapshot contains the challenge and both events.", "LififyChecks.swift"),
        ),
        "Challenge lösen entfernt nur ihre Termine": make(
            "Wird eine Challenge gelöst, verschwinden nur ihre Termine. Fremde Termine bleiben.",
            "Unlinking a challenge removes only its events. Other events stay.",
            ("Eine Challenge hat zwei Termine, ein dritter Termin gehört niemandem.", "One challenge has two events, and a third event belongs to nobody.", "WorkoutLinkRules.swift"),
            ("Nach dem Lösen bleibt der fremde Termin, die eigenen sind weg.", "After unlinking, the unrelated event stays and the owned ones are gone.", "LififyChecks.swift"),
        ),
        "Einen Termin abwählen löst die Challenge": make(
            "Fällt der letzte gewählte Termin weg, fällt auch die Challenge aus der Verknüpfung.",
            "When the last selected event is cleared, the challenge drops out of the link too.",
            ("Eine Challenge hängt an zwei Terminen.", "A challenge is attached to two events.", "WorkoutLinkRules.swift"),
            ("Ohne diese Termine enthält der nächste Stand weder Challenge noch ihre Termine.", "Without those events, the next snapshot has neither the challenge nor its events.", "LififyChecks.swift"),
        ),
        "Manuelle und fremde Termine bleiben draußen": make(
            "Termine ohne Challenge und Termine einer anderen Challenge werden nicht mitgezogen.",
            "Events without a challenge, and events of another challenge, are not pulled in.",
            ("Der Kalender mischt eigene, manuelle und fremde Termine.", "The calendar mixes owned, manual, and unrelated events.", "WorkoutLinkRules.swift"),
            ("Geschlossen bleibt nur, was zur gewählten Challenge gehört.", "The closed set keeps only what belongs to the chosen challenge.", "LififyChecks.swift"),
        ),
        "Offene Woche zählt beliebige Tage": make(
            "Eine Wochenquote zählt beliebige Tage, nicht einen festen Wochentag.",
            "A weekly quota counts any days, not one fixed weekday.",
            ("Eine Challenge verlangt mehrere Erledigungen in der offenen Woche.", "A challenge requires several completions in the open week.", "ChallengeService.swift"),
            ("Die Serie steigt, sobald die Quote irgendwo in der Woche erfüllt ist.", "The streak advances once the quota is met anywhere in the week.", "LififyChecks.swift"),
        ),
        "Mehr Tage als die Woche verlangt zählen mit": make(
            "Zusätzliche Erledigungen über der Wochenquote gehen nicht verloren.",
            "Extra completions above the weekly quota still count.",
            ("In der Woche liegen mehr Erledigungen als die Quote verlangt.", "The week has more completions than the quota requires.", "ChallengeService.swift"),
            ("Serie und erledigte Anzahl bleiben oberhalb der Quote.", "The streak and the done count stay above the quota.", "LififyChecks.swift"),
        ),
        "Freeze hält die angefangene Serie": make(
            "Eine verpasste Woche mit Freeze setzt die Serie nicht auf 0.",
            "A missed week with a freeze does not reset the streak to 0.",
            ("Die Serie ist offen und ein Freeze ist verfügbar.", "The streak is open and a freeze is available.", "ChallengeService.swift"),
            ("Nach der verpassten Woche bleibt die Serie, und ein Freeze ist verbraucht.", "After the missed week the streak remains, and one freeze is spent.", "LififyChecks.swift"),
        ),
        "Dritte verpasste Woche setzt die Serie auf 0": make(
            "Ohne genug Freezes fällt die Serie nach den erlaubten Aussetzern auf 0.",
            "Without enough freezes, the streak falls to 0 after the allowed misses.",
            ("Mehrere Wochen werden ohne Erledigung und ohne restlichen Freeze geprüft.", "Several weeks are checked without a completion and without a freeze left.", "ChallengeService.swift"),
            ("Die Serie steht danach auf 0.", "The streak is then 0.", "LififyChecks.swift"),
        ),
        "Einmal im Monat, Freeze hält den Folgemonat": make(
            "Eine monatliche Quote gilt für den Monat. Ein Freeze hält den Folgemonat.",
            "A monthly quota applies to the month. A freeze holds the following month.",
            ("Der Oktober ist mit einer Erledigung erfüllt.", "October is met with one completion.", "ChallengeService.swift"),
            ("Der Folgemonat bleibt durch den Freeze in der Serie.", "The following month stays in the streak because of the freeze.", "LififyChecks.swift"),
        ),
        "Tägliche Serie zählt jeden Tag": make(
            "Bei täglicher Wiederholung zählt jeder erledigte Tag.",
            "With a daily repeat, every completed day counts.",
            ("Mehrere aufeinanderfolgende Tage sind erledigt.", "Several consecutive days are completed.", "ChallengeService.swift"),
            ("Die Serie entspricht der Zahl der erledigten Tage.", "The streak matches the number of completed days.", "LififyChecks.swift"),
        ),
        "Standardwerte bleiben, bis eine Stufe geändert wird": make(
            "Die eingebauten Stufen bleiben, solange der Nutzer sie nicht ersetzt.",
            "The built-in steps stay until the user replaces them.",
            ("Die Standardstufen werden mit einer geänderten Fünferstufe gemischt.", "The default steps are merged with a changed step at 5.", "StreakSettings.swift"),
            ("Die Fünferstufe trägt den neuen Wert, die übrigen Standards bleiben.", "The step at 5 carries the new value, and the other defaults stay.", "LififyChecks.swift"),
        ),
        "Standard-Multiplikator skaliert die Basis-Belohnung": make(
            "Ohne eigene Stufen skaliert der Standardfaktor die Basis-Coins.",
            "Without custom steps, the default factor scales the base coins.",
            ("Eine Serie erreicht eine Standardstufe.", "A streak reaches a default step.", "ChallengeService.swift"),
            ("Die ausgezahlten Coins sind Basis mal diesen Faktor.", "The paid coins are the base times that factor.", "LififyChecks.swift"),
        ),
        "Freeze-Preis ist ein ganzzahliger Faktor": make(
            "Der Freeze-Preis ist ein ganzer Faktor der Basis, keine Bruchmünze.",
            "The freeze price is a whole factor of the base, not a fractional coin.",
            ("Der Preis wird für 10 und für 20 Coins gerechnet.", "The price is calculated for 10 and for 20 coins.", "StreakSettings.swift"),
            ("Beide Preise sind ganzzahlig und folgen dem Faktor.", "Both prices are whole numbers and follow the factor.", "LififyChecks.swift"),
        ),
        "Wiederkehrend bleibt aktiv und wird heute grau": make(
            "Eine wiederkehrende Challenge bleibt in der aktiven Liste. Eine einmalige mit Erledigung verschwindet.",
            "A repeating challenge stays on the active list. A one-time challenge with a completion leaves it.",
            ("Eine wöchentliche und eine einmalige Challenge werden verglichen.", "A weekly challenge and a one-time challenge are compared.", "ChallengeHistory.swift"),
            ("Die wöchentliche bleibt aktiv, die einmalige nicht.", "The weekly one stays active, and the one-time one does not.", "LififyChecks.swift"),
        ),
        "Verlauf gruppiert erledigte Challenges nach Tag": make(
            "Der Verlauf fasst Erledigungen desselben Tages zusammen.",
            "History groups completions from the same day.",
            ("Mehrere Erledigungen liegen auf heute und auf einem anderen Tag.", "Several completions fall on today and on another day.", "ChallengeHistory.swift"),
            ("Die Tage sind getrennt, und der heutige Tag enthält seine Einträge.", "The days are separate, and today contains its entries.", "LififyChecks.swift"),
        ),
        "Fällig folgt täglich, wöchentlich, monatlich, jährlich und einmalig": make(
            "Fällig sein folgt der Wiederholung und den gewählten Wochentagen.",
            "Being due follows the repeat and the chosen weekdays.",
            ("Dieselbe Challenge wird als täglich, wöchentlich, monatlich, jährlich und einmalig geprüft.", "The same challenge is checked as daily, weekly, monthly, yearly, and one-time.", "ChallengeService.swift"),
            ("Nur der passende Tag gilt als fällig.", "Only the matching day counts as due.", "LififyChecks.swift"),
        ),
        "Ohne Streak bleibt die Basis-Belohnung": make(
            "Ohne Serie werden genau die Basis-Coins gezahlt.",
            "Without a streak, exactly the base coins are paid.",
            ("Die Challenge hat eine Basis-Belohnung und keine Serie.", "The challenge has a base reward and no streak.", "ChallengeService.swift"),
            ("Die errechneten Coins entsprechen der Basis.", "The calculated coins match the base.", "LififyChecks.swift"),
        ),
        "Gleiche Kalendertitel werden zusammengezählt": make(
            "Mehrere Termine mit demselben Titel werden in einer Beschriftung gezählt.",
            "Several events with the same title are counted in one caption.",
            ("Zwei Termine heißen gleich.", "Two events share a title.", "LinkCaption.swift"),
            ("Die Beschriftung nennt den Titel einmal und die Anzahl.", "The caption names the title once and the count.", "LififyChecks.swift"),
        ),
        "Sync umfasst ein Jahr voraus und 30 Tage zurück": make(
            "Der Kalenderabgleich schaut ein Jahr nach vorn und 30 Tage zurück.",
            "Calendar sync looks one year ahead and 30 days back.",
            ("Die Fenstergrenzen werden gelesen.", "The window limits are read.", "CalendarSyncRules.swift"),
            ("Voraus sind 365 Tage, zurück 30.", "Ahead is 365 days, and back is 30.", "LififyChecks.swift"),
        ),
        "Neue Serientermine behalten die Challenge": make(
            "Neue Termine einer Serie behalten die Challenge der Serie.",
            "New events in a series keep the series’ challenge.",
            ("Eine bestehende Serie ist mit einer Challenge verknüpft.", "An existing series is linked to a challenge.", "CalendarSyncRules.swift"),
            ("Ein neuer Serientermin trägt dieselbe Challenge.", "A new series event carries the same challenge.", "LififyChecks.swift"),
        ),
        "Sync löscht nur verschwundene Termine im Jahresfenster": make(
            "Der Abgleich löscht nur Termine, die im Fenster verschwunden sind. Ältere bleiben.",
            "Sync deletes only events that disappeared inside the window. Older ones stay.",
            ("Ein alter Termin liegt außerhalb des Fensters, einer darin ist weg.", "An old event sits outside the window, and one inside it is gone.", "CalendarSyncRules.swift"),
            ("Der alte Termin bleibt gespeichert.", "The old event stays stored.", "LififyChecks.swift"),
        ),
        "Termin im Jahresfenster hängt an Challenge und Training": make(
            "Ein Termin im Fenster kann zugleich an Challenge und Training hängen.",
            "An event inside the window can belong to a challenge and a workout at once.",
            ("Der Termin liegt im Sync-Fenster und ist mit beiden verknüpft.", "The event is inside the sync window and linked to both.", "WorkoutLinkRules.swift"),
            ("Nach dem Schließen ist der Termin noch da.", "After closing, the event is still there.", "LififyChecks.swift"),
        ),
        "Termin im nächsten Jahr hängt am Training": make(
            "Ein Termin im nächsten Jahr bleibt am Training hängen, wenn er im Fenster liegt.",
            "An event next year stays on the workout when it is inside the window.",
            ("Der Termin liegt innerhalb des Jahresfensters.", "The event falls inside the one-year window.", "WorkoutLinkRules.swift"),
            ("Die geschlossene Menge enthält den Termin.", "The closed set contains the event.", "LififyChecks.swift"),
        ),
        "Training rastet auf fünf Minuten ein": make(
            "Die Trainingsuhr rundet auf fünf Minuten.",
            "The workout clock rounds to five minutes.",
            ("Eine Uhrzeit zwischen zwei Fünf-Minuten-Marken wird gerundet.", "A time between two five-minute marks is rounded.", "WorkoutCalendarSync.swift"),
            ("Das Ergebnis liegt auf einem Vielfachen von fünf Minuten.", "The result sits on a multiple of five minutes.", "LififyChecks.swift"),
        ),
        "Timer zählt Tage, Stunden, Minuten und Sekunden": make(
            "Der Abstinenz-Timer zerlegt die verstrichene Zeit in Tage, Stunden, Minuten und Sekunden.",
            "The abstinence timer splits the elapsed time into days, hours, minutes, and seconds.",
            ("Eine Minute und eine längere Spanne werden ab dem Start gerechnet.", "One minute and a longer span are counted from the start.", "AbstinenceRules.swift"),
            ("Stunden, Minuten und Sekunden stimmen mit der Spanne überein.", "Hours, minutes, and seconds match the span.", "LififyChecks.swift"),
        ),
        "Schwer zahlt mehr als leicht, ein Faktor bleibt editierbar": make(
            "Schwierigkeit schwer zahlt einen höheren Bonusfaktor als leicht. Der Faktor lässt sich setzen.",
            "Hard pays a higher bonus factor than easy. The factor can be set.",
            ("Die Standardfaktoren von leicht und schwer werden verglichen.", "The default factors of easy and hard are compared.", "AbstinenceSettings.swift"),
            ("Ein gesetzter Faktor wie 0,5 oder 1,5 bleibt der gesetzte Wert.", "A set factor such as 0.5 or 1.5 stays the value that was set.", "LififyChecks.swift"),
        ),
        "Boni sitzen auf 1, 2, 4, 8, 24 und 72 Stunden, dann 7, 14, 30 Tage und 1 Jahr": make(
            "Die Bonusstufen sitzen auf festen Zeiten, von einer Stunde bis zu einem Jahr.",
            "The bonus steps sit on fixed times, from one hour up to one year.",
            ("Alle Stufen werden in ihrer Reihenfolge gelesen.", "All steps are read in their order.", "AbstinenceRules.swift"),
            ("72 Stunden ist erreicht, und die Abstände bleiben 1, 2, 4, 8, 24, 72 Stunden, dann 7, 14, 30 Tage und 1 Jahr.", "72 hours is reached, and the gaps stay 1, 2, 4, 8, 24, 72 hours, then 7, 14, 30 days, and 1 year.", "LififyChecks.swift"),
        ),
        "Ein Lauf zahlt jeden Tag und jede Stufe einmal, ein Rückfall startet die Boni neu": make(
            "Ein Lauf zahlt jeden Tag und jede Stufe nur einmal. Ein Rückfall beginnt die Stufen von vorn.",
            "One run pays each day and each step only once. A relapse starts the steps over.",
            ("Ein Lauf über mehrere Tage sammelt Tage und Stufen.", "A run across several days collects days and steps.", "AbstinenceService.swift"),
            ("Nach dem Rückfall sind die schon gezahlten Stufen wieder offen.", "After the relapse, the steps already paid are open again.", "LififyChecks.swift"),
        ),
        "Eine Ausnahme ändert den Timer nicht": make(
            "Eine verknüpfte Belohnung dokumentiert eine Ausnahme und setzt den Timer nicht zurück.",
            "A linked reward records an exception and does not reset the timer.",
            ("Vor der Ausnahme sind die erreichten Stufen bekannt.", "The reached steps are known before the exception.", "AbstinenceRules.swift"),
            ("Nach der Ausnahme ist der Start unverändert und die Stufenzahl gleich.", "After the exception the start is unchanged and the step count is the same.", "LififyChecks.swift"),
        ),
        "In zwei Stunden passen vier Challenges à 30 Minuten": make(
            "In einen Termin von zwei Stunden passen vier Challenges mit je 30 Minuten.",
            "A two-hour event fits four challenges of 30 minutes each.",
            ("Das Zeitfenster und die Dauer werden gegeneinander gerechnet.", "The time slot and the duration are compared.", "ChallengeTimeRules.swift"),
            ("Vier passen, eine fünfte nicht mehr.", "Four fit, and a fifth does not.", "LififyChecks.swift"),
        ),
        "Der Termin behält den Slot, bis die echte Dauer steht": make(
            "Ein Termin behält seine geplante Länge, bis eine verknüpfte Challenge abgehakt und die echte Dauer eingetragen ist.",
            "An event keeps its planned length until a linked challenge is checked off and the actual duration is entered.",
            ("Ohne echte Dauer bleibt der Slot bei 120 Minuten.", "Without an actual duration the slot stays at 120 minutes.", "ChallengeTimeRules.swift"),
            ("Drei echte Dauern von 20 Minuten und eine offene Schätzung von 30 Minuten ergeben 90.", "Three actual durations of 20 minutes and one open estimate of 30 minutes make 90.", "LififyChecks.swift"),
        ),
        "Vorschläge beginnen bei der ältesten Challenge": make(
            "Beim Zuweisen stehen die angebotenen Challenges mit der ältesten zuerst, mit oder ohne Dauer.",
            "When assigning, the offered challenges start with the oldest, with or without a duration.",
            ("Eine ausgeschaltete und eine erledigte Challenge werden nicht angeboten.", "A switched-off challenge and a finished one are not offered.", "ChallengeTimeRules.swift"),
            ("Die älteste angebotene Challenge steht vor der neueren.", "The oldest offered challenge comes before the newer one.", "LififyChecks.swift"),
        ),
        "Das Tagesbriefing nennt Termine, Coins, Belohnung, Gehalt und Ausgaben": make(
            "Der Text des Tagesbriefings nennt Termine, Challenges mit Coins, Belohnungen, Gehalt und Ausgaben.",
            "The daily briefing text names events, challenges with coins, rewards, salary, and expenses.",
            ("Jede Gruppe bekommt eine Zeile mit Titel und Detail.", "Each group gets a line with a title and a detail.", "DailyBriefing.swift"),
            ("Der Text enthält die übergebenen Beispiele und bleibt kürzer als 500 Zeichen.", "The text contains the given examples and stays shorter than 500 characters.", "LififyChecks.swift"),
        ),
        "Auf der Startseite steht nur der Abstinenz-Bonus von heute": make(
            "Die Startseite zeigt den zuletzt erreichten Abstinenz-Bonus von heute. Eine spätere Stufe desselben Tages bleibt verborgen.",
            "Home shows the last abstinence bonus already reached today. A later step on the same day stays hidden.",
            ("Mehrere Boni liegen an verschiedenen Tagen, einer davon noch später am selben Tag.", "Several bonuses fall on different days, and one is still later on the same day.", "AbstinenceRules.swift"),
            ("Angezeigt werden der schon erreichte Bonus und der Bonus der anderen Challenge.", "The bonus already reached and the other challenge’s bonus are shown.", "LififyChecks.swift"),
            ("Die Mitteilung zum ganzen Tag nennt Rauchfrei, 24 Stunden und 20 Coins, und ihr Titel ist kein reiner Hinweis.", "The whole-day notification names Rauchfrei, 24 hours, and 20 coins, and its title is not a plain notice.", "DailyBriefing.swift"),
        ),
        "Offene Challenges bekommen einen Abendstups und die Uhrzeit": make(
            "Eine offene Challenge bekommt um 20:00 einen Stups und zusätzlich die Uhrzeit eines verknüpften Termins. 20:00 wird nicht doppelt gesetzt.",
            "An open challenge gets a nudge at 20:00 and also the time of a linked event. 20:00 is not scheduled twice.",
            ("Ein Termin liegt um 18:30, ein anderer um 20:00. Es ist 16:00.", "One event is at 18:30, another at 20:00. It is 16:00.", "ChallengeNudge.swift"),
            ("Es bleiben der Abendstups um 20:00 und die Uhrzeit 18:30.", "The evening nudge at 20:00 and the 18:30 time remain.", "LififyChecks.swift"),
        ),
        "Eine Serie wird nur am letzten Tag gewarnt": make(
            "Die Serienwarnung kommt nur am letzten Tag der offenen Periode. Der Geburtstagsbonus nennt 500 Coins um 9:00.",
            "The streak warning arrives only on the last day of the open period. The birthday bonus names 500 coins at 9:00.",
            ("Sonntag ist der letzte Tag einer Woche, Montag nicht. Ein Geburtstag liegt noch vor 9:00.", "Sunday is the last day of a week, Monday is not. A birthday is still before 9:00.", "ChallengeNudge.swift"),
            ("Die Warnung gibt es nur am Sonntag, und der nächste Bonus liegt um 9:00.", "The warning exists only on Sunday, and the next bonus is at 9:00.", "LififyChecks.swift"),
        ),
        "Die Terminauswahl öffnet beim heutigen Tag": make(
            "Die Terminauswahl öffnet bei heute. Keiner steht an diesem Tag. Ältere Termine liegen darüber, spätere darunter. Ein Termin mit Sport, Abstinenz oder eigener Challenge, und ein Termin ohne freie Zeit, werden nicht angeboten.",
            "The event picker opens on today. None sits on that day. Older events are above it, later ones below. An event tied to sport, abstinence, or its own challenge, and an event with no time left, are not offered.",
            ("Ein älterer Termin, der heutige und ein späterer werden gezählt. Ein belegter Termin wird geprüft.", "One older event, today’s event, and a later one are counted. A taken event is checked.", "ChallengeTimeRules.swift"),
            ("Die Messung ist 1, zu. Keiner sitzt nach dem einen älteren Termin, und der belegte Termin bleibt zu.", "The reading is 1, zu. None sits after the one older event, and the taken event stays closed.", "LififyChecks.swift"),
        ),
        "Ein Termin setzt den Tag der Challenge": make(
            "Eine verknüpfte Challenge übernimmt Tag und Uhrzeit des Termins. Eine weitere Challenge kommt in dieselbe Gruppe. Die Erinnerung bekommt die Uhrzeit nur bei einem Termin mit Uhrzeit.",
            "A linked challenge takes the day and time of the event. Another challenge joins the same group. The reminder gets a time only for an event that has a time.",
            ("Ein wöchentlicher Termin am 18.11. um 19:15 ersetzt einen früheren Tag. Eine dritte Challenge kommt dazu.", "A weekly event on 18 Nov at 19:15 replaces an earlier day. A third challenge is added.", "ChallengeTimeRules.swift"),
            ("Die Messung ist 19:15, 3. Die Uhrzeit ist die des Termins, und die Gruppe hat drei Challenges.", "The reading is 19:15, 3. The time is the event's, and the group has three challenges.", "LififyChecks.swift"),
        ),
        "Einzeln zeigt die Challenges einer Gruppe": make(
            "Der Filter Einzeln zeigt die Challenges aus einer Gruppe einzeln, nicht die Gruppenkarte. Eine nachträglich verknüpfte Challenge gehört zur Gruppe des Termins.",
            "The Single filter shows the challenges from a group one by one, not the group card. A challenge linked afterwards belongs to the event's group.",
            ("Eine Challenge steckt in einer Gruppe, und eine weitere wird mit dem Termin verknüpft.", "One challenge sits in a group, and another is linked to the event.", "ChallengeTimeRules.swift"),
            ("Die Messung ist einzeln, 2. Einzeln blendet die Challenge ein, und die Gruppe hat beide.", "The reading is einzeln, 2. Single includes the challenge, and the group has both.", "LififyFeatureChecks.swift"),
        ),
        "Eine erledigte Challenge bleibt in der Gruppe": make(
            "Eine erledigte Einzel-Challenge bleibt in ihrer Gruppe stehen. Die Gruppe selbst liegt im Abschnitt Gruppen und kommt nur durch Anpinnen nach oben. In den Terminvorschlägen fehlt sie.",
            "A finished one-time challenge stays in its group. The group itself sits in the Groups section and reaches the top only when pinned. It is missing from the event suggestions.",
            ("Eine erledigte Challenge und eine offene werden den Vorschlägen gegeben.", "A finished challenge and an open one are given to the suggestions.", "ChallengeTimeRules.swift"),
            ("Die Messung ist Gruppe, aus. Die erledigte Challenge fehlt, die Gruppe bleibt im eigenen Abschnitt.", "The reading is Gruppe, aus. The finished challenge is missing, and the group stays in its own section.", "LififyFeatureChecks.swift"),
        ),
        "Sport und Abstinenz stehen separat, der Rest in einem Topf": make(
            "Sport und Abstinenz haben eigene Abschnitte. Alle anderen Kategorien teilen sich einen.",
            "Sport and abstinence have their own sections. Every other category shares one.",
            ("Challenges aus Sport, Abstinenz und einer eigenen Kategorie werden gruppiert.", "Challenges from sport, abstinence, and a custom category are grouped.", "ChallengeCategoryStore.swift"),
            ("Die Abschnitte sind Sport, Abstinenz und ein gemeinsamer Topf.", "The sections are sport, abstinence, and one shared group.", "LififyChecks.swift"),
        ),
        "Das Briefing hat von Montag bis Sonntag eine eigene Uhrzeit": make(
            "Jeder Wochentag kann eine eigene Uhrzeit haben. Ein fehlender Tag nimmt die Standardzeit.",
            "Each weekday can have its own time. A missing day uses the fallback time.",
            ("Montag ist auf 7:30 gesetzt, Sonntag hat keinen eigenen Wert.", "Monday is set to 7:30, and Sunday has no value of its own.", "DailyBriefing.swift"),
            ("Montag bleibt 7:30, Sonntag wird 8:00, und eine ungültige Uhr wird auf 23:59 begrenzt.", "Monday stays 7:30, Sunday becomes 8:00, and an invalid clock is capped at 23:59.", "LififyChecks.swift"),
        ),
        "Zwei Shop-Kacheln teilen sich eine Reihe": make(
            "Zwei Shop-Kacheln liegen in derselben Reihe und teilen sich die Breite.",
            "Two shop tiles sit in the same row and share the width.",
            ("Die Kacheln werden in Reihen gepackt.", "The tiles are packed into rows.", "ShopView.swift"),
            ("Eine Reihe enthält beide Kacheln.", "One row contains both tiles.", "LififyChecks.swift"),
        ),
        "Eine Abstinenz steht unter Abgeschlossen als ein Eintrag": make(
            "Eine abgeschlossene Abstinenz erscheint als ein Eintrag, nicht als jeder einzelne Tag.",
            "A finished abstinence appears as one entry, not as every single day.",
            ("Mehrere Tage derselben Abstinenz sind abgeschlossen.", "Several days of the same abstinence are finished.", "ChallengeHistory.swift"),
            ("Die abgeschlossene Liste enthält genau eine Spanne.", "The finished list contains exactly one span.", "LififyChecks.swift"),
        ),
        "Geburtstag zahlt 500 Coins einmal an diesem Tag": make(
            "Am Geburtstag gibt es 500 Coins, und nur einmal in diesem Jahr. Der 29. Februar fällt sonst auf den 28.",
            "A birthday pays 500 coins, and only once that year. 29 February otherwise falls on the 28th.",
            ("Der 8.11. und ein Schaltgeburtstag werden gegen mehrere Tage geprüft.", "8 November and a leap-day birthday are checked against several days.", "BirthdayBonus.swift"),
            ("Nur der passende Tag zahlt, ein schon vergebenes Jahr nicht noch einmal.", "Only the matching day pays, and a year already awarded does not pay again.", "LififyChecks.swift"),
        ),
        "Der Geburtstagsbonus gilt im nächsten Jahr wieder": make(
            "Ist der Bonus in diesem Jahr gezahlt, gilt er im nächsten Jahr wieder.",
            "Once the bonus is paid this year, it applies again next year.",
            ("Der 8.11.2026 ist mit dem Jahr 2026 schon vergeben.", "8 Nov 2026 is already awarded for 2026.", "BirthdayBonus.swift"),
            ("Am 8.11.2027 ist der Bonus wieder fällig.", "On 8 Nov 2027 the bonus is due again.", "LififyChecks.swift"),
        ),
        "Manuelle Buchung blendet Depot und Sparplan aus": make(
            "Depotkauf, Depotverkauf und Sparplan stehen nicht in der manuellen Buchungsauswahl.",
            "Portfolio buy, portfolio sale, and savings plan are not in the manual booking picker.",
            ("Die angebotenen Kategorien werden gelesen.", "The offered categories are read.", "BookingCategory.swift"),
            ("Die drei gesperrten Kategorien fehlen in der Liste und in den Beschriftungen.", "The three locked categories are missing from the list and from the labels.", "LififyFeatureChecks.swift"),
        ),
        "Buchungsfeld und Betrag nutzen dieselben Kategorien": make(
            "Das Buchungsfeld bietet dieselben sieben Kategorien, und Beträge werden als Cent gelesen.",
            "The booking field offers the same seven categories, and amounts are read as cents.",
            ("19,99 wird 1999 Cent und 1.250,50 wird 125050 Cent.", "19.99 becomes 1999 cents and 1,250.50 becomes 125050 cents.", "Formatters.swift"),
            ("Die manuelle Liste hat sieben Einträge und enthält Depot und Sparplan nicht.", "The manual list has seven entries and does not contain portfolio or savings plan.", "BookingCategory.swift"),
        ),
        "Die Symbolauswahl enthält Hanfblatt und Zigarette": make(
            "Die Symbolauswahl enthält das Hanfblatt und die Zigarette als eigene Zeichnungen.",
            "The symbol picker contains the hemp leaf and the cigarette as their own drawings.",
            ("Der Katalog wird gelesen und auf doppelte Namen geprüft.", "The catalog is read and checked for duplicate names.", "SymbolPicker.swift"),
            ("symbol.hemp-leaf und symbol.cigarette zeigen auf die Vorlagen hemp-leaf und cigarette.", "symbol.hemp-leaf and symbol.cigarette point at the hemp-leaf and cigarette templates.", "SymbolPicker.swift"),
        ),
        "Gesundheit, Einstellungen und Glasflächen zeigen dieselben Titel": make(
            "Gesundheit, Einstellungen und die bemalten Flächen zeigen die Titel, die auf dem Bildschirm stehen.",
            "Health, Settings, and the painted screens show the titles that appear on screen.",
            ("Training, Ernährung und die sechs Einstellungszeilen werden gelesen. Nutzereinstellungen steht über Allgemein.", "Training, Nutrition, and the six settings rows are read. User settings sits above General.", "AppChrome.swift"),
            ("Die bemalten Flächen umfassen Home, Challenges, Gesundheit, Einstellungen, Einrichtung und Finanzen. Die Version ist 0.4.0. Ohne Schlüssel bleibt der Text, dass die Erkennung nicht verbunden ist.", "The painted screens include Home, Challenges, Health, Settings, setup, and Finance. The version is 0.4.0. Without a key the text still says recognition is not connected.", "HealthView.swift"),
        ),
        "Hell und Dunkel haben eigene Flächen": make(
            "Heller und dunkler Modus haben verschiedene Hintergrund- und Kartenfarben.",
            "Light and dark mode have different background and card colors.",
            ("Die obere Farbe und die Kartenfüllung werden für beide Modi gelesen.", "The top color and the card fill are read for both modes.", "AppSurface.swift"),
            ("Hell ist deutlich heller als 0,75, dunkel dunkler als 0,2, und die Karten sind deckend.", "Light is clearly brighter than 0.75, dark is darker than 0.2, and the cards are opaque.", "AppSurface.swift"),
        ),
        "Testkategorien starten eingeklappt": make(
            "Die Testliste öffnet mit eingeklappten Kategorien. CheckResultList.groups sortiert die Kategorien alphabetisch nach dem Titel. In einer Kategorie kommen zuerst alle Unit-Prüfungen, danach alle Integrationsprüfungen, und innerhalb jeder Art wieder alphabetisch nach dem Namen.",
            "The test list opens with collapsed categories. CheckResultList.groups sorts the categories alphabetically by title. Inside a category every unit check comes first, then every integration check, and within each kind the names are alphabetical again.",
            ("Ein Beispiel für Shop enthält die Unit-Prüfungen Alpha und Zeta und die fehlgeschlagene Integration Mango. Mango liegt im Alphabet vor Zeta und steht trotzdem dahinter, weil Integration nach Unit kommt.", "A shop sample contains the unit checks Alpha and Zeta and the failed integration Mango. Mango comes before Zeta in the alphabet and is still listed after them, because integration follows unit.", "LififyChecks.swift"),
            ("Die Gruppen starten eingeklappt. Die Reihenfolge der Kategorien ist Konten, Navigation, Shop. Shop zählt 2/3.", "The groups start collapsed. The category order is Accounts, Navigation, Shop. Shop counts 2/3.", "LififyChecks.swift"),
        ),
        "Die Briefingtage stehen nebeneinander": make(
            "Die Wochentage des Briefings stehen in einer Reihe. Ein abgewählter Tag bekommt keine Mitteilung.",
            "The briefing weekdays sit in one row. A day that is turned off gets no notification.",
            ("Die Kürzel werden von Montag bis Sonntag gelesen: Mo, Di, Mi, Do, Fr, Sa, So.", "The abbreviations are read from Monday through Sunday: Mo, Tu, We, Th, Fr, Sa, Su.", "DailyBriefing.swift"),
            ("Montag ist aus und liefert nichts. Ein Tag ohne gespeicherten Schalter bleibt an. Der Hauptschalter aus liefert gar nichts.", "Monday is off and delivers nothing. A day without a stored switch stays on. The master switch off delivers nothing.", "DailyBriefing.swift"),
        ),
        "Die Version steht unter dem Entwicklermodus": make(
            "In Allgemein kommt der Entwicklermodus unten hin, und die Version steht ganz zuletzt. Name und Körpermaße liegen unter Nutzereinstellungen.",
            "In General, developer mode sits near the bottom, and the version is last of all. Name and body measures live under User settings.",
            ("Die Reihenfolge der Abschnitte wird gelesen.", "The section order is read.", "SettingsView.swift"),
            ("Sie lautet Darstellung, Briefing, Entwicklermodus, Version.", "It reads appearance, briefing, developer mode, version.", "SettingsView.swift"),
        ),
        "Weitere Einstellungen starten geschlossen": make(
            "Beim Anlegen bleiben Erinnerung, Termin und Gruppe unter Weitere Einstellungen, und die Gruppe startet zu.",
            "When creating something, reminders, the event, and the group stay under More settings, and that group starts closed.",
            ("Die Beschriftung Weitere Einstellungen und der Startzustand werden gelesen.", "The More settings label and the starting state are read.", "SettingsView.swift"),
            ("Eine neue Challenge sichert sich standardmäßig in Apple Erinnerungen.", "A new challenge saves to Apple Reminders by default.", "ReminderLinkStore.swift"),
        ),
        "Konten, Buchungen und Schulden zeigen ihre Namen": make(
            "Konten, Buchungsarten und Schulden zeigen die Namen, die in der App stehen.",
            "Accounts, booking kinds, and debts show the names that appear in the app.",
            ("Die Beschriftungen der Kontoarten, Buchungsarten und Schuldenrichtungen werden gelesen.", "The labels of account kinds, booking kinds, and debt directions are read.", "DomainEnums.swift"),
            ("Keine Beschriftung ist leer.", "No label is empty.", "LififyCoverageChecks.swift"),
        ),
        "Saldo-Anker, Oberspartopf und Depotwert": make(
            "FinanceService.balance und FinanceService.totalBalance in FinanceService.swift rechnen Konten aus Buchungen. Ein Saldo-Anker ist eine Anpassung: er setzt den Stand, und nur Buchungen danach ändern ihn. Buchungen davor werden ignoriert. Ein Spartopf zählt in die Summe, die Spargruppe selbst nicht, weil totalBalance Konten der Art Oberspartopf überspringt. Das Depot ist keine Buchungssumme, sondern Menge mal aktuellem Kurs in Cent.",
            "FinanceService.balance and FinanceService.totalBalance in FinanceService.swift calculate accounts from bookings. A balance anchor is an adjustment: it sets the balance, and only bookings after it change it. Bookings before it are ignored. A savings pot counts in the total, and the savings group itself does not, because totalBalance skips savings-group accounts. The portfolio is not a sum of bookings. It is quantity times the current price in cents.",
            ("FinanceService.balance für das Giro: Anker 10000 Cent am 2. Januar, die Ausgabe von 500 Cent am 1. Januar liegt davor und zählt nicht, die Ausgabe von 200 Cent am 3. Januar wird abgezogen. 10000 minus 200 ist 9800 Cent. Dieselbe Methode für das Depot: Menge 2 mal Kurs 150 Cent ist 300 Cent.", "FinanceService.balance for checking: an anchor of 10000 cents on 2 January, the 500 cent expense on 1 January is before it and does not count, and the 200 cent expense on 3 January is subtracted. 10000 minus 200 is 9800 cents. The same method for the portfolio: quantity 2 times a price of 150 cents is 300 cents.", "FinanceService.swift"),
            ("FinanceService.totalBalance addiert Giro 9800, den Spartopf-Anker 5000 und das Depot 300. Das sind 15100 Cent. Der Gruppen-Anker von 99999 Cent fehlt absichtlich. 9800 plus 300 allein wären 10100 und wären falsch. Die Messung nennt Giro, Depot und Summe. Der Spartopf steht nicht extra in der Zeile, steckt aber in der Summe.", "FinanceService.totalBalance adds checking 9800, the savings-pot anchor 5000, and the portfolio 300. That is 15100 cents. The group anchor of 99999 cents is left out on purpose. 9800 plus 300 alone would be 10100 and would be wrong. The reading names checking, the portfolio, and the total. The pot is not a separate figure, but it is inside the total.", "LififyCoverageChecks.swift"),
        ),
        "Fälligkeit und Bankarbeitstage": make(
            "CalendarService.isBankingDay, CalendarService.dueDate und CalendarService.chargeDays in CalendarService.swift bestimmen Fälligkeiten. Ein Bankarbeitstag ist kein Samstag, kein Sonntag und kein gesetzlicher Feiertag. Feste Feiertage sind unter anderem der 1. Januar und der 1. Mai. Der 14. Mai 2026 ist Christi Himmelfahrt. Die Prüfung nutzt die Zeitzone des Geräts. Die Testdaten liegen auf Berliner Mittag, damit der Kalendertag stabil bleibt.",
            "CalendarService.isBankingDay, CalendarService.dueDate, and CalendarService.chargeDays in CalendarService.swift decide due dates. A banking day is not a Saturday, not a Sunday, and not a public holiday. Fixed holidays include 1 January and 1 May. 14 May 2026 is Ascension Day. The check uses the device time zone. The test dates sit at noon in Berlin so the calendar day stays stable.",
            ("CalendarService.isBankingDay weist den 1.1.2026 ab, weil Neujahr ein Feiertag ist, und den 1.5.2026, weil der Tag der Arbeit ein Feiertag ist. Der 2.1.2026 ist ein Freitag und ein Bankarbeitstag. Der 14.5.2026 ist ebenfalls keiner. CalendarService.chargeDays liefert für wöchentlich die Tage 2, 9, 16 und 23 und für zweiwöchentlich 2 und 16.", "CalendarService.isBankingDay rejects 1 Jan 2026 because New Year’s Day is a holiday, and 1 May 2026 because Labour Day is a holiday. 2 Jan 2026 is a Friday and a banking day. 14 May 2026 is not a banking day either. CalendarService.chargeDays returns days 2, 9, 16, and 23 for weekly, and 2 and 16 for biweekly.", "CalendarService.swift"),
            ("CalendarService.dueDate mit der Regel erster Bankarbeitstag startet am 1. Januar und geht vorwärts auf den 2. Die Regel letzter Bankarbeitstag startet am 31. Mai 2026. Der 31. ist ein Sonntag, der 30. ein Samstag, also ist der letzte Bankarbeitstag Freitag der 29. Der Sprung vom 1. Mai auf den 4. Mai gehört nicht hierher. Den rechnet CalendarService.savingsPlanDates in der Prüfung Wiederholungen und Sparplan-Abbuchung.", "CalendarService.dueDate with the first-banking-day rule starts on 1 January and walks forward to the 2nd. The last-banking-day rule starts on 31 May 2026. The 31st is a Sunday and the 30th is a Saturday, so the last banking day is Friday the 29th. The jump from 1 May to 4 May does not belong here. CalendarService.savingsPlanDates measures that in the check about repeats and the savings-plan charge.", "LififyCoverageChecks.swift"),
        ),
        "Wiederholungen und Sparplan-Abbuchung": make(
            "CalendarService.nextOccurrences zählt Prognosen nach Rhythmus. CalendarService.savingsPlanDates schiebt eine Abbuchung vom Feiertag und vom Wochenende auf den nächsten Bankarbeitstag. Im Mai 2026 ist der 1. ein Feiertag und der 2. ein Samstag, deshalb landet die monatliche Abbuchung am Montag, dem 4. Mai.",
            "CalendarService.nextOccurrences counts forecasts by cadence. CalendarService.savingsPlanDates moves a charge off a holiday and off the weekend onto the next banking day. In May 2026 the 1st is a holiday and the 2nd is a Saturday, so the monthly charge lands on Monday 4 May.",
            ("CalendarService.nextOccurrences zählt ab dem 15.1.2026 monatlich bis zum 20.3. drei Termine, alle am 15. Wöchentlich ab dem 5.1. sind es vier Termine.", "CalendarService.nextOccurrences counts three monthly occurrences from 15 Jan 2026 through 20 Mar, all on the 15th. Weekly from 5 Jan there are four occurrences.", "CalendarService.swift"),
            ("CalendarService.savingsPlanDates für Mai 2026 liefert nur den 4. Der 2. fehlt, weil er ein Samstag nach dem Feiertag ist. Der Wochenplan-Text nennt 2., 9., 16. und 23.", "CalendarService.savingsPlanDates for May 2026 returns only the 4th. The 2nd is missing because it is a Saturday after the holiday. The weekly schedule text names the 2nd, 9th, 16th, and 23rd.", "LififyCoverageChecks.swift"),
        ),
        "Restbudget, Anteil und Zeitraum": make(
            "Das Restbudget ist geplant minus ausgegeben. Anteile und der Zeitraum bleiben nachvollziehbar.",
            "The remaining budget is planned minus spent. Shares and the period stay traceable.",
            ("Ein Budget mit Ausgabe wird direkt gebaut, ohne Nutzerdaten zu schreiben.", "A budget with spending is built directly, without writing user data.", "HomeBudget.swift"),
            ("Der Rest ist die Differenz, auch wenn er negativ ist.", "The remainder is the difference, even when it is negative.", "LififyCoverageChecks.swift"),
        ),
        "Übertrag, Einkauf und Ausgabengruppe": make(
            "Budgetpools übertragen den Rest. Der Einkaufszettel verschiebt Geplantes. Eine Gruppenzeile ändert die Buchung nicht.",
            "Budget pools carry the remainder. The shopping list shifts what is planned. A group line does not change the booking.",
            ("Übertrag, Einkaufsvorschlag und eine Gruppenzeile werden getrennt gerechnet.", "Carry, a shopping bias, and a group line are calculated separately.", "FinanceService.swift"),
            ("Der Übertrag stimmt vor einer Änderung der Skalierung, und die Buchung bleibt unangetastet.", "The carry is correct before a scale change, and the booking stays untouched.", "LififyCoverageChecks.swift"),
        ),
        "Einstand und Sortierung im Depot": make(
            "Der Einstand ist der Durchschnitt der Käufe. Die Sortierung zeigt ihre Beschriftungen.",
            "Cost basis is the average of the purchases. The sort order shows its labels.",
            ("Käufe werden zu einem Durchschnittspreis gemischt.", "Purchases are mixed into an average price.", "PortfolioActivity.swift"),
            ("Menge und Preis des Schnitts stimmen, und die Sortiernamen sind nicht leer.", "The average quantity and price match, and the sort names are not empty.", "LififyCoverageChecks.swift"),
        ),
        "Kaufveränderung und Depotkauf": make(
            "Die Tagesveränderung liest den Vortageskurs. Ein Depotkauf ist keine Umbuchung.",
            "The day change reads the previous close. A portfolio purchase is not a transfer.",
            ("Ein frisches Wertpapier hat keinen gespeicherten Vortageskurs.", "A fresh holding has no stored previous close.", "PortfolioView.swift"),
            ("Die Tagesänderung fehlt dann, und ein Kauf zählt als Depotkauf.", "The day change is then missing, and a purchase counts as a portfolio buy.", "LififyCoverageChecks.swift"),
        ),
        "CSV und CAMT zeigen die Buchung": make(
            "CSV und CAMT werden zu Buchungen mit Betrag und Text.",
            "CSV and CAMT become bookings with an amount and text.",
            ("Eine CSV-Zeile und eine CAMT-Zahlung werden gelesen.", "One CSV row and one CAMT payment are read.", "BankImportService.swift"),
            ("Anzahl und Betrag entsprechen der Datei.", "The count and the amount match the file.", "LififyCoverageChecks.swift"),
        ),
        "Fingerabdruck und Import-Hinweise": make(
            "Jede importierte Buchung bekommt einen Fingerabdruck. Unlesbare PDFs nennen den Hinweis.",
            "Every imported booking gets a fingerprint. Unreadable PDFs name the message.",
            ("Dieselbe Buchung ergibt denselben Fingerabdruck.", "The same booking produces the same fingerprint.", "BankImportService.swift"),
            ("Ein leeres PDF liefert den Fehlerhinweis statt einer Buchung.", "An empty PDF returns the error message instead of a booking.", "LififyCoverageChecks.swift"),
        ),
        "Sicherung behält das Konto": make(
            "Eine Sicherung schreibt das Konto ins JSON und wieder heraus. Die Dateinamen tragen das Bereichskürzel.",
            "A backup writes the account into JSON and back out. The file names carry the area prefix.",
            ("Ein Konto wird kodiert und wieder dekodiert.", "An account is encoded and decoded again.", "BackupService.swift"),
            ("Name und Art bleiben, und die Exportnamen beginnen mit Lifify.", "Name and kind stay, and the export names start with Lifify.", "LififyCoverageChecks.swift"),
        ),
        "Löschen und Zurücksetzen sagen, was bleibt": make(
            "Löschen und Zurücksetzen erklären in Titel und Text, welche Daten bleiben.",
            "Delete and reset explain in the title and message which data stays.",
            ("Die Texte der beiden destruktiven Aktionen werden gelesen.", "The copy of the two destructive actions is read.", "DataManagementView.swift"),
            ("Zurücksetzen und Löschen unterscheiden, was erhalten bleibt.", "Reset and delete distinguish what is kept.", "LififyCoverageChecks.swift"),
        ),
        "Wallet und Einlösbarkeit": make(
            "Das Wallet rechnet das Guthaben. Eine Belohnung ist nur einlösbar, wenn die Coins reichen.",
            "The wallet calculates the balance. A reward can be redeemed only when the coins are enough.",
            ("Einnahmen und Ausgaben an Coins werden addiert.", "Coin income and spending are added.", "ChallengeService.swift"),
            ("Das Guthaben und die Einlösbarkeit passen zum Preis.", "The balance and whether it can be redeemed match the price.", "LififyCoverageChecks.swift"),
        ),
        "Der Shop nennt fehlende Coins": make(
            "Der Shop sagt, wenn die Coins nicht reichen, und unterscheidet einmalige und wiederholbare Belohnungen.",
            "The shop says when the coins are not enough, and it distinguishes one-time and repeatable rewards.",
            ("Guthaben und Preis werden verglichen.", "Balance and price are compared.", "ShopView.swift"),
            ("Der Hinweis fehlt nicht, und die Art der Belohnung steht daneben.", "The message is present, and the reward kind sits beside it.", "LififyCoverageChecks.swift"),
        ),
        "Trainingssatz, Übungsname und Klingelton": make(
            "Ein Trainingssatz rechnet Volumen. Übungsnamen werden lesbar, und der Klingelton hat einen Namen.",
            "A workout set calculates volume. Exercise names become readable, and the chime has a name.",
            ("Gewicht mal Wiederholungen ergibt das Volumen.", "Weight times reps produces the volume.", "WorkoutProgress.swift"),
            ("Der Übungsname und der Klingelton sind die Texte aus der App.", "The exercise name and the chime are the texts from the app.", "LififyCoverageChecks.swift"),
        ),
        "Die Leiste zeigt fünf Bereiche": make(
            "Die Tableiste zeigt Home, Finanzen, Challenges, Gesundheit und Einstellungen.",
            "The tab bar shows Home, Finance, Challenges, Health, and Settings.",
            ("Die fünf Tabs werden mit Symbol und Titel gelesen.", "The five tabs are read with symbol and title.", "AppChrome.swift"),
            ("Es gibt kein Bucketlist-Tab und kein vision-Symbol.", "There is no bucket-list tab and no vision symbol.", "LififyCoverageChecks.swift"),
        ),
        "Tabs, Einrichtung und Weitere Bereiche": make(
            "Einrichtung, Tabs und Weitere Bereiche zeigen die Texte der Oberfläche. Die Links sind mittelgroß.",
            "Setup, tabs, and More show the on-screen texts. The links are a middle size.",
            ("Die Einrichtungstitel, die fünf Tabs und die drei Links unter Weitere Bereiche werden gelesen.", "The setup titles, the five tabs, and the three More links are read.", "OnboardingView.swift"),
            ("Die Zeilen nutzen die Schrift body, die Überschrift headline, 14 Punkt Abstand und höchstens 8 Punkt zur nächsten Sektion. Finanzen liegt auf derselben Fläche.", "The rows use the body font, the heading uses headline, 14 points of padding, and at most 8 points before the next section. Finance sits on the same wash.", "FinanceRoute.swift"),
        ),
        "Entwicklertag und Schalter": make(
            "Der Entwicklertag behält die Uhrzeit, und der Schalter heißt Entwicklermodus.",
            "The developer day keeps the clock time, and the switch is labeled Developer mode.",
            ("Der 8.11.2026 wird mit 7:30:15 zusammengelegt.", "8 Nov 2026 is combined with 7:30:15.", "AppClock.swift"),
            ("Der Schaltertext ist Entwicklermodus, und der Speicherschlüssel ist lifify.developerMode.", "The switch text is Developer mode, and the storage key is lifify.developerMode.", "SettingsView.swift"),
        ),
        "Challenges und Gesundheit nutzen ein Kartenraster": make(
            "Aktive Challenges stehen zu zweit in einer Reihe und teilen sich die Höhe der höheren Karte. Ein einzelner Plan oder der übrige Plan nimmt die ganze Reihe ein. Gesundheit schaltet Training und Ernährung in einer schmalen Kapsel um.",
            "Active challenges sit two in a row and share the height of the taller card. One plan, or the leftover plan, takes the whole row. Health switches Training and Nutrition in a slim capsule.",
            ("Das Raster liest zwei Spalten. Die Shop-Kapsel ist 36 Punkt hoch, dazwischen von der alten und der hohen Kapsel.", "The grid reads two columns. The shop capsule is 36 points tall, midway between the old one and the tall one.", "AppChrome.swift"),
            ("Training und Ernährung stehen als schmale Umschaltung in einer Kapsel. Darunter lassen sich Abstinenz und Sport anlegen.", "Training and Nutrition sit as a slim switch in a capsule. Abstinence and sport can be created underneath.", "AppChrome.swift"),
        ),
        "Die erste und die letzte Zeile runden die Kachel": make(
            "Prognosen und Buchungen stehen jeweils in einer Kachel. Die oberste Zeile rundet oben, die unterste unten, eine einzelne Zeile rundet beide Seiten.",
            "Forecasts and transactions each sit in one card. The first row rounds the top, the last row rounds the bottom, and a single row rounds both.",
            ("Drei Zeilen werden als oben, Mitte und unten gelesen. Eine einzelne Zeile ist allein.", "Three rows are read as top, middle, and bottom. A single row stands alone.", "AppSurface.swift"),
            ("Oben ist nur oben rund, die Mitte gar nicht, unten nur unten, und die einzelne Zeile an beiden Enden.", "The top rounds only the top, the middle rounds nothing, the bottom rounds only the bottom, and the single row rounds both ends.", "AppSurface.swift"),
        ),
        "Die Kalorien folgen Körper und Ziel": make(
            "Das Tagesziel rechnet aus Größe, Gewicht, Alter und Geschlecht. Fett verlieren liegt darunter, Halten bleibt, Muskeln aufbauen liegt darüber. Ohne Größe oder Gewicht gibt es kein Ziel.",
            "The daily target is calculated from height, weight, age, and sex. Lose fat sits below it, maintain stays, and build muscle sits above. Without height or weight there is no target.",
            ("Eine Frau, 30 Jahre, 165 cm und 70 kg, wird für Fett verlieren, Halten und die offene Angabe gelesen. Ein Mann, 25 Jahre, 180 cm und 80 kg, wird für Muskeln aufbauen gelesen.", "A woman, age 30, 165 cm and 70 kg, is read for lose fat, maintain, and unspecified. A man, age 25, 180 cm and 80 kg, is read for build muscle.", "NutritionPlan.swift"),
            ("Die Messung ist 1448, 1704, 2383 und 1804. Fehlendes Gewicht liefert kein Ziel.", "The reading is 1448, 1704, 2383, and 1804. A missing weight gives no target.", "LififyFeatureChecks.swift"),
        ),
        "Fast Food kostet Coins und ein sauberer Tag zahlt": make(
            "Fast Food löst einen Kauf im Shop aus. Ein Tag aus unverarbeiteten und ausgewogenen Mahlzeiten unter dem Ziel zahlt mehr als ein Fast-Food-Tag unter dem Ziel. Über dem Ziel gibt es keine Coins.",
            "Fast food triggers a shop purchase. A day of whole and balanced meals under the target pays more than a fast-food day under the target. Over the target pays nothing.",
            ("Der Preis und die Punkte der Arten werden gelesen.", "The price and the points of the kinds are read.", "NutritionPlan.swift"),
            ("1000 von 1400 mit unverarbeitet und ausgewogen sind 30, dasselbe mit Fast Food ist 20, und 2000 von 1400 ist 0.", "1000 of 1400 with whole and balanced is 30, the same with fast food is 20, and 2000 of 1400 is 0.", "LififyFeatureChecks.swift"),
        ),
        "Höchstens vier Challenges bleiben angepinnt": make(
            "Eine fünfte Challenge wird nicht angepinnt. Eine von vieren lässt sich lösen.",
            "A fifth challenge is not pinned. One of four can be unpinned.",
            ("Vier Kennungen bleiben vier, wenn eine weitere dazukommt.", "Four identifiers stay four when another is added.", "ChallengePins.swift"),
            ("Drei werden vier, und das Lösen einer von vieren lässt drei übrig.", "Three become four, and unpinning one of four leaves three.", "LififyFeatureChecks.swift"),
        ),
        "Eine gekoppelte Sport-Challenge lässt sich nicht abhaken": make(
            "Eine Sport-Challenge mit einem verknüpften Training lässt sich nicht von Hand abhaken. Ohne Training oder in einer anderen Kategorie geht das weiter.",
            "A sport challenge linked to a workout cannot be checked off by hand. Without a workout, or in another category, it still can.",
            ("Sport mit einem Training, Sport ohne Training und Sonstiges mit einem Training werden gelesen.", "Sport with one workout, sport with none, and Other with one workout are read.", "ChallengePins.swift"),
            ("Nur die gekoppelte Sport-Challenge bleibt gesperrt.", "Only the linked sport challenge stays locked.", "LififyFeatureChecks.swift"),
        ),
        "Schlüssel, Depot und Ernährung folgen derselben Regel": make(
            "Ein gespeicherter Schlüssel verbindet die Erkennung, ein leerer nicht. Das Depot dreht die Ladekachel nicht wieder auf, wenn es schon bereit ist. Fast Food kostet 25, und es bleiben höchstens vier Pins.",
            "A stored key connects recognition, and an empty one does not. Portfolio does not bring the loading card back once it is ready. Fast food costs 25, and at most four pins remain.",
            ("Verbunden wird aus dem Schlüssel gelesen, und die Ladekachel aus dem Bereit-Zustand.", "Connected is read from the key, and the loading card from the ready state.", "MealRecognition.swift"),
            ("Die Messung ist ready, 25, 4. Das Modell ist gemini-2.5-flash, und die Kalorien-Challenge trägt die Markierung nutrition:calories.", "The reading is ready, 25, 4. The model is gemini-2.5-flash, and the calorie challenge carries the mark nutrition:calories.", "NutritionLedger.swift"),
        ),
        "Eine leere Kategorie zeigt keinen Haken": make(
            "Eine Kategorie ohne ungepinnte Challenge verschwindet samt Anlegen-Knopf. Eine Sport-Challenge, die nur das Training zählt, zeigt keinen Hakenkreis.",
            "A category with no unpinned challenge disappears, including its create button. A sport challenge that only counts the workout shows no check circle.",
            ("Null ungepinnte Karten verstecken die Kategorie, eine Karte zeigt sie.", "Zero unpinned cards hide the category, and one card shows it.", "AppChrome.swift"),
            ("Ohne Hand-Abhaken gibt es keinen Kreis, mit Hand-Abhaken bleibt er.", "Without a hand check there is no circle, and with a hand check it stays.", "ChallengesView.swift"),
        ),
        "Ein Ziel entscheidet die Ernährungs-Coins": make(
            "Die Ernährungs-Challenge folgt dem Ziel. Fett verlieren zahlt am oder unter dem Ziel, Muskeln aufbauen erst ab dem Ziel, Halten nur nah am Ziel. Ein Abzug kann den Stand unter null ziehen.",
            "The nutrition challenge follows the goal. Lose fat pays at or under the target, build muscle pays once the target is reached, and maintain pays only near the target. A reversal can take the balance below zero.",
            ("Über dem Ziel bei Fett verlieren und unter dem Ziel beim Muskelaufbau zahlt nichts.", "Over the target while losing fat, and under the target while building muscle, pays nothing.", "NutritionPlan.swift"),
            ("Die Messung ist 0, -20. Die Challenge lässt sich nicht von Hand abhaken.", "The reading is 0, -20. The challenge cannot be checked off by hand.", "LififyFeatureChecks.swift"),
        ),
        "Der Kalender öffnet beim heutigen Tag": make(
            "Der Kalender beginnt beim heutigen Tag. Darüber liegen 30 vergangene Tage, darunter die Zukunft. Ein belegter Termin zeigt die Restzeit, und mehrere Challenges bilden eine Gruppe aus Terminname und Tag.",
            "The calendar starts on today. Thirty past days sit above it, and the future sits below. A filled event shows the time left, and several challenges form a group from the event name and the day.",
            ("Der Index des heutigen Tags ist 30.", "The index of today is 30.", "CalendarSyncRules.swift"),
            ("Die Messung ist 30, 45. 45 ist die Restzeit eines 120-Minuten-Slots nach 75 Minuten.", "The reading is 30, 45. 45 is the time left in a 120-minute slot after 75 minutes.", "LififyFeatureChecks.swift"),
        ),
        "Eiweiß, Kohlenhydrate und Fett stehen groß": make(
            "Die Ernährungskachel zeigt alle Nährstoffe. Eiweiß, Kohlenhydrate und Fett stehen groß, die übrigen kleiner, jeweils mit der Empfehlung für den Tag.",
            "The nutrition card shows every nutrient. Protein, carbohydrate, and fat are large, and the others are smaller, each with the suggested amount for the day.",
            ("Bei 70 kg und Fett verlieren sind 112 g Eiweiß empfohlen.", "At 70 kg while losing fat, 112 g of protein is suggested.", "NutritionPlan.swift"),
            ("Die Messung ist 112, 30. 30 g sind die Ballaststoffe.", "The reading is 112, 30. 30 g is the fiber.", "LififyFeatureChecks.swift"),
        ),
        "Profil, Galerie und Kaloriendefizit": make(
            "Die Einstellungen beginnen mit dem Profil und der Zeile Nutzereinstellungen. Eine Aufnahme kommt nur mit eingeschaltetem Schalter in die Galerie. Die Kalorien-Challenge heißt Kaloriendefizit. Das Plus bietet Abstinenz, Sport, Sonstige und Gruppe.",
            "Settings start with the profile and the line User settings. A new photo reaches the library only when the switch is on. The calorie challenge is named Calorie deficit. The plus menu offers abstinence, sport, other, and a group.",
            ("Die erste Zeile und der Galerie-Schalter werden gelesen. Aus bleibt aus.", "The first row and the library switch are read. Off stays off.", "SettingsView.swift"),
            ("Die Messung ist Profil, aus, Kaloriendefizit. Das Plus nennt vier Einträge.", "The reading is profile, off, calorie deficit. The plus menu names four entries.", "AppChrome.swift"),
        ),
        "Ein Trainingstag hebt das Kalorienziel": make(
            "Ein abgeschlossenes Training an dem Tag hebt das Ziel um 250 kcal. Mahlzeiten eines anderen Tags zählen nicht mit. Nutzer steht in den Einstellungen ganz oben, und das Depot zeigt zuerst die Ladekachel.",
            "A finished workout on that day raises the target by 250 kcal. Meals from another day do not count. User is the first settings row, and Portfolio shows the loading card first.",
            ("Der 8.11.2026 hat ein Training, der 7.11. nicht. Die Mahlzeit vom 8. zählt 600 kcal, die vom 7. bleibt draußen.", "8 Nov 2026 has a workout, and 7 Nov does not. The meal on the 8th counts 600 kcal, and the one on the 7th stays out.", "NutritionPlan.swift"),
            ("Das Ziel steigt von 1448 auf 1698. Die erste Einstellungszeile ist Nutzereinstellungen. Die Depotkachel bleibt zu, bis sie bereit ist.", "The target rises from 1448 to 1698. The first settings row is User settings. The portfolio card stays closed until it is ready.", "SettingsView.swift"),
        ),
        "Vier Stile haben je eine helle und eine dunkle Fläche": make(
            "Grün, Blau, Bordeaux und Violett haben je eine helle und eine dunkle Fläche. Die Akzente bleiben unterscheidbar.",
            "Green, blue, bordeaux, and violet each have a light and a dark surface. The accents stay distinct.",
            ("Jeder Stil prüft Helligkeit von Grund und Karte in Hell und Dunkel.", "Each style checks the brightness of the wash and the card in light and dark.", "AppSurface.swift"),
            ("Blau ist blauer, Bordeaux röter und Violett tiefer als Grün.", "Blue is bluer, bordeaux is redder, and violet is deeper than green.", "LififyFeatureChecks.swift"),
        ),
        "Jede Prüfung erklärt ihre Schritte": make(
            "Jede Prüfung in der Liste nennt die wichtigen Dateien, die Methoden und eine Lesart der Messung. Dazu kommen mindestens zwei Schritte, und jeder Schritt zeigt auf eine Swift-Datei.",
            "Every check in the list names the important files, the methods, and how to read the measurement. It also has at least two steps, and each step points at a Swift file.",
            ("CheckStories.isComplete prüft alle Ergebnisse außer dieser Prüfung selbst. CheckGuides.guide liefert Methoden und die Lesart.", "CheckStories.isComplete checks every result except this check itself. CheckGuides.guide supplies the methods and the reading.", "CheckStories.swift"),
            ("Eine Erklärung ist vollständig, wenn der Text da ist, die Methoden und die Lesart nicht leer sind und mindestens zwei Schritte auf eine Swift-Datei zeigen.", "An explanation is complete when the text is present, the methods and the reading are not empty, and at least two steps point at a Swift file.", "CheckStories.swift"),
        ),
    ]
}
