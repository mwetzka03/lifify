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
- Der Startsaldo des ersten Zeitraums ist der rechte Saldo des Auszugs vor dem
  Starttag, also der letzte gedruckte Saldo der Zeilen davor. Fehlt so eine
  Zeile, gilt der Eröffnungssaldo des Auszugs.
- Der Saldo ist der Stand des Girokontos nach der Zeile. Er wird nie als
  Zahlungsbetrag gebucht.
- Dieser Startsaldo wird als Saldo-Korrektur am Starttag gespeichert. In der
  Anzeige zählt er zum Beginn des Zeitraums. Einnahmen und andere Buchungen
  am ersten Tag gehören in den Zeitraum, nicht in den Startsaldo.

## Saldo bei allen Konten

Ist **Alle Konten** gewählt, ist der Startsaldo die Summe der Startsalden der
einzelnen Konten plus den Depotwert am Tag davor.

- Buchungen am ersten Tag, auch Einnahmen, zählen nicht in den Startsaldo.
  Eine Saldo-Korrektur an diesem Tag bleibt der Eröffnungswert.
- Der Depotwert sind die Stücke, die am Ende des Tages davor gehalten wurden.
  Käufe am ersten Tag fehlen im Startsaldo und liegen im Zeitraum.
- Der Kurs ist der Schlusskurs dieses Tages, sobald er gespeichert ist. Fehlt
  er, gilt der aktuelle Kurs, die Stückzahl bleibt die historische.
- Liegt der Stichtag in der Zukunft, kommt der aktuelle Kurs zum Einsatz. Noch
  nicht gebuchte Sparpläne erhöhen bis zu diesem Tag die Stückzahl. Pro
  Ausführung kommen so viele Stücke dazu, wie der Planbetrag beim aktuellen
  Kurs kauft. Kostet der ETF 100 € und der Plan 50 €, ist das eine halbe
  Stückzahl, auch über ein Jahr hinweg. Der Wert dieser Stücke ist der
  Eurobetrag, ohne prozentuale Steigerung. Ein Plan ohne passende Position
  zählt weiter nur als Eurobetrag. Auf dem verknüpften Girokonto mindern
  dieselben Termine den Startsaldo, sodass die Summe unverändert bleibt.
- In der Depotliste steht für den gewählten Zeitraum diese Stückzahl und der
  dazu passende Wert. Die Veränderung daneben bleibt die der schon gehaltenen
  Stücke.
- Startsaldo und Endsaldo stehen in derselben Reihe. Darunter steht der liquide
  Saldo ohne Depot, in derselben Zifferngröße. Die Zahl darf leicht schrumpfen,
  damit beide Kacheln nebeneinander passen. Kacheln in einer Reihe sind gleich
  hoch, auch wenn eine Zahl oder der Hinweis darunter umbricht.
- Das Endsaldo ist der Startsaldo plus die Prognose-Differenz. Unter dem
  Endsaldo steht keine weitere Differenzzahl. Die Prognose-Differenz ist
  gebuchte plus offene Einnahmen abzüglich gebuchter plus offener Ausgaben.
- Im laufenden Zeitraum steht unter der Differenz das Wort **Prognose** in
  einer eigenen Zeile und der Betrag darunter, ebenfalls allein. **Offen**
  steht bei Einnahmen, Ausgaben, Fixkosten und variablen Kosten genauso:
  Überschrift oben, Betrag darunter. Der große Betrag bleibt dort der schon
  gebuchte. Bei den Einnahmen enthält der große Betrag die Prognose bereits,
  Offen zeigt nur den noch offenen Teil.
- Liegt der ganze Zeitraum in der Zukunft, gibt es kein Offen. Der große
  Betrag ist dann der normale Wert, also gebucht plus noch offen. Bei den
  Fixkosten steht dieser Betrag direkt in der Kachel Fixkosten. Die Differenz
  zeigt direkt die Prognose, ohne eine zweite Zeile.
- Ein abgeschlossener Zeitraum zeigt nur Gebuchtes, ohne Offen und ohne
  Prognosezeile.
- Während die Finanzkacheln zum ersten Mal oder nach einem Wechsel von
  Zeitraum oder Konto rechnen, steht dort eine Ladeanzeige. Kurze
  Datenänderungen beim Start werden zu diesem einen Ladevorgang
  zusammengezogen. Danach bleiben die Kacheln stehen und die Zahlen
  aktualisieren sich, ohne die Ansicht erneut zu leeren. Die Filter bleiben
  benutzbar. In der Finanzansicht bleiben die Buchungen darunter sichtbar.
