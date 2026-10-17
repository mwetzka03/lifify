# Finanzregeln

Diese Datei beschreibt, wie Lifify Konten, Zeiträume, Einnahmen, Ausgaben,
Depot und das Home-Budget rechnet. Sie gilt für Version 0.2.0.

Zeitraum und Konto sind ein gemeinsamer Filter. Eine Änderung gilt in der
Finanzansicht, in den Buchungen und in den Listen für Einnahmen und Ausgaben.

## Konten

- Kontenarten sind Girokonto, Spartopf, Oberspartopf und Depot.
- Ein Oberspartopf gruppiert Spartöpfe und wird nicht noch einmal zur Summe
  addiert.
- Das Hauptkonto ist verpflichtend und lässt sich nicht löschen.
- Ein Depot ist nicht liquide und muss mit genau einem Girokonto verknüpft
  sein. Ohne diese Verknüpfung lässt es sich nicht anlegen.
- Mehrere Depots dürfen an verschiedenen Girokonten hängen. Im Kontofilter
  erscheinen sie als ein Eintrag **Depot**. Die einzelnen Depotkonten stehen
  dort nicht separat.
- Der Link „Depot“ unter Weitere Bereiche entfällt. Dieselben Positionen sieht
  man, wenn im Filter **Depot** gewählt ist.
- Für Käufe und Verkäufe lässt sich in den Einstellungen ein Standard-Girokonto
  und eine Standardgebühr hinterlegen. Die Gebühr ist beim Buchen zunächst aus.

## Zeitraum

- Vor und zurück sowie Heute stehen über der Finanzliste, damit der Wechsel
  immer ankommt.
- Zeiträume folgen der Haupteinnahme, wenn der Gehaltszeitraum aktiv ist.
  Sonst sind es Kalendermonate.
- Der erste Zeitraum beginnt mit den Buchungen des Hauptkontos. Sein Start ist
  der Stichtag.
- Trade-Republic-Buchungen vor dem Stichtag werden nicht angelegt. Buchungen am
  Stichtag und danach werden angelegt, auch wenn der erste Zeitraum schon vorbei
  ist.
- Depotpositionen aus dem ganzen Auszug werden trotzdem übernommen, auch Käufe
  vor dem Stichtag.
- Gibt es auf dem Hauptkonto noch keine Buchung, gibt es noch keinen Zeitraum.
  Dann werden alle Auszugszeilen gebucht.
- Der Startsaldo des ersten Zeitraums ist der rechte Saldo des Auszugs am
  Starttag. Fehlt dieser Tag, gilt der Saldo des letzten vorherigen Tags.
- Der Saldo ist der Stand des Girokontos nach der Zeile. Er wird nie als
  Zahlungsbetrag gebucht.

## Saldo bei allen Konten

Ist **Alle Konten** gewählt, enthalten Startsaldo und Endsaldo den Depotwert.

- Der Startsaldo enthält nur Aktien, die am Ende des ersten Tages des Zeitraums
  schon gehalten werden. Das ist derselbe Zeitpunkt wie der Kassensaldo, also
  nach den Buchungen dieses Tages. Käufe an späteren Tagen des Zeitraums fehlen
  im Startsaldo.
- Der Endsaldo enthält die Stücke, die am Ende des Zeitraums gehalten werden.
- Der Wert ist Stückzahl mal aktueller Kurs. Historische Kurse werden nicht
  gespeichert.
- Darunter steht der liquide Saldo ohne Depot, in derselben Zifferngröße wie
  der Gesamtsaldo. Die Karte wird höher, statt die Zahl zu verkleinern.
- Ist **Depot** gewählt, zeigt die Karte Gesamtvermögen nur den Depotwert und
  die Veränderung, ohne leeren Bereich. Einnahmen, Ausgaben, Startsaldo und
  Endsaldo entfallen dort. Weitere Bereiche entfallen ebenfalls.

## Einnahmen und Ausgaben

### Alle Konten

Einnahmen sind:

