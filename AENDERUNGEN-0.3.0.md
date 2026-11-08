# Änderungen in 0.3.0

Stand gegenüber `main`. Die Rechenregeln der Finanzen bleiben in
[FINANZEN.md](FINANZEN.md) beschrieben. Die angezeigte Version ist 0.3.0.

## Finanzen

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

## Challenges und Coins

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

## Abstinenz

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
- Ein erreichter Bonus erscheint auf der Startseite, wie die Karte „Heute
  abhaken“. Der Haken quittiert die Meldung. Die Coins sind dann schon
  gutgeschrieben.
- Ein Rückfall setzt den Timer auf jetzt und speichert Datum, Uhrzeit und die
  Dauer des beendeten Laufs. Schon gezahlte Coins bleiben. Die Boni können im
  neuen Lauf wieder erreicht werden.
- Schwierigkeit, gezahlte Stufen, Faktoren, Rückfälle und offene Meldungen
  liegen neben dem Datenmodell und reisen mit der Challenge-Sicherung.

## Gesundheit und Kalender

- Ein Training startet einen Timer. Die Dauer steht im Verlauf und im
  Abschlussdialog.
- Mehrere Trainings können eine Challenge teilen. Am Training liegt kein
  Wochentag. Ein beendetes verknüpftes Training hakt die Challenge für diesen
  Tag ab und setzt nur dieses Kalendervorkommen auf das Fünf-Minuten-Raster.
  Die übrige Serie bleibt. Fand keines der verknüpften Trainings statt, wird
  dieses Vorkommen nach dem Tag entfernt.
- Ein Kalendereintrag nennt seine Verknüpfung, zum Beispiel „Mit Challenge Gym
  verknüpft“, oder den Namen der Gruppe oder der Belohnung. Eine Challenge
  nennt ihren Kalendereintrag in der Liste, in der Gruppe, auf der Startseite
  und in der Tagesansicht. Auf einem Training werden gleiche Titel zu
  „GYM · 12“ zusammengezogen.
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

## Einstellungen, Daten und Checks

- Die Einstellungen folgen dem Aufbau der Apple-Einstellungen. Allgemein hat
  Sprache, Erscheinungsbild und die Version. Finanzen hat die Konten und das
  Girokonto samt Gebühr fürs Depot. Herausforderung hat Kalenderabgleich,
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