- Ist **Depot** gewählt, zeigt die Karte Gesamtvermögen den Depotwert am Ende
  des gewählten Zeitraums, inklusive noch nicht gebuchter Sparpläne, und die
  Veränderung. Die Positionen stehen direkt darunter. Beides erscheint, ohne
  auf die übrigen Kacheln zu warten. Einnahmen, Ausgaben, Startsaldo und
  Endsaldo entfallen dort. Weitere Bereiche entfallen ebenfalls.

## Einnahmen und Ausgaben

### Alle Konten

Einnahmen sind:

- Eingänge von einer fremden IBAN oder einem fremden Konto
- Dividenden (Ertrag)
- Zinsen
- die positive Kursdifferenz eines Aktienverkaufs

Nicht als Einnahme zählen Eingänge von der eigenen IBAN, der volle
Verkaufserlös und eine Rückerstattung.

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

### Einnahmeprognosen

Eine Prognose mit Konto gilt nur für dieses Konto. In der Einnahmenliste und
in der Einnahmenkachel eines einzelnen Kontos erscheinen nur dessen Prognosen.
Eine Prognose ohne Konto erscheint nur bei allen Konten, nicht auf einem
einzelnen Konto. Dasselbe gilt für den Startsaldo: jedes Konto rechnet nur mit
seinen eigenen Prognosen.

In der Einnahmenansicht steht jeder noch offene Termin des Zeitraums, nicht nur
der nächste. Ist genau ein Konto gewählt, stehen dort zusätzlich die
Umbuchungsprognosen, bei denen das Geld auf diesem Konto ankommt. Bei allen
Konten und im Depot stehen dort keine Umbuchungen. Neue Einnahmeprognosen
legt man in der Finanzansicht über das Plus im Bereich Prognosen an. In der
Einnahmenansicht gibt es dafür kein Plus mehr. Eine Prognose, der schon eine
Buchung zugeordnet ist, bleibt in der Liste und ist ausgegraut.

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
- Kurse aktualisieren steht links in einer eigenen Blase, das Plus für eine
  neue Position rechts in einer eigenen Blase, mit Abstand dazwischen. Dieselben
  begrenzten Blasen gelten für die Suche und das Plus bei den Buchungen.
- Kurse kommen von Yahoo Finance. Eine deutsche Notierung, etwa Xetra,
  Frankfurt, gettex oder Tradegate, wird bevorzugt. Lang & Schwarz hat keine
  öffentliche Kurs-API. Gibt es mehrere Treffer, wird nicht abgebrochen.
- Beim Aktualisieren werden tägliche Euro-Schlusskurse gespeichert. Fehlt ein
  Tag, gilt der letzte gespeicherte Kurs davor, sonst der aktuelle Kurs.
- Schlägt der Abruf fehl, bleibt der manuelle Fallbackkurs. Die Stückzahl zum
  Stichtag wird trotzdem verwendet.

## Sparpläne

- Ein Sparplan entsteht aus den Ausführungen im Auszug.
- Der Betrag ist der letzte Zahlungsausgang. Liegen am selben Tag mehrere
  Ausführungen, gilt der größte Betrag.
- Der Rhythmus ergibt sich aus dem Abstand der Ausführungstage: bis 10 Tage
  wöchentlich, bis 18 zweiwöchentlich, bis 45 monatlich, sonst jährlich. Eine
  einzelne Ausführung gilt als monatlich.
- Der Plan wird übernommen, wenn die letzte Ausführung nah am Auszugsende liegt
  und die Position noch Bestand hat. Ein beendeter Plan wird gelöscht und nicht
  angezeigt. Es gibt keinen Schalter zwischen Aktiv und Beendet.
- Im Depot ist **Sparpläne** ein Link in eine eigene Liste, kein aufklappbarer
  Block. Wischen bearbeitet oder löscht einen Plan. Beim Bearbeiten lässt sich
  das Konto wählen, von dem der Plan abgebucht oder prognostiziert wird. Ist
  noch keins gespeichert, gilt das Girokonto aus den Einstellungen.
