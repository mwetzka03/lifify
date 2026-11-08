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

    static func story(named name: String) -> CheckStory {
        catalog[name] ?? CheckStory(german: name, english: name, steps: [])
    }

    static func isComplete(_ name: String) -> Bool {
        guard let story = catalog[name], !story.german.isEmpty, story.steps.count >= 2 else { return false }
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
        "Drei erledigte Challenges à 30 Minuten machen den Termin zu 90 Minuten": make(
            "Erledigte Challenges mit Dauer verkürzen oder setzen die Terminlänge auf die erledigte Zeit.",
            "Completed challenges with a duration set the event length to the completed time.",
            ("Drei Challenges zu 30 Minuten sind erledigt.", "Three challenges of 30 minutes are completed.", "ChallengeTimeRules.swift"),
            ("Der Termin wird zu 90 Minuten, ein einzelner bleibt bei seiner eigenen Dauer.", "The event becomes 90 minutes, and a single one stays at its own duration.", "LififyChecks.swift"),
        ),
        "Ältere Challenges werden vorgeschlagen, wenn sie in die Zeit passen": make(
            "Vorschläge sind ältere Challenges, deren Dauer noch in den Termin passt.",
            "Suggestions are older challenges whose duration still fits the event.",
            ("Ein Termin hat noch freie Minuten.", "An event still has free minutes.", "ChallengeTimeRules.swift"),
            ("Nur Challenges, die in die Restzeit passen, werden vorgeschlagen.", "Only challenges that fit the remaining time are suggested.", "LififyChecks.swift"),
        ),
        "Das Tagesbriefing nennt Termine, Coins, Belohnung, Gehalt und Ausgaben": make(
            "Der Text des Tagesbriefings nennt Termine, Challenges mit Coins, Belohnungen, Gehalt und Ausgaben.",
            "The daily briefing text names events, challenges with coins, rewards, salary, and expenses.",
            ("Jede Gruppe bekommt eine Zeile mit Titel und Detail.", "Each group gets a line with a title and a detail.", "DailyBriefing.swift"),
            ("Der Text enthält die übergebenen Beispiele und bleibt kürzer als 500 Zeichen.", "The text contains the given examples and stays shorter than 500 characters.", "LififyChecks.swift"),
        ),
        "Auf der Startseite steht nur der Abstinenz-Bonus von heute": make(
            "Die Startseite zeigt nur den Abstinenz-Bonus, der heute fällig ist.",
            "Home shows only the abstinence bonus that is due today.",
            ("Mehrere Boni liegen an verschiedenen Tagen.", "Several bonuses fall on different days.", "AbstinenceRules.swift"),
            ("Angezeigt wird nur der Bonus des heutigen Tages.", "Only today’s bonus is shown.", "LififyChecks.swift"),
            ("Die Mitteilung zum ganzen Tag nennt Rauchfrei, 24 Stunden und 20 Coins, und ihr Titel ist kein reiner Hinweis.", "The whole-day notification names Rauchfrei, 24 hours, and 20 coins, and its title is not a plain notice.", "DailyBriefing.swift"),
        ),
        "Ein Termin darf höchstens eine Woche in der Vergangenheit liegen": make(
            "Ein Termin lässt sich nur zuordnen, wenn er nicht älter als eine Woche ist.",
            "An event can be assigned only when it is not older than one week.",
            ("Ein Termin von vor acht Tagen und einer von vor sechs Tagen werden geprüft.", "An event from eight days ago and one from six days ago are checked.", "ChallengeTimeRules.swift"),
            ("Nur der Termin innerhalb der Woche darf zugeordnet werden.", "Only the event inside the week may be assigned.", "LififyChecks.swift"),
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
            ("Die drei Gesundheitsabschnitte und die fünf Einstellungszeilen werden gelesen.", "The three health sections and the five settings rows are read.", "AppChrome.swift"),
            ("Die bemalten Flächen umfassen Home, Challenges, Gesundheit, Einstellungen, Einrichtung und Finanzen. Die Version ist 0.4.0.", "The painted screens include Home, Challenges, Health, Settings, setup, and Finance. The version is 0.4.0.", "HealthView.swift"),
        ),
        "Hell und Dunkel haben eigene Flächen": make(
            "Heller und dunkler Modus haben verschiedene Hintergrund- und Kartenfarben.",
            "Light and dark mode have different background and card colors.",
            ("Die obere Farbe und die Kartenfüllung werden für beide Modi gelesen.", "The top color and the card fill are read for both modes.", "AppSurface.swift"),
            ("Hell ist deutlich heller als 0,75, dunkel dunkler als 0,2, und die Karten sind deckend.", "Light is clearly brighter than 0.75, dark is darker than 0.2, and the cards are opaque.", "AppSurface.swift"),
        ),
        "Testkategorien starten eingeklappt": make(
            "Die Testliste öffnet mit eingeklappten Kategorien und zählt bestandene Prüfungen je Kategorie.",
            "The test list opens with collapsed categories and counts passed checks per category.",
            ("Eine Beispielgruppe Shop hat einen Fehlschlag, Konto hat einen Erfolg.", "A sample shop group has one failure, and account has one pass.", "LififyChecks.swift"),
            ("Die Gruppen starten eingeklappt und stehen alphabetisch: Konten, Navigation, Shop. Shop zählt 1/2.", "The groups start collapsed and sit in alphabetical order: Accounts, Navigation, Shop. Shop counts 1/2.", "LififyChecks.swift"),
        ),
        "Die Briefingtage stehen nebeneinander": make(
            "Die Wochentage des Briefings stehen in einer Reihe. Ein abgewählter Tag bekommt keine Mitteilung.",
            "The briefing weekdays sit in one row. A day that is turned off gets no notification.",
            ("Die Kürzel werden von Montag bis Sonntag gelesen: Mo, Di, Mi, Do, Fr, Sa, So.", "The abbreviations are read from Monday through Sunday: Mo, Tu, We, Th, Fr, Sa, Su.", "DailyBriefing.swift"),
            ("Montag ist aus und liefert nichts. Ein Tag ohne gespeicherten Schalter bleibt an. Der Hauptschalter aus liefert gar nichts.", "Monday is off and delivers nothing. A day without a stored switch stays on. The master switch off delivers nothing.", "DailyBriefing.swift"),
        ),
        "Die Version steht unter dem Entwicklermodus": make(
            "In Allgemein kommt der Entwicklermodus unten hin, und die Version steht ganz zuletzt.",
            "In General, developer mode sits near the bottom, and the version is last of all.",
            ("Die Reihenfolge der Abschnitte wird gelesen.", "The section order is read.", "SettingsView.swift"),
            ("Sie lautet Profil, Darstellung, Briefing, Entwicklermodus, Version.", "It reads profile, appearance, briefing, developer mode, version.", "SettingsView.swift"),
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
            "Ein Saldo-Anker setzt den Kontostand. Spartöpfe zählen mit, die Gruppe selbst nicht. Das Depot ist Menge mal Kurs.",
            "A balance anchor sets the account balance. Savings pots count, the group itself does not. The portfolio is quantity times price.",
            ("Giro, Spartopf, Gruppe und Depot werden mit Buchungen und einer Aktie gerechnet.", "Checking, a savings pot, a group, and a portfolio are calculated with bookings and one share.", "FinanceService.swift"),
            ("Giro ist 9800 Cent, Depot 300 Cent, die Summe 15100 Cent.", "Checking is 9800 cents, the portfolio 300 cents, and the total 15100 cents.", "LififyCoverageChecks.swift"),
        ),
        "Fälligkeit und Bankarbeitstage": make(
            "Fälligkeiten kennen Bankarbeitstage. Feiertage und Wochenenden werden übersprungen.",
            "Due dates know banking days. Holidays and weekends are skipped.",
            ("Der 1.1.2026 und der 1.5.2026 werden als Feiertage geprüft.", "1 Jan 2026 and 1 May 2026 are checked as holidays.", "CalendarService.swift"),
            ("Der erste Bankarbeitstag im Januar ist der 2., und der Mai springt vom Feiertag auf den 4.", "The first banking day in January is the 2nd, and May moves from the holiday to the 4th.", "LififyCoverageChecks.swift"),
        ),
        "Wiederholungen und Sparplan-Abbuchung": make(
            "Prognosen wiederholen sich nach Rhythmus. Ein Sparplan am Samstag rutscht auf den nächsten Bankarbeitstag.",
            "Forecasts repeat by cadence. A savings plan on Saturday moves to the next banking day.",
            ("Monatliche und wöchentliche Termine werden gezählt.", "Monthly and weekly occurrences are counted.", "CalendarService.swift"),
            ("Die Mai-Abbuchung am 2., einem Samstag nach dem Feiertag, landet am 4. Mai.", "The May charge on the 2nd, a Saturday after the holiday, lands on 4 May.", "LififyCoverageChecks.swift"),
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
            "Aktive Challenges stehen zu zweit in einer Reihe. Eine einzelne Karte ist breit. Gesundheit schaltet Training, Abstinenz und Ernährung in einer Reihe um.",
            "Active challenges sit two in a row. A single card is wide. Health switches Training, Abstinence, and Nutrition in one row.",
            ("Das Raster liest zwei Spalten für Challenges. Eine einzelne Karte nutzt die volle Breite.", "The grid reads two columns for challenges. A single card uses the full width.", "AppChrome.swift"),
            ("Training, Abstinenz und Ernährung stehen als Schalter in einer Reihe.", "Training, Abstinence, and Nutrition sit as switches in one row.", "HealthView.swift"),
        ),
        "Jede Prüfung erklärt ihre Schritte": make(
            "Jede Prüfung in der Liste hat eine Erklärung und mindestens zwei Schritte mit einer Quelldatei.",
            "Every check in the list has an explanation and at least two steps with a source file.",
            ("Alle Ergebnisse außer dieser Prüfung selbst werden auf eine vollständige Erklärung geprüft.", "Every result except this check itself is checked for a complete explanation.", "CheckStories.swift"),
            ("Eine Erklärung ist vollständig, wenn Text und mindestens zwei Schritte auf eine Swift-Datei zeigen.", "An explanation is complete when the text and at least two steps point at a Swift file.", "CheckStories.swift"),
        ),
    ]
}
