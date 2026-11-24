# Changes in 0.5.5

[English](#english) · [Deutsch](#deutsch)

## English

Lifify 0.5.5 is one release after 0.4.0. There was no separate 0.5.0
release. What changed in 0.4.0 is in [CHANGES-0.4.0.md](CHANGES-0.4.0.md).
The finance calculations are in [FINANCE.md](FINANCE.md). The displayed
version is 0.5.5.

### Overview

- Trade Republic sign-in with phone number, PIN, and confirmation in the
  Trade Republic app. The PDF statement import stays.
- Bank notices booked through Apple Shortcuts, with built-in templates for
  Sparkasse and Trade Republic.
- A reworked bank import and opening balance.
- All user data in one versioned database (schema V3) instead of
  UserDefaults. No more silent reset when the database cannot be opened.
- A complete backup, and a Health export with workouts and meals.
- The shop is locked while the wallet is negative.
- Much faster first opening of Finance and the depot.
- Real tests in Xcode instead of the in-app check page.
- The logic is split into four local Swift packages.

### Trade Republic sign-in

**Sign-in and security**

- Setup has an optional step after the PDF statement. The same sign-in is
  in Settings, Finance, Trade Republic. Statement upload and sign-in are two
  ways to update, shown as Option A and Option B.
- You enter the phone number and the PIN that opens the Trade Republic app,
  then confirm in that app. A leading 0 is sent as +49. Phone number and PIN
  are one step. The steps are popups in the app's colors. The sign-in popup
  opens after the keyboard is gone, so the first attempt stays on screen.
- The sign-in keeps one connection, so the confirmation belongs to the same
  login that then reads the depot. A loading popup holds the screen while the
  depot updates.
- **Neither the PIN nor the session is saved.** You sign in every time.
  Nothing runs on a timer, at launch, or when Finance opens.
- When Trade Republic refuses the first sign-in, Lifify says that no
  confirmation was sent. It does not sign in by itself.
- After a successful sign-in in setup, setup continues to the next step.
  The step can be skipped.

**What is imported**

- Every buy and sale in the history is booked, including sales between
  savings-plan executions and stocks that are no longer in the depot.
- Each purchase stays its own purchase with its own date, share count, and
  price. A position is not collapsed into one buy dated today.
- Savings plans come from the live plan and appear under fixed costs. A
  savings-plan execution is labeled as one and keeps its share count from its
  detail. A normal buy is not labeled as a savings plan.
- Dividends and interest are booked as Ertrag and Zinsen, the same categories
  as the PDF import, not as share purchases.
- Saveback buys shares and takes the money off the cash account.
- **Gifts:** Only a position with no purchase of that ISIN is a gift
  (Depotgeschenk). It keeps the date of the gift event, even when that event
  is only titled Geschenk. The booking shows the value of the shares; the
  lot has purchase price 0, so the gain since purchase equals the market
  value. Mixed gift and paid lots use only the paid cash in the average.
- **IPO:** A subscription is a Depotkauf on the Trade Republic cash account
  only. The shares appear in the depot once allocated; an allocated IPO is a
  purchase.
- A Faktor-Optionsschein moves cash, not the underlying stock.
- Crypto instruments with an XF identifier get a Yahoo price, so Bitcoin is
  not left at 0.
- Card payments, transfers, tax, bonuses, and referrals are booked with their
  statement types. Two card payments of the same amount on the same day both
  stay.
- A payment between two of your own accounts is a transfer and is booked
  once, even when the banks book it two or three days apart. The transfer
  keeps the earlier date.
- Booking notes include the event type, ISIN, quantity, and price.
- The live cash figure from the session sets the Trade Republic checking
  account and prefers total cash over available cash. Lifify asks for the
  cash balance only when the session has none.
- After the import, the existing price update runs, so prices are not left
  at zero.

**Updating and replacing**

- A later sign-in replaces the previous Trade Republic lots, holdings, and
  session bookings. Own-account transfers that did not come from that session
  stay.
- A position the session no longer returns is booked as a sale with the date
  and proceeds of that sale, then removed. Without a sale row the holding
  stays. A leftover quantity without a sale is not booked as a sale dated
  today; the lots are scaled to the live position.
- A lot whose price is nowhere near the average cost is removed on the next
  refresh.
- Cash movements before the first period of the main account stay in the
  ledger and sit outside that period.

**Extract (developer mode)**

- After sign-in, the last Trade Republic response is kept as a file: every
  timeline page, the activity log, gift details, and savings plans. The
  screen shows its size and a short preview.
- Save extract writes it into the Files app. An extract can be loaded or
  pasted back in (not a Lifify backup).

### Bank import and opening balance

- A duplicate is the same payee, amount, nearby date, and reference. Two CSV
  rows to the same payee on the same day with a different End-to-End
  reference stay two bookings. A re-import keeps a second row when its
  purpose is not already in the stored notes.
- Setup imports every bank row without duplicate detection. An import from
  Settings skips identical rows and older days whose booking count already
  matches. On the last booking day and on days with extra rows in the file,
  Lifify asks whether to import them. Missing second payments are selected
  by default.
- A pending Sparkasse row is not imported.
- A bank import asks for the current balance. The opening balance is set at
  the start of the first booking day, before that day's bookings, so that it
  plus all later bookings equals the entered cash. The cash is applied after
  you confirm the review. A later import skips old rows, adds new ones, and
  sets only one balance adjustment since the last import.
- The first salary period follows the main account and starts at its first
  booking or opening balance. An earlier Trade Republic booking does not
  start the period.
- In the current period, net worth is the live cash. In a past or future
  period it is that period's closing balance. Depot stays the market value.
- Each depot is linked to exactly one checking account.

### Shortcuts and notice templates

Create two shortcuts on the iPhone. iOS may still ask you to tap Run.

1. **Sparkasse.** When a Sparkasse notification arrives, run **Bankmitteilung
   buchen** with **Konto** set to Sparkasse and **Mitteilung** set to the
   notification text.
2. **Trade Republic.** The same for a Trade Republic notification, with
   **Konto** set to Trade Republic.

- The same call is `lifify://notice?account=sparkasse&text=…`. For Trade
  Republic the account is `traderepublic`. The URL scheme is open on purpose,
  so Shortcuts can use it.
- Lifify reads the amount, the direction, and a short title, and books on that
  checking account. “Überweisung erhalten” from Trade Republic is a transfer
  from the main account, not income. “ausgegeben” is a card expense.
- The same transfer is not booked twice within three days. The same account,
  amount, and direction within six hours become one booking.
- **Templates** (Settings, Finance, Shortcuts): one per checking account, with
  an example notice and whether it is an expense, income, or transfer.
  Built-in templates cover the Sparkasse balance alert (debit and credit) and
  Trade Republic buys, sales, savings plans, dividends, card payments, and
  cancelled orders. Each has an on/off switch. Built-in templates can be
  edited or deleted; a deleted one does not come back. Your own templates win.
- A buy, sale, or savings plan from a notice moves cash to or from the depot.
  Shares come with the next Trade Republic import. A dividend books the euro
  amount as income. A cancelled order books nothing.

### Setup

- Setup can restore the entire app from one JSON file, or individual areas
  (Finance, Challenges, Health). Several part files can be picked at once.
- If setup is not finished, it starts again at the first step after every
  launch or update. Partial data from the unfinished setup is discarded. Every
  step after the first has Back.
- Setup can add a depot before Trade Republic. Only Trade Republic can be
  chosen; other brokers are marked not supported. Choosing it creates a
  secondary checking account linked to the depot.
- Settings, Finance lists Accounts, Bank import, Shortcuts, Trade Republic,
  and Portfolio, in that order.

### Data storage

- All user data now lives in one database, opened through a versioned
  migration plan (schema V3).
- On the first launch of 0.5.5, data moves once from UserDefaults into the
  database: portfolio lots, savings plans, closed positions, market symbols,
  previous closes, purchase dates, portfolio links, refund and income links,
  forecast skips, period links and rejected matches, expense group links,
  transfer forecasts, Shortcuts templates, budget accounts, bank import
  cursors, streak states, abstinence data, challenge minutes and event
  members, workout links, pins, custom categories, reward policies, reminder
  and event repeats, icons, and meals. Old keys are deleted only after the new
  rows are saved. Unreadable data stays untouched and the move runs again on
  the next launch.
- Settings such as language, theme, multipliers, body data, and briefing times
  stay in UserDefaults.
- **No silent reset:** A finished app that cannot open its database shows the
  error and offers to restore a backup of the entire app. Only that choice
  moves the old store into an archive folder; a failed restore puts it back.
- A challenge has one source for its groups. The direct event link and the
  event member list stay separate on purpose, because only the direct link
  sets the streak quota.

### Backup

- The backup now carries everything that was reset on restore but never
  exported: transfer forecasts, refund links, forecast skips, period links and
  rejected matches, Shortcuts templates, variable budget accounts, bank
  import cursors, default trade settings, pinned challenges and groups, event
  offers, the Fast Food reward link, and display and briefing choices.
- The finance export also carries lots, savings plans, closed positions, and
  the depot link.
- A Finance or Challenges file carries only its own area. Device-wide choices
  are in the entire-app backup. Older backup files still restore and leave
  newer values as they are. Restoring no longer creates a second Fast Food
  reward.
- **Health:** Export training is now Export health and carries workouts and
  meals. On restore, fast-food coins are kept in step with the meals. Delete
  training is now Delete health and also removes meals and meal photos, with
  their fast-food charges refunded.
- **Not included:** meal and profile photos, exercise images, price caches,
  developer and setup state, the Trade Republic extract, and the Keychain.

### Shop lock

- While the wallet is below 0, rewards and streak freezes cannot be bought,
  including free ones. The shop shows a red notice with the balance and the
  missing coins; buy buttons read Locked. At 0 or above, the shop opens again.
- The automatic fast-food purchase still books while the shop is locked.
  Earning coins, unchecking challenges, and editing rewards stay available.

### Performance

- Finance periods are reused until stored data changes. Fixed-cost matching
  looks only at bookings of the same day. Link lookups no longer rebuild for
  every booking. The depot sorts by values computed once. The Finance tab no
  longer hashes every booking on each frame.
- Measured in a release build in the iPhone 17 simulator with 5,000 bookings,
  30 holdings, 1,200 lots, and 365 prices per holding (median of three first
  opens):

| Screen | Before | After |
| --- | ---: | ---: |
| Finance overview | 8.4 s | 1.4 s |
| Depot | 36.2 s | 1.5 s |

- These are simulator values with test data. Results are unchanged.
- Changing account or period shows a loading state on the whole Finance page.
  Returning from the background shows a loading screen until input works
  again; it also covers the calendar sync.

### Tests

- `LififyTests` has real rule tests in Swift Testing, with an in-memory
  database and a private UserDefaults suite. They cover coins and the wallet,
  streaks, freezes and the multiplier, abstinence payouts, time slots and
  groups, workout links, due dates, finance balances, forecasts, the
  savings-plan forecast, backup coverage, and the data move.
- The in-app check page is gone. 99 of its 108 checks became tests; the rest
  only compared UI text or constants with themselves. Four outdated check
  conditions that failed before were corrected; none was an app bug.
- **Not covered yet:** paths that write to the iOS calendar or schedule
  notifications (calendar rewrite after check-off, `WorkoutCalendarSync`,
  abstinence bonuses and relapse), the full-app and Health restore, and the
  real Trade Republic sign-in.

### Packages

- The logic is in four local packages under `Packages`: `LififyCore`
  (shared models and storage), `LififyFinance` (with Trade Republic),
  `LififyChallenges`, and `LififyHealth`. The app keeps the views,
  navigation, backup, and the wiring between packages.
- Health may use Challenges. Challenges reaches meals only through a small
  hook that the app connects at launch.

### Open questions

- Should a shortcut create the Trade Republic checking account when it is
  missing?
- Should the six-hour window be longer when the bank notice arrives the next
  morning?
- Should a market price from the session be stored, or should the existing
  price update stay the only source?

## Deutsch

Lifify 0.5.5 ist ein Release nach 0.4.0. Ein eigenes Release 0.5.0 gab es
nicht. Was sich in 0.4.0 geändert hat, steht in
[CHANGES-0.4.0.md](CHANGES-0.4.0.md). Die Finanzrechnung steht in
[FINANCE.md](FINANCE.md). Die angezeigte Version ist 0.5.5.

### Überblick

- Anmeldung bei Trade Republic mit Telefonnummer, PIN und Bestätigung in der
  Trade-Republic-App. Der PDF-Import bleibt.
- Bankmitteilungen werden über Apple Kurzbefehle gebucht, mit mitgelieferten
  Vorlagen für Sparkasse und Trade Republic.
- Überarbeiteter Bankimport und Eröffnungssaldo.
- Alle Nutzerdaten liegen in einer versionierten Datenbank (Schema V3) statt
  in UserDefaults. Kein stilles Zurücksetzen mehr, wenn die Datenbank sich
  nicht öffnen lässt.
- Vollständiges Backup und ein Gesundheits-Export mit Trainings und
  Mahlzeiten.
- Der Shop ist gesperrt, solange das Wallet im Minus ist.
- Finanzen und Depot öffnen beim ersten Mal deutlich schneller.
- Echte Tests in Xcode statt der In-App-Prüfseite.
- Die Logik ist auf vier lokale Swift Packages aufgeteilt.

### Anmeldung bei Trade Republic

**Anmeldung und Sicherheit**

- Die Einrichtung hat nach dem PDF-Auszug einen optionalen Schritt. Dieselbe
  Anmeldung liegt unter Einstellungen, Finanzen, Trade Republic.
  Kontoauszug hochladen und Anmelden sind zwei Update-Wege, als Variante A und
  Variante B.
- Du gibst Telefonnummer und die PIN ein, mit der du die Trade-Republic-App
  öffnest, und bestätigst in der App. Eine 0 am Anfang geht als +49 mit.
  Telefonnummer und PIN sind ein Schritt. Die Schritte sind Pop-ups in den
  Farben der App. Das Anmelde-Pop-up öffnet erst, wenn die Tastatur weg ist,
  damit der erste Versuch auf dem Schirm bleibt.
- Die Anmeldung bleibt auf einer Verbindung, damit die Bestätigung zu
  derselben Anmeldung gehört, die danach das Depot liest. Ein Lade-Pop-up hält
  den Bildschirm, solange das Depot aktualisiert wird.
- **Weder PIN noch Sitzung werden gespeichert.** Du meldest dich jedes Mal neu
  an. Nichts läuft mit Timer, beim Start oder beim Öffnen von Finanzen.
- Lehnt Trade Republic die erste Anmeldung ab, sagt Lifify, dass keine
  Bestätigung geschickt wurde. Es meldet sich nicht von allein an.
- Nach erfolgreicher Anmeldung geht die Einrichtung zum nächsten Schritt.
  Der Schritt lässt sich überspringen.

**Was übernommen wird**

- Jeder Kauf und Verkauf aus der Historie wird gebucht, auch ein Verkauf
  zwischen Sparplan-Ausführungen und Aktien, die nicht mehr im Depot liegen.
- Jeder Kauf bleibt ein eigener Kauf mit eigenem Datum, eigener Stückzahl und
  eigenem Kurs. Eine Position wird nicht zu einem Kauf mit heutigem Datum
  zusammengezogen.
- Sparpläne kommen aus dem laufenden Plan und stehen unter den Fixkosten.
  Eine Sparplan-Ausführung heißt Sparplan und behält die Stückzahl aus ihrem
  Detail. Ein normaler Kauf heißt nicht Sparplan.
- Dividenden und Zinsen werden als Ertrag und Zinsen gebucht, wie beim
  PDF-Import, nicht als Aktienkauf.
- Saveback kauft Stücke und geht vom Girokonto ab.
- **Geschenke:** Nur eine Position ohne Kauf dieser ISIN ist ein Geschenk
  (Depotgeschenk). Sie behält das Datum des Geschenk-Ereignisses, auch wenn es
  nur Geschenk heißt. Die Buchung zeigt den Wert der Stücke; das Stück hat
  den Kaufkurs 0, damit die Veränderung seit Kauf dem Marktwert entspricht.
  Gemischte Geschenk- und Kaufstücke rechnen nur das bezahlte Geld in den
  Einstand.
- **IPO:** Eine Zeichnung ist ein Depotkauf nur auf dem
  Trade-Republic-Girokonto. Die Stücke liegen erst nach der Zuteilung im
  Depot; eine zugeteilte IPO ist ein Kauf.
- Ein Faktor-Optionsschein bewegt nur Cash, nicht die Aktie darunter.
- Krypto-Instrumente mit XF-Kennung bekommen einen Yahoo-Kurs, Bitcoin bleibt
  nicht bei 0.
- Kartenzahlungen, Überweisungen, Steuern, Boni und Empfehlungen werden mit
  ihren Auszugstypen gebucht. Zwei Kartenzahlungen am selben Tag mit demselben
  Betrag bleiben beide.
- Eine Zahlung zwischen zwei eigenen Konten ist eine Umbuchung und wird nur
  einmal gebucht, auch wenn die Banken sie zwei oder drei Tage auseinander
  buchen. Die Umbuchung behält das frühere Datum.
- In den Buchungsdetails stehen Ereignistyp, ISIN, Stück und Kurs.
- Der Live-Cash aus der Sitzung setzt das Trade-Republic-Girokonto und nimmt
  den Total-Cash vor dem verfügbaren Cash. Lifify fragt nur nach dem
  Kontostand, wenn die Sitzung keinen liefert.
- Nach dem Import läuft die bisherige Kursaktualisierung, damit die Kurse
  nicht auf null stehen.

**Aktualisieren und Ersetzen**

- Eine spätere Anmeldung ersetzt die bisherigen Trade-Republic-Stücke,
  Bestände und Sitzungsbuchungen. Umbuchungen zwischen eigenen Konten, die
  nicht aus dieser Sitzung kamen, bleiben.
- Eine Position, die die Sitzung nicht mehr liefert, wird mit Datum und Erlös
  des Verkaufs als Verkauf gebucht und dann entfernt. Ohne Verkaufszeile
  bleibt der Bestand. Ein Rest ohne Verkauf wird nicht als Verkauf von heute
  gebucht; die Stücke werden auf den Live-Stand skaliert.
- Ein Stück, dessen Kurs nicht zum Einstand passt, verschwindet beim nächsten
  Aktualisieren.
- Geldbewegungen vor dem ersten Zeitraum des Hauptkontos bleiben in der Liste
  und liegen außerhalb dieses Zeitraums.

**Auszug (Entwicklermodus)**

- Nach der Anmeldung liegt die letzte Trade-Republic-Antwort als Datei vor:
  alle Timeline-Seiten, das Aktivitätslog, Geschenk-Details und Sparpläne. Der
  Bildschirm zeigt Größe und eine kurze Vorschau.
- Auszug speichern schreibt sie in die Dateien-App. Ein Auszug lässt sich
  wieder laden oder einfügen (keine Lifify-Sicherung).

### Bankimport und Eröffnungssaldo

- Eine Doppelung ist derselbe Empfänger, derselbe Betrag, ein nahes Datum und
  dieselbe Referenz. Zwei CSV-Zeilen an denselben Empfänger am selben Tag mit
  unterschiedlicher End-to-End-Referenz bleiben zwei Buchungen. Ein erneuter
  Import behält eine zweite Zeile, wenn ihr Verwendungszweck noch nicht in den
  gespeicherten Notizen steht.
- Die Einrichtung übernimmt jede Bankzeile ohne Duplikaterkennung. Ein Import
  aus den Einstellungen überspringt identische Zeilen und ältere Tage, deren
  Anzahl schon stimmt. Am letzten Buchungstag und an Tagen mit zusätzlichen
  Zeilen fragt Lifify nach. Fehlende Zweit-Zahlungen sind vorausgewählt.
- Ein vorgemerkter Sparkassen-Umsatz wird nicht importiert.
- Ein Bankimport fragt nach dem aktuellen Kontostand. Der Eröffnungssaldo
  steht am Anfang des ersten Buchungstags, vor dessen Buchungen, so dass er
  plus alle späteren Buchungen den angegebenen Stand ergibt. Der Stand wird
  erst nach dem Übernehmen gesetzt. Ein späterer Import überspringt alte
  Zeilen, übernimmt neue und setzt nur eine Saldo-Korrektur seit dem letzten
  Import.
- Der erste Gehaltszeitraum folgt dem Hauptkonto und beginnt mit dessen
  erster Buchung oder Eröffnungssaldo. Eine frühere Trade-Republic-Buchung
  startet den Zeitraum nicht.
- Im aktuellen Zeitraum ist das Gesamtvermögen der Live-Cash. In einem
  vergangenen oder künftigen Zeitraum ist es dessen Endsaldo. Depot bleibt der
  Marktwert.
- Jedes Depot hängt an genau einem Girokonto.

### Kurzbefehle und Mitteilungs-Vorlagen

Lege auf dem iPhone zwei Kurzbefehle an. iOS kann trotzdem nach Ausführen
fragen.

1. **Sparkasse.** Kommt eine Mitteilung der Sparkasse, führe
   **Bankmitteilung buchen** aus, mit **Konto** Sparkasse und **Mitteilung**
   gleich dem Text der Mitteilung.
2. **Trade Republic.** Dasselbe für Trade Republic, mit **Konto** Trade
   Republic.

- Derselbe Aufruf ist `lifify://notice?account=sparkasse&text=…`. Bei Trade
  Republic ist das Konto `traderepublic`. Das URL-Schema ist bewusst offen,
  damit Kurzbefehle es nutzen können.
- Lifify liest Betrag, Richtung und einen kurzen Titel und bucht auf dieses
  Girokonto. „Überweisung erhalten“ von Trade Republic ist eine Umbuchung vom
  Hauptkonto, keine Einnahme. „ausgegeben“ ist eine Kartenausgabe.
- Dieselbe Umbuchung wird innerhalb von drei Tagen nicht doppelt gebucht.
  Dasselbe Konto, derselbe Betrag und dieselbe Richtung innerhalb von sechs
  Stunden werden eine Buchung.
- **Vorlagen** (Einstellungen, Finanzen, Kurzbefehle): eine pro Girokonto,
  mit Beispielmitteilung und ob es Ausgabe, Einnahme oder Umbuchung ist.
  Mitgeliefert sind Vorlagen für den Sparkassen-Umsatzwecker (Abbuchung und
  Gutschrift) und für Käufe, Verkäufe, Sparpläne, Dividenden,
  Kartenzahlungen und stornierte Orders bei Trade Republic. Jede hat einen
  Schalter. Mitgelieferte Vorlagen lassen sich bearbeiten oder löschen; eine
  gelöschte kommt nicht zurück. Eigene Vorlagen haben Vorrang.
- Kauf, Verkauf und Sparplan aus einer Mitteilung bewegen Geld zum oder vom
  Depot. Die Stücke kommen mit dem nächsten Trade-Republic-Import. Eine
  Dividende bucht den Euro-Betrag als Ertrag. Eine stornierte Order bucht
  nichts.

### Einrichtung

- Die Einrichtung lädt die ganze App aus einer JSON-Datei oder einzelne
  Bereiche (Finanzen, Challenges, Gesundheit). Mehrere Teildateien gehen auf
  einmal.
- Ist die Einrichtung nicht abgeschlossen, beginnt sie nach jedem Start oder
  Update wieder beim ersten Schritt. Teildaten der unfertigen Einrichtung
  verfallen. Ab dem zweiten Schritt gibt es Zurück.
- Vor Trade Republic kann ein Depot angelegt werden. Nur Trade Republic ist
  wählbar, andere Broker sind als nicht unterstützt markiert. Die Auswahl
  legt ein Girokonto als Nebenkonto an und verknüpft das Depot damit.
- Unter Einstellungen, Finanzen stehen Konten, Bankimport, Kurzbefehle,
  Trade Republic und Depot, in dieser Reihenfolge.

### Datenspeicher

- Alle Nutzerdaten liegen jetzt in einer Datenbank, die über einen
  versionierten Migrationsplan öffnet (Schema V3).
- Beim ersten Start von 0.5.5 ziehen Daten einmalig von UserDefaults in die
  Datenbank um: Depot-Lots, Sparpläne, geschlossene Positionen, Marktsymbole,
  Vortageskurse, Kaufdaten, Depot-Verknüpfungen, Erstattungs- und
  Einkommens-Verknüpfungen, übersprungene Prognosen, Zeitraum-Verknüpfungen
  und abgelehnte Treffer, Ausgabengruppen-Zuordnungen, Umbuchungsprognosen,
  Kurzbefehl-Vorlagen, Budget-Konten, Bankimport-Stände, Streak-Zustände,
  Abstinenzdaten, Challenge-Minuten und Termin-Mitglieder, Workout-Links,
  Pins, eigene Kategorien, Einlöse-Regeln, Wiederholungen von Erinnerungen
  und Terminen, Symbole und Mahlzeiten. Alte Schlüssel werden erst gelöscht,
  wenn die neuen Zeilen gespeichert sind. Unlesbare Daten bleiben
  unangetastet, der Umzug läuft beim nächsten Start erneut.
- Einstellungen wie Sprache, Design, Multiplikatoren, Körperdaten und
  Briefing-Zeiten bleiben in UserDefaults.
- **Kein stilles Zurücksetzen:** Kann eine fertig eingerichtete App ihre
  Datenbank nicht öffnen, zeigt sie den Fehler und bietet an, eine Sicherung
  der gesamten App wiederherzustellen. Erst diese Wahl verschiebt den alten
  Speicher in einen Archivordner; ein fehlgeschlagener Restore legt ihn
  zurück.
- Eine Challenge hat eine Quelle für ihre Gruppen. Die direkte
  Terminverknüpfung und die Mitgliederliste des Termins bleiben bewusst
  getrennt, weil nur die direkte Verknüpfung das Streak-Soll bestimmt.

### Backup

- Das Backup enthält jetzt alles, was beim Wiederherstellen zurückgesetzt,
  aber nie exportiert wurde: Umbuchungsprognosen, Erstattungs-Verknüpfungen,
  übersprungene Prognosen, Zeitraum-Verknüpfungen und abgelehnte Treffer,
  Kurzbefehl-Vorlagen, Konten variabler Budgets, Bankimport-Stände,
  Handelsvorgaben, angepinnte Challenges und Gruppen, Termin-Angebote, die
  Verknüpfung der Fast-Food-Belohnung sowie Anzeige- und
  Briefing-Einstellungen.
- Der Finanzexport enthält auch Depotstücke, Sparpläne, geschlossene
  Positionen und die Depotverknüpfung.
- Eine Finanz- oder Challenge-Datei enthält nur ihren Bereich. Geräteweite
  Einstellungen stehen im Gesamt-Backup. Ältere Dateien lassen sich weiter
  einspielen und lassen neuere Werte unverändert. Eine Wiederherstellung legt
  keine zweite Fast-Food-Belohnung mehr an.
- **Gesundheit:** Aus „Training exportieren“ wird „Gesundheit exportieren“
  mit Trainings und Mahlzeiten. Beim Einspielen bleiben die Fast-Food-Coins
  passend zu den Mahlzeiten. Aus „Training löschen“ wird „Gesundheit
  löschen“; es entfernt auch Mahlzeiten und Mahlzeitenfotos und erstattet
  deren Fast-Food-Käufe.
- **Nicht enthalten:** Mahlzeiten- und Profilfotos, Übungsbilder,
  Kurs-Caches, Entwickler- und Einrichtungszustand, der
  Trade-Republic-Auszug und der Schlüsselbund.

### Shop-Sperre

- Solange das Wallet unter 0 liegt, lassen sich Belohnungen und
  Streak-Freezes nicht kaufen, auch kostenlose nicht. Der Shop zeigt einen
  roten Hinweis mit Guthaben und fehlenden Coins; die Kaufknöpfe heißen
  Gesperrt. Ab 0 ist der Shop wieder offen.
- Der automatische Fast-Food-Kauf bucht auch bei gesperrtem Shop. Coins
  verdienen, Haken entfernen und Belohnungen bearbeiten bleiben möglich.

### Performance

- Finanzzeiträume werden wiederverwendet, bis sich gespeicherte Daten ändern.
  Der Fixkosten-Abgleich prüft nur Buchungen desselben Tages.
  Verknüpfungen werden nicht mehr für jede Buchung neu aufgebaut. Das Depot
  sortiert nach einmal berechneten Werten. Der Finanzen-Tab hasht nicht mehr
  bei jedem Bild jede Buchung.
- Gemessen im Release-Build im iPhone-17-Simulator mit 5.000 Buchungen,
  30 Positionen, 1.200 Lots und 365 Kursen je Position (Median aus drei
  ersten Aufrufen):

| Bildschirm | Vorher | Nachher |
| --- | ---: | ---: |
| Finanzübersicht | 8,4 s | 1,4 s |
| Depot | 36,2 s | 1,5 s |

- Es sind Simulatorwerte mit Testdaten. Die Ergebnisse bleiben gleich.
- Beim Wechsel von Konto oder Zeitraum zeigt die ganze Finanzen-Seite den
  Ladezustand. Nach der Rückkehr aus dem Hintergrund liegt ein Ladebildschirm
  über der App, bis Eingaben wieder gehen; er deckt auch den
  Kalender-Abgleich ab.

### Tests

- `LififyTests` enthält echte Regeltests mit Swift Testing, mit
  In-Memory-Datenbank und eigener UserDefaults-Suite. Sie decken Coins und
  Wallet, Streaks, Freezes und Multiplikator, Abstinenz-Auszahlungen,
  Zeit-Slots und Gruppen, Workout-Verknüpfungen, Fälligkeit, Finanzsalden,
  Prognosen, die Sparplan-Prognose, die Backup-Abdeckung und den Datenumzug
  ab.
- Die In-App-Prüfseite ist entfernt. 99 der 108 Prüfungen wurden Tests, der
  Rest verglich nur UI-Texte oder Konstanten mit sich selbst. Vier veraltete
  Bedingungen, die vorher fehlschlugen, wurden korrigiert; keine war ein
  App-Fehler.
- **Noch nicht abgedeckt:** Wege, die in den iOS-Kalender schreiben oder
  Mitteilungen planen (Termin-Umschreiben nach dem Abhaken,
  `WorkoutCalendarSync`, Abstinenz-Boni und Rückfall), die Wiederherstellung
  von Gesamt- und Gesundheits-Backup und die echte Trade-Republic-Anmeldung.

### Packages

- Die Logik liegt in vier lokalen Packages unter `Packages`: `LififyCore`
  (gemeinsame Modelle und Speicher), `LififyFinance` (mit Trade Republic),
  `LififyChallenges` und `LififyHealth`. Die App behält Views, Navigation,
  Backup und das Zusammenschalten der Packages.
- Health darf Challenges nutzen. Challenges erreicht Mahlzeiten nur über eine
  kleine Schnittstelle, die die App beim Start verbindet.

### Offene Fragen

- Soll ein Kurzbefehl das Trade-Republic-Girokonto anlegen, wenn es fehlt?
- Soll das Sechs-Stunden-Fenster länger sein, wenn die Bankmitteilung erst am
  nächsten Morgen kommt?
- Soll ein Kurs aus der Sitzung gespeichert werden, oder bleibt die bisherige
  Kursaktualisierung die einzige Quelle?