- Oben stehen die Kosten aller aktiven Pläne pro Woche und pro Monat. Eine
  Woche ist ein Viertel des Monats, weil ein Monat vier Abbuchungstermine hat.
- Unten stehen die im gewählten Finanzzeitraum gebuchten Ausführungen, mit
  Name, Datum und Betrag. Der Zeitraum ist derselbe wie in der Finanzansicht.
- Trade Republic bucht am 2., 9., 16. und 23. Wöchentlich sind alle vier Tage,
  zweiwöchentlich der 2. und der 16., monatlich und jährlich nur der 2. Ist
  das kein Bankarbeitstag, gilt der nächste Bankarbeitstag.
- Die Sparpläne im Depot sind die Vorlage. Jeder Plan bleibt intern eine
  Fixkosten auf dem verknüpften Girokonto, damit die Prognose weiterläuft.
  In der Fixkostenliste stehen die Pläne nicht einzeln. Eine Zeile zeigt den
  Gesamtbetrag des Zeitraums, also schon abgebuchte Ausführungen plus noch
  offene Termine, und öffnet die Sparplanliste.
- Eine bereits gebuchte Ausführung zählt nicht noch einmal als offene Fixkosten.
  Sie steht aber im gebuchten Fixkostenbetrag des Zeitraums, auch wenn sie vor
  der letzten Ausführung lag.
- Bei allen Konten werden diese Fixkosten angezeigt. In der Prognose-Differenz
  zählen offene Sparpläne als offene Ausgaben. Im Depotwert desselben
  Zeitpunkts stehen sie als Zugang, auf dem Girokonto als Abgang.
- Auf einem anderen Konto erscheinen sie nur, wenn es das verknüpfte Girokonto
  ist.
- In der Fixkostenliste steht bei normalen Fixkosten der nächste Abbuchungstag
  und wie viele Termine im gewählten Zeitraum noch offen sind. Ein Tipp öffnet
  die Detailansicht: alle bisher zugeordneten Buchungen, ob von Hand oder
  automatisch erkannt, und die nächsten drei Termine. Eine Buchung lässt sich
  dort antippen, bearbeiten oder aus der Zuweisung nehmen. Die Buchung selbst
  bleibt dabei stehen. Wischen nach rechts bearbeitet die Fixkosten, Wischen
  nach links löscht sie. Ist ein Konto gewählt, zeigt die Zuweisung nur
  Buchungen dieses Kontos.
- Dieselben offenen Termine stehen in den Ausgaben als Prognoseausgaben, je
  an ihrem Tag, so wie die Fixkostenkachel sie zählt. Auf dem Hauptkonto sind
  das die Haushalts-Fixkosten, auf einem anderen Konto nur dessen Sparpläne.
  In derselben Liste stehen der noch offene Rest jeder variablen Kosten und
  die geplanten, noch nicht gekauften Einträge des Einkaufszettels. Einkäufe
  nur bei allen Konten und auf dem Hauptkonto. Ist genau ein Konto gewählt,
  stehen dort auch die Umbuchungsprognosen, die von diesem Konto abgehen. Bei
  allen Konten und im Depot stehen dort keine Umbuchungen. Schon zugeordnete
  Termine bleiben in diesen Listen und sind ausgegraut.

## Buchungen in der Finanzansicht

Unten stehen die Buchungen des gewählten Zeitraums und Kontos, nicht mehr eine
eigene Ereignisliste. Darüber sucht ein Feld nach Titel oder Notiz. Rechts
daneben, mit Abstand, legt das Plus eine Buchung an. Beide liegen in eigenen
Blasen. Jede Zeile zeigt Icon, Kategorie, Datum und Betrag, öffnet die Buchung
und lässt sich wischen: links löschen, rechts bearbeiten.

Über den Buchungen steht ein eigener Bereich **Prognosen**. Darin liegen die
Einnahmen, Fixkosten, variablen Kosten und Einkäufe des Zeitraums, gefiltert
wie in der Einnahmen- und Ausgabenansicht. Ist genau ein Konto gewählt, liegen
dort auch die Umbuchungen, Abgang negativ und Zugang positiv. Darüber sucht ein
eigenes Feld, rechts daneben legt das Plus eine Prognose an. Zur Auswahl stehen
Einnahmeprognose, Umbuchungsprognose, Sparplan, Fixkosten und variable Kosten.
Jedes öffnet sein eigenes Formular. Die Buchungssuche filtert diesen Bereich
nicht. Ein Tipp öffnet die Detailansicht. Dort lässt sich eine echte Buchung
zuweisen. Ist ein Konto gewählt, stehen nur Buchungen dieses Kontos zur
Auswahl. Die Zuweisung ersetzt die Prognose für den ganzen Zeitraum, die
anderen Termine bleiben. Eine schon zugeordnete Prognose, von Hand oder
automatisch, bleibt sichtbar und ist ausgegraut. Wischen nach rechts bearbeitet
die Serie, Wischen nach links löscht nur diesen Termin. Im Depot entfällt der
Bereich. Die Zeilen stehen nicht zwischen den Buchungen.