- Eingänge von einer fremden IBAN oder einem fremden Konto
- Dividenden (Ertrag)
- Zinsen
- die positive Kursdifferenz eines Aktienverkaufs

Nicht als Einnahme zählen Eingänge von der eigenen IBAN und der volle
Verkaufserlös.

Ein Verkauf wird mit Einstand und Gebühren verglichen. Der Erlös ist der
Zahlungsbetrag nach Gebühr, der Einstand ist der durchschnittliche Kaufpreis
der verkauften Stücke inklusive Kaufgebühren. Nur die Differenz erscheint:

- positiv als Einnahme
- negativ als Ausgabe
- null wird nicht gezeigt

Aktienkäufe und Sparpläne sind bei allen Konten keine Ausgaben. Das Geld wechselt
nur vom Girokonto ins Depot. Andere Umbuchungen zwischen eigenen Konten zählen
ebenfalls nicht als Einnahme oder Ausgabe.

### Verknüpftes Girokonto

Ist das Girokonto gewählt, das mit dem Depot verknüpft ist, zählen Käufe,
Sparpläne und Verkäufe mit dem vollen Betrag. Ein Abfluss ist eine Ausgabe, ein
Zufluss eine Einnahme. Die Kursdifferenz wird dann nicht noch einmal extra
gezählt.

### Einzelnes anderes Konto

Umbuchungen, die dieses Konto berühren, zählen dort voll mit. Depotkäufe eines
anderen Girokontos erscheinen nicht.

## Depot und Einzelpositionen

- Jeder Kauf derselben ISIN bleibt eine eigene Position mit Datum, Stückzahl
  und Kurs.
- Der Einstand ist die Summe der Zahlungen geteilt durch die verbleibenden
  Stücke, einmal gerundet.
- Der Stückpreis eines importierten Kaufs ist der Zahlungsbetrag geteilt durch
  die Quantity.
- Eine Gebühr erhöht den Kauf und mindert den Verkaufserlös. Sie gilt einmal
  pro Buchung.
- Ein Kauf ist eine Umbuchung vom Girokonto ins Depot. Ein Verkauf ist eine
  Umbuchung vom Depot auf das Girokonto.
- Ein Übertrag verändert das Depot, ohne das Girokonto zu belasten.
- Verkaufen geht nach Stückzahl oder nach Prozent, einschließlich 25 %, 50 %,
  75 % und 100 %.
- Eine vollständig verkaufte Position verschwindet aus dem Depot. Die Buchung
  bleibt. Die Kaufhistorie bleibt erhalten, damit die Kursdifferenz gerechnet
  werden kann.
- Die Liste sortiert nach Wert, Kaufzeitpunkt oder Name. Die Veränderung steht
  wahlweise seit dem Vortag oder seit dem Kauf, in Euro oder in Prozent.
- Kurse aktualisieren und eine neue Position sind große Liquid-Glass-Buttons.
  Nachkauf und Verkauf in der Position ebenfalls.
- Kurse werden über die ISIN abgerufen. Schlägt das fehl, bleibt der manuelle
  Fallbackkurs.

## Sparpläne

- Ein Sparplan entsteht aus den Ausführungen im Auszug.
- Der Betrag ist der letzte Zahlungsausgang. Liegen am selben Tag mehrere
  Ausführungen, gilt der größte Betrag.
- Der Rhythmus ergibt sich aus dem Abstand der Ausführungstage: bis 10 Tage
  wöchentlich, bis 18 zweiwöchentlich, bis 45 monatlich, sonst jährlich. Eine
  einzelne Ausführung gilt als monatlich.
- Der Plan ist aktiv, wenn die letzte Ausführung nah am Auszugsende liegt.
  Sonst ist er beendet. Für eine Position mit Bestand null wird kein Plan
  fortgeführt.
- Im Depot ist **Sparpläne** ein Link in eine eigene Liste, kein aufklappbarer
  Block. Die Liste filtert nach Aktiv und Beendet. Wischen bearbeitet oder
  löscht einen Plan.
