# Changes in 0.3.0

[English](#english) · [Deutsch](#deutsch)

This file is always in English and in German. Compared with `main`. The finance
calculations stay in [FINANZEN.md](../FINANZEN.md). The displayed version is 0.3.0.

## English

### Finance

- A budget pool opens on tap. Swipe edits or deletes it. There is no start day
  and no account. **Scalable** carries the remainder, including a negative one,
  into the next period. The detail assigns existing bookings from that period.
  It does not create a booking. Several bookings can be assigned, and removing
  one drops only that assignment.
- An expense group assigns existing bookings, including several at once. The
  group is only a view. The booking itself stays unchanged.
- An assignment to a pool, group, fixed cost, variable cost, shopping item, or
  a similar forecast is shown on the booking.
- The fixed-cost tile opens the fixed-cost list. Savings plans are one row
  there, with the week, month, and debit day. A tap on that row opens the
  savings plans. The other fixed costs stay in the list.
- A forecast whose date has passed stays under forecasts and still counts as
  open. It is not copied into bookings. It turns gray only when a real booking
  covers it. Savings-plan dates follow the same rule. Earlier automatic
  savings-plan bookings are removed.
- The savings pot in forecasts starts collapsed. Search expands it so the
  matching dates show. The header shows total, booked, and open for the
  selected period. The per-week line is gone there.
- Under savings plans, **Shares** opens a pie chart. A tap shows the name, the
  euro amount, and the percent without rebuilding the chart.
- An expense can receive a refund. A depot buy, a depot sale, and a savings
  plan can no longer be entered by hand as an ordinary booking.
- A transfer forecast on a single account counts there as open income or an
  open expense. Income forecasts follow the selected account.
- In a future period the open amount sits in the main tiles, with open and
  forecast on two lines.
- The finance overview shows a loading indicator while the values are built.

### Challenges and coins

- The form no longer asks for a repeat interval or a streak target. Saving
  stores interval 1 and streak target 0.
- Streaks are a switch per challenge. The quota follows the frequency: linked
  calendar entries in the period, otherwise the recurrence itself (selected
  weekdays, once a month, once a year, or every day). Completions count on any
  day inside that period. Each completion adds one to the streak. If the quota
  is missed when the period ends, the streak falls to 0.
- Every streak challenge starts with two freezes. Another freeze costs a whole
  number times that challenge’s base reward and applies only to it. The factor
  starts at 10 and is edited under Challenges. A comma or a dot is rejected.
  With none left, Home warns before the period ends and links to the shop.
- The steps 5, 10, 15, 20, 25, 50, 100, 200, 250, 500, and 1000 replace one
  another. Only the highest one counts, not the product. Until a step is
  changed, the defaults are 1.1, 1.2, 1.3, 1.4, 1.5, 1.75, 2, 2.25, 2.5, 2.75,
  and 3. Changing one step leaves the others. Deleting challenge data or all
  data restores the table and the freeze factor.
- A recurring challenge completed for today stays on Active, gray, with “Done
  today”. A one-time challenge leaves Active once it has been done on any day.
  Completed is the history of those days, newest first. A tap undoes that day.
  Swipe still edits or deletes the challenge.
- Switches, freezes, multipliers, and the freeze factor live beside the store
  and travel with a challenge backup and a full backup.

### Abstinence

- Abstinence is a challenge category and a section on Health, between Training
  and Nutrition.
- The timer counts from “Abstinent since”, including the clock time. Easy,
  medium, and hard have their own bonus factors. The coins per day are set
  when the challenge is created or edited. Each calendar day pays them once.
  If the start lies in the past, the missing days and the bonuses already
  reached are credited once.
- Bonuses sit at 1, 2, 4, 8, 24, and 72 hours, then at 7, 14, and 30 days, and
  at 1 year. Every reached step pays its own factor times the daily coins. The
  factors are under Settings, Challenges, abstinence bonus.
- A reached bonus appears on Home only when its step falls on the current day.
  If several steps fall on that day, only the latest one is shown. Older steps
  leave on their own, without a checkmark. The same bonus is also sent as a
  push and stays in Notification Center. That includes a developer-time jump
  that awards the bonus now.
- Medium’s default factors are the previous hard table. Hard sits above that,
  for example 6× at 24 hours for medium and 12× for hard.
- A reward can be linked to an abstinence. Redeeming it does not reset the
  timer. The purchase is stored on that abstinence as an exception with its
  date and time.
- A relapse sets the timer to now and stores the date, the time, and how long
  that run lasted. Coins already paid stay. The bonuses can be earned again
  on the new run.
- Difficulty, awarded steps, factors, relapses, exceptions, the reward link,
  and open notices live beside the store and travel with a challenge backup.
  Duration and slot membership do too.

### Time in challenges

- A challenge can, but does not have to, carry a duration in minutes. Sport
  and abstinence are left out.
- An event is a slot. Timed challenges fit only while their minutes stay within
  the slot. Five 30-minute challenges are two and a half hours, so a two-hour
  event holds four.
- One timed challenge makes the event that long. Several, with none finished,
  keep the slot. If four 30-minute challenges are linked and three are
  finished, the event becomes 90 minutes.
- When assigning, the list can be filtered to with time, without time, or all.
  Challenges without a duration do not use the slot.
- An event offered for a challenge is at most one week in the past. The list
  can be searched. The event already chosen stays visible.
- Challenges that have been open for at least seven days and still fit the
  slot are offered as suggestions.

### Notifications

- General has a daily briefing. Monday through Sunday each have their own
  time, 08:00 until changed. It names that day’s events, the due challenges
  and their coins, upcoming rewards, the next salary, and that day’s expenses.
  The app schedules the next seven days whenever it becomes active.
- Abstinence bonuses are pushed as well, as soon as the step is reached. The
  notification stays in Notification Center.

### Categories and lists

- New challenges offer Sport, Abstinence, and Other. More categories can be
  added on the challenge and under Challenges. A custom category can have its
  own heading. Otherwise it stays with the rest.
- On the active list, abstinence and sport each have their own heading.
  Everything else shares one group, unless a category is marked separate.
- Under Completed, an abstinence is one row for the span of its days, not one
  row per day.
- Two shop tiles in a row have the same width and the same height. The shorter
  one grows to match the taller one.
- The developer day returns to the real today when the app launches and when
  the mode is switched on or off.

### Profile

- Setup asks for the name and the date of birth. The same fields are under
  Settings, General. The name is the greeting.
- The birthday pays 500 coins, once in that year. A 29 February birthday is
  paid on 28 February when the year has no 29 February.
- The name, the date of birth, and the year already paid travel with a full
  backup. Resetting the app clears the date and asks again during setup.

### Icon

- The home-screen icon is a Liquid Glass icon. In Clear and Tinted, the plate
  takes the same system tint as the other icons. The green mark stays in the
  normal and the dark appearance.

### Health and calendar

- Starting a workout runs a timer. The duration is shown in the history and in
  the finish dialog.
- Several workouts can share one challenge. No weekday is stored on the
  workout. Finishing a linked workout checks that challenge for the day and
  moves only that calendar occurrence onto the five-minute grid. The rest of
  the series stays. If none of the linked workouts happened, that occurrence
  is removed after the day.
- A calendar entry names its link, for example “Linked to challenge Gym”, or
  the group or reward name. Several challenges in one slot are named together
  on the event. A challenge names its calendar entry in the list, in the
  group, on Home, and in the day view. On a workout, repeated titles collapse
  to “GYM · 12”.
- Apple Calendar is read from 30 days back through 365 days ahead. When the
  app becomes active and access was already allowed, it syncs. The first
  permission still comes from the button under Challenges, Calendar &
  Reminders.
- A new occurrence of a series keeps the challenge, group, and reward of that
  series. Workouts linked to the challenge receive that event. Entries outside
  the window stay. An entry that disappeared is removed only inside the
  window, including its workout link. The sync uses the real date, so a
  simulated day deletes nothing.
- A challenge and the calendar follow each other. A challenge links its
  events. An event links the challenge and that challenge’s other events.
  Removing a challenge drops its events and keeps a manual event that belongs
  to no challenge. Unchecking one event of a challenge drops that challenge
  and its other events.
- The picker shows a circle on every row. A tap fills the circle, and Done
  saves. The list is a normal scroll view, because the system row was
  swallowing the tap.

### Settings, data, and checks

- Settings follow the Apple Settings layout. General has the profile, language,
  appearance, the daily briefing with a time for each weekday, and the version.
  Finance has the accounts and the checking account plus the fee for the
  portfolio. Challenges has calendar sync, custom categories, the freeze
  factor, the streak multipliers, and the abstinence bonuses. Health has the
  rest chime. Data has bank import, Trade Republic import, backup, and the
  delete actions.
- Finance, challenges, and training can be deleted separately. Delete all data
  keeps accounts, language, and appearance. Reset app also removes the accounts
  and starts setup again.
- General has developer mode. When it is on, Current day is the day Home,
  challenges, the calendar, and streaks call today. Finance stays on the real
  date.
- Run tests groups the checks by streak, multiplier, challenge, calendar,
  training, abstinence, and developer mode, and labels each row Unit or
  Integration. The same suite is the Xcode target LififyTests, with one test
  per topic. The checks do not write user data.

## Deutsch

Stand gegenüber `main`. Die Rechenregeln der Finanzen bleiben in
[FINANZEN.md](../FINANZEN.md) beschrieben. Die angezeigte Version ist 0.3.0.

### Finanzen

- Ein Budgetpool öffnet sich mit einem Tipp. Wischen bearbeitet oder löscht ihn.
  Es gibt keinen Starttag und kein Konto. **Skalierbar** überträgt den Rest,
  auch einen negativen, in die nächste Periode. Im Detail werden vorhandene
  Buchungen dieses Zeitraums zugeordnet. Es entsteht keine neue Buchung.
  Mehrere Buchungen können zugeordnet werden, und das Lösen entfernt nur diese
  Zuordnung.
- Eine Ausgabengruppe ordnet vorhandene Buchungen zu, auch mehrere auf einmal.
  Die Gruppe ist nur eine Ansicht. Die Buchung selbst bleibt unverändert.
- Eine Zuordnung zu Pool, Gruppe, Fixkosten, variablen Kosten, Einkauf oder
  einer ähnlichen Prognose steht auf der Buchung.
- Die Kachel Fixkosten öffnet die Fixkostenliste. Sparpläne sind dort eine
  Zeile mit Woche, Monat und Abbuchungstag. Ein Tipp auf diese Zeile öffnet
  die Sparpläne. Die übrigen Fixkosten bleiben in der Liste.
- Eine Prognose, deren Datum vorbei ist, bleibt unter Prognosen und zählt
  weiter als offen. Sie wird nicht in die Buchungen kopiert. Grau wird sie
  erst, wenn eine echte Buchung sie deckt. Sparplan-Termine folgen derselben
  Regel. Frühere automatische Sparplan-Buchungen werden entfernt.
- Der Spartopf in den Prognosen startet eingeklappt. Die Suche klappt ihn auf,
  damit die passenden Termine sichtbar sind. Die Kopfzeile zeigt Gesamt,
  gebucht und offen für den gewählten Zeitraum. Die Zeile pro Woche ist dort weg.
- Unter Sparpläne öffnet **Anteile** ein Tortendiagramm. Ein Tipp zeigt Name,
  Eurobetrag und Prozent, ohne das Diagramm neu aufzubauen.
- Eine Ausgabe kann eine Rückerstattung bekommen. Depotkauf, Depotverkauf und
  Sparplan lassen sich nicht mehr von Hand als gewöhnliche Buchung anlegen.
- Eine Umbuchungsprognose auf einem einzelnen Konto zählt dort als offene
  Einnahme oder Ausgabe. Einnahmeprognosen folgen dem gewählten Konto.
- In einer zukünftigen Periode steckt das Offene in den Hauptkacheln, mit
  Offen und Prognose in zwei Zeilen.
- Die Finanzübersicht zeigt eine Ladeanzeige, während die Werte entstehen.

### Challenges und Coins

- Das Formular fragt nicht mehr nach einem Wiederholungsintervall oder einem
  Streak-Ziel. Gespeichert werden Intervall 1 und Streak-Ziel 0.
- Streaks sind ein Schalter pro Challenge. Die Quote folgt der Frequenz:
  verknüpfte Kalendereinträge in der Periode, sonst die Wiederholung selbst
  (gewählte Wochentage, einmal im Monat, einmal im Jahr oder jeden Tag).
  Erledigungen zählen an beliebigen Tagen dieser Periode. Jede Erledigung
  erhöht die Serie um eins. Fehlt die Quote am Ende der Periode, fällt die
  Serie auf 0.
- Jede Streak-Challenge startet mit zwei Freezes. Ein weiterer Freeze kostet
  einen ganzzahligen Faktor mal die Basis-Belohnung und gilt nur für diese
  Challenge. Der Faktor beginnt bei 10 und steht unter Herausforderung.
  Komma und Punkt werden abgelehnt. Ist keiner mehr übrig, warnt die Startseite
  vor dem Periodenende und verlinkt den Shop.
- Die Stufen 5, 10, 15, 20, 25, 50, 100, 200, 250, 500 und 1000 ersetzen sich.
  Es zählt nur die höchste, nicht das Produkt. Bis eine Stufe geändert wird,
  gelten 1,1 / 1,2 / 1,3 / 1,4 / 1,5 / 1,75 / 2 / 2,25 / 2,5 / 2,75 / 3.
  Eine Änderung lässt die übrigen Stufen stehen. Challenge-Daten oder alle
  Daten löschen setzt die Tabelle und den Freeze-Faktor zurück.
- Eine wiederkehrende Challenge, die heute erledigt ist, bleibt unter Aktiv,
  grau, mit „Heute erledigt“. Eine einmalige Challenge verlässt Aktiv, sobald
  sie an irgendeinem Tag erledigt wurde. Abgeschlossen ist die Historie dieser
  Tage, neueste zuerst. Ein Tipp macht den Tag rückgängig. Wischen bearbeitet
  oder löscht die Challenge.
- Schalter, Freezes, Multiplikatoren und der Freeze-Faktor liegen neben dem
  Datenmodell und reisen mit der Challenge- und der Vollsicherung.

### Abstinenz

- Abstinenz ist eine Challenge-Kategorie und ein Abschnitt auf der
  Gesundheitsseite, zwischen Training und Ernährung.
- Der Timer zählt ab „Abstinent seit“, inklusive Uhrzeit. Leicht, mittel und
  schwer haben eigene Bonus-Faktoren. Die Coins pro Tag werden beim Anlegen
  oder Bearbeiten gesetzt. Jeder Kalendertag zahlt sie einmal. Liegt der Start
  in der Vergangenheit, werden die fehlenden Tage und die schon erreichten
  Boni einmal gutgeschrieben.
- Die Boni sitzen auf 1, 2, 4, 8, 24 und 72 Stunden, danach auf 7, 14 und
  30 Tagen und auf 1 Jahr. Jede erreichte Stufe zahlt ihren eigenen Faktor mal
  die Tagescoins. Die Faktoren stehen unter Einstellungen, Herausforderung,
  Abstinenz-Bonus.
- Ein erreichter Bonus erscheint auf der Startseite nur, wenn seine Stufe auf
  den aktuellen Tag fällt. Liegen mehrere Stufen an dem Tag, steht nur die
  letzte dort. Ältere Stufen verschwinden von allein, ohne Abhaken. Derselbe
  Bonus kommt als Push und bleibt in der Mitteilungszentrale. Das gilt auch,
  wenn der Entwicklermodus die Zeit vorspult und der Bonus dadurch jetzt
  gutgeschrieben wird.
- Die Standardfaktoren für mittel sind die früheren Werte von schwer. Schwer
  liegt darüber, zum Beispiel 6× nach 24 Stunden bei mittel und 12× bei schwer.
- Eine Belohnung kann mit einer Abstinenz verknüpft werden. Wird sie eingelöst,
  bleibt der Timer stehen. Der Kauf steht unter der Abstinenz als Ausnahme mit
  Datum und Uhrzeit.
- Ein Rückfall setzt den Timer auf jetzt und speichert Datum, Uhrzeit und die
  Dauer des beendeten Laufs. Schon gezahlte Coins bleiben. Die Boni können im
  neuen Lauf wieder erreicht werden.
- Schwierigkeit, gezahlte Stufen, Faktoren, Rückfälle, Ausnahmen, die
  Belohnungsverknüpfung und offene Meldungen liegen neben dem Datenmodell und
  reisen mit der Challenge-Sicherung. Dauer und Slot-Zuordnung ebenso.

### Zeit in Challenges

- Eine Challenge kann, muss aber nicht, eine Dauer in Minuten haben. Sport und
  Abstinenz sind davon ausgenommen.
- Ein Termin ist ein Slot. Challenges mit Dauer passen nur hinein, solange die
  Summe die Slot-Länge nicht übersteigt. Fünf Challenges à 30 Minuten sind
  zweieinhalb Stunden. In einen Termin von zwei Stunden passen vier.
- Ist genau eine Challenge mit Dauer verknüpft, ist der Termin so lang wie
  diese Challenge. Sind mehrere verknüpft und noch keine erledigt, bleibt der
  Slot. Sind zum Beispiel vier à 30 Minuten verknüpft und drei erledigt, wird
  der Termin auf 90 Minuten gestellt.
- Beim Zuweisen lässt sich filtern: mit Zeit, ohne Zeit oder alle. Challenges
  ohne Dauer verbrauchen den Slot nicht.
- Der Termin einer Challenge darf höchstens eine Woche zurückliegen. Die Liste
  hat ein Suchfeld. Der schon gewählte Termin bleibt sichtbar.
- Challenges, die seit mindestens sieben Tagen offen sind und noch in den Slot
  passen, werden als Vorschlag angeboten.

### Mitteilungen

- Unter Allgemein gibt es das tägliche Briefing. Montag bis Sonntag haben
  jeweils eine eigene Uhrzeit, der Standard ist 08:00. Es nennt die Termine
  des Tags, die fälligen Challenges und ihre Coins, nahende Belohnungen, das
  nächste Gehalt und die Ausgaben dieses Tags. Die App plant die nächsten
  sieben Tage, jedes Mal wenn sie aktiv wird.
- Abstinenz-Boni werden zusätzlich gepusht, sobald die Stufe erreicht ist.
  Die Mitteilung bleibt in der Mitteilungszentrale.

### Kategorien und Listen

- Neue Challenges bieten Sport, Abstinenz und Sonstiges an. Weitere Kategorien
  lassen sich an der Challenge und unter Herausforderung anlegen. Eine eigene
  Kategorie kann separat eine Überschrift bekommen. Sonst liegt sie bei den
  übrigen.
- In der aktiven Liste haben Abstinenz und Sport eine eigene Zwischenüberschrift.
  Alles andere steht in einem Topf, außer eine Kategorie ist separat markiert.
- Unter Abgeschlossen steht eine Abstinenz einmal, mit der Spanne ihrer Tage,
  und nicht an jedem Tag einzeln.
- Zwei Shop-Kacheln in einer Reihe sind gleich breit und gleich hoch. Die
  kleinere wächst auf die größere.
- Der Entwicklertag springt beim Start der App und beim Ein- oder Ausschalten
  des Modus auf den echten heutigen Tag zurück.

### Profil

- Die Ersteinrichtung fragt nach dem Namen und dem Geburtsdatum. Dieselben
  Felder stehen unter Einstellungen, Allgemein. Der Name ist die Begrüßung.
- Am Geburtstag gibt es 500 Coins, einmal in diesem Jahr. Ein Geburtstag am
  29. Februar wird in einem Jahr ohne diesen Tag am 28. Februar gutgeschrieben.
- Name, Geburtsdatum und das schon ausgezahlte Jahr reisen mit der
  vollständigen Sicherung. Die App zurücksetzen löscht das Datum, und die
  Einrichtung fragt wieder danach.

### Symbol

- Das Symbol auf dem Home-Bildschirm ist ein Liquid-Glass-Icon. In Klar und
  Getönt übernimmt die Fläche dieselbe Systemtönung wie die übrigen Icons.
  Grün bleibt in der normalen und der dunklen Darstellung.

### Gesundheit und Kalender

- Ein Training startet einen Timer. Die Dauer steht im Verlauf und im
  Abschlussdialog.
- Mehrere Trainings können eine Challenge teilen. Am Training liegt kein
  Wochentag. Ein beendetes verknüpftes Training hakt die Challenge für diesen
  Tag ab und setzt nur dieses Kalendervorkommen auf das Fünf-Minuten-Raster.
  Die übrige Serie bleibt. Fand keines der verknüpften Trainings statt, wird
  dieses Vorkommen nach dem Tag entfernt.
- Ein Kalendereintrag nennt seine Verknüpfung, zum Beispiel „Mit Challenge Gym
  verknüpft“, oder den Namen der Gruppe oder der Belohnung. Mehrere Challenges
  in einem Slot stehen gemeinsam an dem Termin. Eine Challenge nennt ihren
  Kalendereintrag in der Liste, in der Gruppe, auf der Startseite und in der
  Tagesansicht. Auf einem Training werden gleiche Titel zu „GYM · 12“
  zusammengezogen.
- Der Apple-Kalender wird von 30 Tagen zurück bis 365 Tage voraus gelesen.
  Wird die App aktiv und der Zugriff ist schon erlaubt, gleicht sie ab. Die
  erste Erlaubnis kommt weiter über den Knopf unter Herausforderung,
  Kalender & Erinnerungen.
- Ein neues Vorkommen einer Serie behält Challenge, Gruppe und Belohnung
  dieser Serie. Trainings, die mit der Challenge verknüpft sind, bekommen
  diesen Termin dazu. Einträge außerhalb des Fensters bleiben. Ein
  verschwundener Eintrag wird nur innerhalb des Fensters gelöscht, inklusive
  seiner Trainingsverknüpfung. Der Abgleich nutzt das echte Datum, damit ein
  simulierter Tag nichts löscht.
- Challenge und Kalender ziehen sich gegenseitig nach: eine Challenge
  verknüpft ihre Termine, ein Termin verknüpft die Challenge und deren andere
  Termine. Das Entfernen einer Challenge nimmt ihre Termine mit und lässt
  einen manuellen Termin ohne Challenge stehen. Das Abwählen eines Termins
  einer Challenge nimmt die Challenge und ihre anderen Termine mit.
- Die Auswahlliste zeigt an jeder Zeile einen Kreis. Ein Tipp füllt den Kreis,
  Fertig speichert. Die Liste ist eine normale Scrollansicht, weil die
  Systemzeile den Tipp verschluckt hat.

### Einstellungen, Daten und Checks

- Die Einstellungen folgen dem Aufbau der Apple-Einstellungen. Allgemein hat
  das Profil, Sprache, Erscheinungsbild, das tägliche Briefing mit Uhrzeit und
  die Version. Finanzen hat die Konten und das Girokonto samt Gebühr fürs
  Depot. Herausforderung hat Kalenderabgleich, eigene Kategorien,
  Freeze-Faktor, Streak-Multiplikatoren und die Abstinenz-Boni. Gesundheit hat
  den Pausen-Ton. Daten hat Bankimport, Trade-Republic-Import, Sicherung und
  die Löschaktionen.
- Finanzen, Challenges und Training lassen sich getrennt löschen. Alle Daten
  löschen behält Konten, Sprache und Erscheinungsbild. Die App zurücksetzen
  löscht auch die Konten und startet die Ersteinrichtung neu.
- Allgemein hat den Entwicklermodus. Ist er an, ist „Aktueller Tag“ der Tag,
  den Startseite, Challenges, Kalender und Streaks als heute verwenden.
  Die Finanzen bleiben am echten Datum.
- „Tests ausführen“ gruppiert die Checks nach Streak, Multiplikator, Challenge,
  Kalender, Training, Abstinenz und Entwicklermodus und kennzeichnet jede Zeile
  als Unit oder Integration. Dieselbe Suite ist das Xcode-Target LififyTests,
  mit einem Test pro Thema. Die Checks schreiben keine Nutzerdaten.