Alle Sparpläne in diesem Bereich stehen in einem Topf. Zugeklappt zeigt er die
Kosten pro Woche und die Summe des Zeitraums. Die einzelnen Termine erscheinen
erst beim Aufklappen.

Die angezeigte Kategorie ist keine eigene Speicherart. Gespeichert bleibt
Einnahme, Ausgabe, Umbuchung oder Saldo-Korrektur. Angezeigt wird:

- Einnahme, Zinsen, Dividende, Ausgabe, Rückerstattung, Depotkauf,
  Depotverkauf, Sparplan, Umbuchung
- Eine Saldo-Korrektur bleibt eine Saldo-Korrektur.

Jedes davon hat ein eigenes Symbol. Dieselben Symbole stehen in den Listen für
Einnahmen und Ausgaben und bei den Buchungen auf der Home-Seite.

- Einnahme ist ein Geldschein, Ausgabe ein Einkaufswagen, Rückerstattung ein
  Pfeil zurück.
- Depotkauf ist ein steigender Chart, Depotverkauf ein fallender Chart.
- Sparplan und Umbuchung behalten ihre bisherigen Symbole.

Die Farbe von Depotkauf, Sparplan und Depotverkauf hängt vom Filter ab:

- Girokonto: Depotkauf und Sparplan sind rot, Icon und Betrag. Ein Verkauf ist
  grün. Unter dem Betrag steht die Differenz kleiner, grün wenn positiv und rot
  wenn negativ.
- Alle Konten: Depotkauf, Sparplan und der Verkaufsbetrag bleiben in der
  Textfarbe, auch das Icon. Nur die Differenz unter dem Verkauf ist rot oder
  grün.
- Depot: Depotkauf und Sparplan sind grün, Icon und Betrag. Ein Verkauf ist rot.

Einnahme, Zinsen und Dividende bleiben grün, eine Ausgabe rot. Eine
Rückerstattung bleibt in der Textfarbe, Icon und Betrag, und zeigt die ganze
Summe. In der
Einnahmen- oder Ausgabenliste ist die Kursdifferenz selbst der Betrag und trägt
deren Farbe. Dort steht keine zweite Differenz darunter.

Ein Sparplan erkennt man am Titel „Sparplan:“. Ein Depotkauf geht auf ein Depot,
ein Depotverkauf kommt von einem Depot. Zinsen und Dividenden stehen in der
Notiz als Typ Zinsen oder Typ Ertrag.

Eine Umbuchung zwischen eigenen Konten heißt bei allen Konten Umbuchung. Ist
genau ein Konto gewählt, ist sie dort eine Ausgabe, wenn das Geld das Konto
verlässt, und eine Einnahme, wenn es ankommt. Depotkauf, Depotverkauf und
Sparplan behalten ihre Kategorie, auch auf einem einzelnen Konto. Die Zählregeln
bleiben dieselben: bei allen Konten zählt ein Depotverkauf nur mit der positiven
Kursdifferenz als Einnahme und mit der negativen als Ausgabe. Auf dem
verknüpften Girokonto zählt der volle Betrag.

Die Detailansicht einer Umbuchung zeigt beide Seiten, den Abgang auf dem einen
Konto und den Zugang auf dem anderen. Ein Depotverkauf zeigt zusätzlich immer
Einkaufspreis, Verkaufspreis und Differenz. Beim Anlegen einer gewöhnlichen
Buchung wählt man die Kategorie. Depotkauf, Depotverkauf und Sparplan stehen
in dieser Auswahl nicht, auch nicht beim Bearbeiten. Diese drei entstehen nur,
wenn eine Depotposition angelegt, nachgekauft oder verkauft wird, oder wenn
ein Sparplan angelegt wird. Öffnet man eine bestehende Buchung dieser Art,
bleibt die Kategorie fest und lässt sich dort nicht umstellen. Ein Depotverkauf
wird weiter als Umbuchung vom Depot auf das Konto gespeichert, damit die
Kursdifferenz gilt.