- Oben stehen die Kosten aller aktiven Pläne pro Woche und pro Monat. Eine
  Woche ist ein Viertel des Monats, weil ein Monat vier Abbuchungstermine hat.
- Trade Republic bucht am 2., 9., 16. und 23. Wöchentlich sind alle vier Tage,
  zweiwöchentlich der 2. und der 16., monatlich und jährlich nur der 2. Ist
  das kein Bankarbeitstag, gilt der nächste Bankarbeitstag.
- Die Sparpläne im Depot sind die Vorlage. Jeder Plan ist eine Fixkosten auf
  dem verknüpften Girokonto, mit demselben Betrag, Rhythmus und Status.
  Ändern oder Löschen auf einer Seite ändert die andere.
- Eine bereits gebuchte Ausführung zählt nicht noch einmal als offene Fixkosten.
- Bei allen Konten werden diese Fixkosten angezeigt. Den gemeinsamen Saldo
  mindern sie nicht, weil das Geld im Depot bleibt. Auf einem anderen Konto
  erscheinen sie nur, wenn es das verknüpfte Girokonto ist.
- In der Fixkostenliste steht der nächste Abbuchungstag und wie viele Termine
  im gewählten Zeitraum noch offen sind.
- Dieselben offenen Termine stehen in den Ausgaben als Prognoseausgaben, je
  an ihrem Tag.

## Buchungen in der Finanzansicht

Unten stehen die Buchungen des gewählten Zeitraums und Kontos, nicht mehr eine
eigene Ereignisliste. Darüber sucht ein Feld nach Titel oder Notiz. Rechts
daneben legt das Plus eine Buchung an. Jede Zeile zeigt Icon, Art, Datum und
Betrag, öffnet die Buchung und lässt sich wischen: links löschen, rechts
bearbeiten.

## Home-Budget

Das Budget auf der Home-Seite ist nicht dieselbe Summe wie die Finanzansicht.
Ein Tipp öffnet die Aufschlüsselung, nicht die Finanzansicht. Dort stehen die
Einnahmen, die Prognosen und die Buchungen, aus denen Gesamt und Verbraucht
entstehen.

- Einnahmen sind nur fremde Eingänge. Die eigene IBAN, Dividenden und Zinsen
  zählen nicht. Offene Gehaltsprognosen im Zeitraum zählen weiter.
- Verbrauch sind normale Ausgaben plus Aktienkäufe und Sparplan-Ausführungen.
  Andere Umbuchungen zählen nicht.
- Das Tagesbudget ist das verbleibende Budget geteilt durch die Tage bis zum
  nächsten Gehalt.

## Trade-Republic-Import

Der Import ist vom Bankimport getrennt. In der Einrichtung kommt er nach dem
Hauptkonto und nach dem optionalen CSV- oder CAMT-Import. Unter Einstellungen
steht er in einem eigenen Abschnitt. Ein Zielkonto gibt es nur für CSV und
CAMT. Ein PDF wird dort nicht automatisch erkannt.

Gelesen wird die Umsatzübersicht mit Datum, Typ, Beschreibung, Zahlungseingang,
Zahlungsausgang und Saldo.

- Handel verändert das Depot und das verknüpfte Girokonto.
- Kartentransaktion ist eine Ausgabe des Girokontos. Eine Erstattung, die den
  Saldo erhöht, bleibt positiv.
- Ertrag und Zinsen sind Einnahmen des Girokontos, keine Depotbuchung.
- Eine Überweisung auf ein eigenes Konto ist eine Umbuchung. Eine Überweisung
  von einer fremden IBAN ist auf dem Empfängerkonto eine Einnahme.
- Ein erneuter Import ersetzt den vorherigen Auszug dieses Girokontos und baut
  das verknüpfte Depot neu auf.

Damit die Kursdifferenz bereits vollständig verkaufter Papiere stimmt, muss der
Auszug nach einer Regeländerung neu importiert werden.