Das Depot steht bei gewöhnlichen Buchungen, Fixkosten, Einnahmeprognosen,
Umbuchungsprognosen, variablen Kosten und Budgetpools nicht zur Auswahl. Nur
Depotkauf, Depotverkauf und Sparplan nutzen es, und dort nur auf der Depotseite.

## Rückerstattung

Eine Rückerstattung ist eine eigene Kategorie. Sie braucht immer eine
ursprüngliche Ausgabe. Die Verknüpfung liegt in den lokalen Einstellungen, nicht
in der Buchung selbst.

- In der Buchungsliste steht die Rückerstattung mit ihrer ganzen Summe. Sie
  zählt nicht in den Einnahmentopf und erscheint nicht in der Einnahmenliste.
- Die ursprüngliche Ausgabe bleibt eine Ausgabe. Unter ihrem Betrag steht der
  Rest, der noch zählt, kleiner und wie die Kursdifferenz bei einem Verkauf.
  Eine Ausgabe von 100 € mit einer Rückerstattung von 30 € zählt als 70 €.
  Mehrere Rückerstattungen werden addiert. Übersteigt die Summe die Ausgabe,
  zählt die Ausgabe als null.
- Der Kontostand behält beide Bewegungen: die Ausgabe geht ab, die
  Rückerstattung kommt an.
- In der Detailansicht der Ausgabe stehen die verknüpften Rückerstattungen.
  In der Detailansicht der Rückerstattung steht die ursprüngliche Buchung.
- In der Detailansicht einer normalen Ausgabe legt ein Button eine
  Rückerstattung an, die schon mit dieser Ausgabe verknüpft ist. Der Betrag
  wird dort eingegeben. Weitere Rückerstattungen derselben Ausgabe bleiben
  möglich. Eine Umbuchung, die auf einem einzelnen Konto wie eine Ausgabe
  aussieht, bekommt diesen Button nicht.

## Umbuchungsprognosen

Neben Einnahme- und Ausgabenprognosen gibt es Umbuchungsprognosen. Anlegen
läuft über das Plus im Bereich Prognosen der Finanzansicht, nicht mehr über
eine eigene Liste in Weitere Bereiche. Jede Prognose hat zwei Konten, beide
ohne Depot, einen Betrag und einen Rhythmus.

- Termine des gewählten Zeitraums stehen im Bereich Prognosen über den
  Buchungen. In der Einnahmenansicht nur die Zugänge, in der Ausgabenansicht
  nur die Abgänge. Das gilt nur, wenn genau ein Konto gewählt ist. Bei allen
  Konten und im Depot fehlt die Umbuchung in diesen Listen. Ein Tipp öffnet
  die Detailansicht. Dort kann die Prognose einer echten Buchung zugewiesen
  werden. Ist ein Konto gewählt, bietet die Liste nur dessen Buchungen an.
  Die Zuweisung gilt für den ganzen Zeitraum. Die Termine bleiben sichtbar
  und werden ausgegraut. Dieselbe Zuweisung gilt für Einnahmen, Fixkosten,
  variable Kosten und den Einkaufszettel. Eine Buchung, die schon automatisch
  erkannt wird, zum Beispiel über die IBAN, ersetzt die Prognose weiter von
  selbst und graut sie ebenfalls aus. Wischen löscht nur den einzelnen
  Termin, nicht die ganze Serie.
- Weist man die Prognose einer echten Umbuchung zu, ersetzt diese Buchung die
  Prognose für den ganzen Zeitraum. Die Termine bleiben ausgegraut stehen, die
  Buchung bleibt.
- In der Prognose des Kontostands bewegt ein offener Termin Geld vom einen
  Konto auf das andere. Liegen beide Konten in der Ansicht, bleibt die Summe
  null. Eine schon ersetzte, aber noch zukünftige Umbuchung zählt einmal mit
  ihrem echten Betrag. Sparpläne und Depotkäufe sind davon ausgenommen.
- Auf einem einzelnen Konto zählt ein noch offener Termin zusätzlich als offene
  Einnahme, wenn das Geld dort ankommt, und als offene Ausgabe, wenn es von
  dort geht. Im laufenden Zeitraum steht das unter Offen. In einem zukünftigen
  Zeitraum steckt es im normalen Einnahmen- oder Ausgabenbetrag. Termine vor
  dem Zeitraum liegen schon im Startsaldo und werden dort nicht noch einmal
  gezählt. Eine echte Umbuchung, die der Prognose im Zeitraum zugeordnet ist,
  ersetzt die Termine.
- Bei allen Konten und im Depot zählen Umbuchungsprognosen nicht als Einnahme
  oder Ausgabe.
- Das Endsaldo bleibt Startsaldo plus Prognose-Differenz. Auf einem einzelnen
  Konto verschiebt die offene Umbuchung deshalb das Endsaldo.

## Variable Kosten

- Rechtswischen bearbeitet eine variable Kosten, Linkswischen löscht sie.
- Ein Tipp öffnet die Buchungen, die ihr im gewählten Zeitraum zugeordnet sind.
  Ist ein Konto gewählt, nur die Buchungen dieses Kontos. Der Zeitraum ist
  derselbe wie in der Finanzansicht.
- Beim Anlegen lassen sich mehrere Konten wählen. Der Monatsbetrag wird
  gleichmäßig aufgeteilt, Restcents auf die ersten Konten. Ohne Auswahl gilt
  der Betrag für alle Konten außer Depot.
- Alle Konten zeigen den vollen Betrag. Ein einzelnes Konto zeigt nur seinen
  Anteil, und die Zeile nur, wenn das Konto beteiligt ist.
- Die gewählten Konten liegen nicht im Datenmodell, sondern in den lokalen
  Einstellungen. So bleibt eine bestehende Datendatei lesbar.
- Ist eine zugeordnete Ausgabe teilweise erstattet, zählt bei den variablen
  Kosten nur derselbe Anteil.

## Einkaufszettel

- In der Finanzansicht steht **Geplant** ohne Plus und in der Textfarbe.
  **Angewendet** ist rot.
- In der Liste bearbeitet Rechtswischen einen Eintrag, Linkswischen löscht ihn.
  Ein Tipp öffnet ihn ebenfalls.

## Home-Budget

Das Budget auf der Home-Seite ist nicht dieselbe Summe wie die Finanzansicht.
Ein Tipp öffnet die Aufschlüsselung, nicht die Finanzansicht. Dort stehen die
Einnahmen, die Prognosen und die Buchungen, aus denen Gesamt und Verbraucht
entstehen.

- Einnahmen sind nur fremde Eingänge. Die eigene IBAN, Dividenden, Zinsen und
  Rückerstattungen zählen nicht. Offene Gehaltsprognosen im Zeitraum zählen
  weiter.
- Verbrauch sind normale Ausgaben plus Aktienkäufe und Sparplan-Ausführungen.
  Eine erstattete Ausgabe zählt nur mit dem Rest. Andere Umbuchungen zählen
  nicht.
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
- Eine Überweisung auf ein eigenes Konto wird nicht mehr automatisch eine
  Umbuchung. Nach dem Import von Trade-Republic-PDF oder Sparkasse-CAMT, auch
  in der Einrichtung, erscheint ein Dialog.
- Unter „Mögliche Umbuchung“ stehen Zeilen mit gleichem Betrag, bekannter IBAN
  und Datum im Abstand von höchstens drei Tagen. Der Schalter ist aus. Nur wenn
  er an ist, werden die beiden Seiten eine Umbuchung und die doppelte Buchung
  auf dem anderen Konto entfällt.
- Unter „Ähnliche Buchungen“ stehen bereits vorhandene Treffer. Der Bereich ist
  eingeklappt. Fingerabdruck oder gleicher Betrag, ähnliches Datum und gleicher
  Titel oder gleiche IBAN gelten als doppelt und werden ausgelassen. Aufklappen
  und anhaken übernimmt eine Zeile trotzdem. Ausführungen im Wochenabstand
  liegen außerhalb des Drei-Tage-Fensters und bleiben eigene Buchungen.
- Ein erneuter Import ersetzt den vorherigen Auszug dieses Girokontos und baut
  das verknüpfte Depot neu auf.

Damit die Kursdifferenz bereits vollständig verkaufter Papiere stimmt, muss der
Auszug nach einer Regeländerung neu importiert werden.
