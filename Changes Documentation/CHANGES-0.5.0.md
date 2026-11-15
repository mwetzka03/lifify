# Changes in 0.5.0

[English](#english) · [Deutsch](#deutsch)

## English

Lifify 0.5.0 adds a manual Trade Republic sign-in and a way for the Shortcuts
app to book a Sparkasse or Trade Republic notice. The finance calculations are
unchanged and stay in [FINANZEN.md](../FINANZEN.md). What changed in 0.4.0 is in
[CHANGES-0.4.0.md](CHANGES-0.4.0.md). The displayed version is 0.5.0.

### Setup

Setup can restore the entire app from one JSON file, or only one area:
Finance, Challenges, or Training. You can pick several of those part files at
once.

### Trade Republic, by hand

Setup has one more optional step, after the PDF statement. You enter the phone
number and the PIN that opens the Trade Republic app, then confirm in that app.
The steps are popups in the same colors as the rest of the app. Phone number and PIN are one step, and a loading popup holds the screen while the depot updates. The sign-in keeps one connection, so the confirmation in the app belongs to the same login that then reads the depot.
A leading 0 is sent as +49. A position the session no longer returns is booked as a sale, with the date and proceeds from that sale, and then removed. When the session has no sale row, the holding stays. A leftover quantity without a sale in the history is not booked as a sale dated today; the lots are scaled to the live position instead.
Each purchase from the sign-in stays its own purchase, with its own date and share count. A position is not collapsed into one buy dated today. A savings plan comes from the live plan, and it shows under fixed costs. A normal buy is not labeled as a savings plan. A later purchase of a stock already held stays its own purchase, with its own share count, date, and price, on the stock and as its own booking. A savings-plan execution is labeled as a savings plan, and the plan keeps the rhythm of its last execution. Bank import and the Trade Republic statement live under Finance. Each portfolio is linked to one checking account. A duplicate is the same payee, the same amount, a nearby date, and the same reference. Two CSV rows to the same payee on the same day with a different End-to-End reference stay two bookings. A re-import keeps the second row when its purpose is not already in the stored notes. Setup imports every bank row without duplicate detection. An import from Settings skips an identical row and offers a similar row for review. A pending Sparkasse row is not imported. The first salary period follows the main account and is clipped to that first booking or opening balance, so an earlier Trade Republic booking does not start the period. A bank import asks for the current balance, works the opening backwards, and stores that current amount as the last balance adjustment when the computed cash still differs. When one cash account is selected, net worth is that live stand. The live cash figure from a Trade Republic session is pinned the same way and prefers total cash over available cash. Save extract sits only in developer mode. After a successful Trade Republic sign-in, setup continues to the next step. Statement upload and sign-in are Option A and Option B, each with an icon. A different shop is imported. Setup can add a portfolio before Trade Republic. Only Trade Republic can be chosen. The others are marked not supported. Choosing it creates a secondary checking account linked to the portfolio. The next page offers the PDF statement and sign-in together. Card payments and other
cash movements are booked there too. The existing price update then runs, so the
prices are not left at zero. After sign-in, the last Trade Republic response is kept as a file. Auszug speichern writes it into the Files app, the same way as Export finance. The extract is not stored in Settings. The screen shows the size and a short preview, not the whole timeline. The history is read page by page, including the activity log, and a savings execution keeps the share count from its detail. Dividends and interest are booked as Ertrag and Zinsen, the same categories as the PDF import, and not as share purchases. A Saveback execution buys those shares and takes that money off the cash account. A gift of shares is Depotgeschenk and does not. Only a position with no purchase of that ISIN is a gift, so a later NVIDIA buy does not invent gift lots. Gift dates come from gift events, not from a card check, a savings-plan row, or another Saveback. The gift booking shows the value of those shares, not 0 €. The lot still has purchase price 0. The live cash figure from the session sets the Trade Republic checking account. When the account or period changes, the whole Finance page shows loading, including forecasts and bookings. When the app returns from the background, a loading screen covers every tab until input works again. The sign-in popup is its own window after the keyboard is gone, so the first attempt stays on screen. The Finance tab no longer hashes every booking title and note on each frame. A position with no purchase of that ISIN in the history is a gift, not an opening buy, even when another stock was bought at a similar price. The gift keeps the date of the gift event, including when that event is only titled Geschenk and does not name the stock. It shows as Depotgeschenk in the bookings, and has a purchase price of 0, so since-purchase P&L is the market value. Mixed gift and paid lots use only the cash that was paid in the average. A later sign-in replaces the previous Trade Republic lots, holdings, and session bookings; own-account transfers that did not come from that session stay. An IPO subscription is a Depotkauf on the Trade Republic cash account only. The shares are not in the depot until the IPO is allocated. An allocated IPO is a purchase. A Faktor Optionsschein moves cash, not the underlying stock. Two card payments of the same amount on the same day both stay. Cash movements before the first period of the main account stay in the ledger and sit outside that period. Lifify asks for the Trade Republic cash balance on that day only when the session has no cash figure. A payment between two of your own accounts is a transfer, and the same payment is not booked twice, including when the banks book it two or three days apart. The surviving transfer keeps the earlier date. Card payments, transfers, tax, bonuses, and referrals use those statement types too. Every buy and sale in the history is booked, including a sale that sits between savings-plan lots and a stock that is no longer in the depot. Crypto instruments with an XF identifier get a Yahoo price, so Bitcoin is not left at 0. Booking notes include the Trade Republic event type, ISIN, quantity, and price. A lot whose price is nowhere near the average cost is removed on the next refresh. The extract keeps every timeline page, the activity log, the gift details, and the savings plans, not one clipped page. Save extract writes that file into the Files app. You can load or paste a Trade Republic extract back in, not a Lifify JSON backup. The finance export under Data includes lots, savings plans, closed positions, and the depot link, not only accounts and holdings. The PDF import stays. You can skip the step.

Finance in Settings lists Accounts, then Bank import, then Trade Republic as one section with statement upload and sign-in as two update paths, then Portfolio last. The same sign-in is there. The session is not saved, so there is
no refresh from a stored session. Sign in each time. Nothing runs on a timer, at
launch, or when Finance opens. The PIN is not saved. A first sign-in that Trade
Republic refuses says that no confirmation was sent. It does not sign in by
itself.

This environment reached `POST /api/v2/auth/web/login` with the headers the web
app sends. A number that is not a phone number came back as HTTP 400
`NUMBER_INVALID`, before any session existed. A real sign-in still needs your
phone, your PIN, and the confirmation in the Trade Republic app. That step was
not run here, and no holdings were invented.

### Shortcuts

Create two shortcuts on the iPhone. iOS may still ask you to tap Run.

1. **Sparkasse.** When a notification from Sparkasse arrives, run **Bankmitteilung buchen**. Set **Konto** to Sparkasse and **Mitteilung** to the notification text.
2. **Trade Republic.** Do the same for a Trade Republic notification, with **Konto** set to Trade Republic.

The same call is `lifify://notice?account=sparkasse&text=` with the notification
text in `text`. For Trade Republic the account is `traderepublic`. Lifify reads
the amount, the direction, and a short title, then books it on that checking
account. A Trade Republic notice that a transfer was received is an own-account
transfer from the main checking account, not income. “ausgegeben” is a card
expense on Trade Republic. The same transfer is not booked twice within three
days. The same account, amount, and direction inside six hours becomes one
booking.

The new behavior has a unit check and an integration check. The checks do not
write user data.

This environment has no Xcode, so the project was not built and the checks were
not executed. Swift braces were balanced locally.

### Ideas, not built

- Should a shortcut create the Trade Republic checking account when it is missing?
- Should the six-hour window be longer when the bank notice arrives the next morning?
- Should a market price from the session be stored, or should the existing price update stay the only source?

## Deutsch

Lifify 0.5.0 ergänzt eine manuelle Anmeldung bei Trade Republic und einen Weg,
mit dem die Kurzbefehle-App eine Sparkassen- oder Trade-Republic-Mitteilung
bucht. Die Finanzrechnung ist unverändert und bleibt in
[FINANZEN.md](../FINANZEN.md). Was sich in 0.4.0 geändert hat, steht in
[CHANGES-0.4.0.md](CHANGES-0.4.0.md). Die angezeigte Version ist 0.5.0.

### Einrichtung

Die Einrichtung lädt die ganze App aus einer JSON-Datei, oder nur einen
Bereich: Finanzen, Challenges oder Training. Mehrere Teildateien gehen auf
einmal.

### Trade Republic, von Hand

Die Einrichtung hat einen weiteren optionalen Schritt, nach dem PDF-Auszug. Du
gibst Telefonnummer und die PIN ein, mit der du die Trade-Republic-App öffnest,
und bestätigst in der App. Die Schritte sind Pop-ups in denselben Farben wie der Rest der App. Telefonnummer
und PIN sind ein Schritt, und ein Lade-Popup hält den Bildschirm, solange das Depot
aktualisiert wird. Die Anmeldung bleibt auf einer Verbindung, damit die Bestätigung
in der App zu derselben Anmeldung gehört, die danach das Depot liest. Eine 0 am Anfang geht als
+49 mit. Eine Position, die die Sitzung nicht mehr liefert, wird als Verkauf gebucht,
mit Datum und Erlös, und verschwindet danach. Fehlt die Verkaufszeile, bleibt der
Bestand. Ein Rest ohne Verkauf in der Historie wird nicht als Verkauf von heute
gebucht; die Stücke werden auf den Live-Stand skaliert.
Jeder Kauf aus der Anmeldung bleibt ein eigener Kauf, mit eigenem Datum und eigener Stückzahl. Eine Position wird nicht zu einem Kauf mit heutigem Datum zusammengezogen. Ein Sparplan kommt aus dem laufenden Plan und steht unter den Fixkosten. Ein normaler Kauf heißt nicht Sparplan. Ein späterer Kauf einer Aktie, die schon im Depot liegt, bleibt ein eigener Kauf, mit eigener Stückzahl, eigenem Datum und eigenem Kurs, an der Aktie und als eigene Buchung. Eine Sparplan-Ausführung heißt Sparplan, und der Plan übernimmt den Rhythmus der letzten Ausführung. Bankimport und der Trade-Republic-Auszug liegen unter Finanzen. Jedes Depot hängt an genau einem Girokonto. Eine Doppelung ist derselbe Empfänger, derselbe Betrag, ein nahes Datum und dieselbe Referenz. Zwei CSV-Zeilen an denselben Empfänger am selben Tag mit unterschiedlicher End-to-End-Referenz bleiben zwei Buchungen. Ein erneuter Import behält die zweite Zeile, wenn ihr Verwendungszweck noch nicht in den gespeicherten Notizen steht. Die Einrichtung übernimmt jede Bankzeile ohne Duplikaterkennung. Ein Import aus den Einstellungen überspringt eine identische Zeile und bietet eine ähnliche zur Prüfung an. Ein vorgemerkter Sparkassen-Umsatz wird nicht importiert. Der erste Gehaltszeitraum folgt dem Hauptkonto und wird auf dessen erste Buchung oder Eröffnungssaldo geschnitten, damit eine frühere Trade-Republic-Buchung den Zeitraum nicht startet. Ein Bankimport fragt nach dem aktuellen Kontostand, rechnet den Startsaldo zurück und speichert diesen aktuellen Betrag als letzte Saldo-Korrektur, wenn der gerechnete Cash-Stand danach nicht passt. Ist ein Girokonto gewählt, ist Gesamtvermögen dieser aktuelle Stand. Der Live-Cash-Stand einer Trade-Republic-Sitzung wird genauso gesetzt und nimmt den Total-Cash vor dem verfügbaren Cash. Auszug speichern steht nur im Entwicklermodus. Nach einer erfolgreichen Trade-Republic-Anmeldung geht die Einrichtung in den nächsten Schritt. Kontoauszug hochladen und Anmelden sind Variante A und Variante B, jeweils mit Icon. Ein anderer Laden wird importiert. Vor Trade Republic kann ein Depot angelegt werden. Nur Trade Republic ist wählbar. Die anderen Broker sind als nicht unterstützt gekennzeichnet. Die Auswahl legt ein Girokonto als Nebenkonto an und verknüpft das Depot damit. Auf der nächsten Seite liegen PDF-Auszug und Anmeldung zusammen. Kartenzahlungen und
andere Geldbewegungen werden dort ebenfalls gebucht. Danach läuft die bisherige
Kursaktualisierung, damit die Kurse nicht auf null stehen bleiben. Nach der Anmeldung liegt die letzte Trade-Republic-Antwort als Datei vor. Auszug speichern schreibt sie in die Dateien-App, wie Finanzen exportieren. Der Auszug liegt nicht in den Einstellungen. Der Bildschirm zeigt die Größe und eine kurze Vorschau, nicht die ganze Timeline. Die Historie wird Seite für Seite gelesen, inklusive Aktivitätslog, und eine Sparplan-Ausführung behält die Stückzahl aus ihrem Detail. Dividenden und Zinsen werden als Ertrag und Zinsen gebucht, dieselben Kategorien wie beim PDF-Import, und nicht als Aktienkauf. Eine Saveback-Ausführung kauft die Stücke und geht vom Girokonto ab. Geschenkte Aktien sind ein Depotgeschenk und tun das nicht. Ein Geschenk gibt es nur bei einer Position ohne Kauf dieser ISIN, ein späterer NVIDIA-Kauf erfindet keine Geschenk-Lose. Das Geschenkdatum kommt vom Geschenk-Ereignis, nicht von einer Kartenprüfung, einer Sparplan-Zeile oder einem anderen Saveback. Die Geschenk-Buchung zeigt den Wert der Stücke, nicht 0 €. Der Kaufkurs am Stück bleibt 0. Der Live-Cash-Stand aus der Sitzung setzt das Trade-Republic-Girokonto. Beim Wechsel von Konto oder Zeitraum zeigt die ganze Finanzen-Seite den Ladezustand, inklusive Prognosen und Buchungen. Kommt die App aus dem Hintergrund zurück, liegt über jedem Tab ein Ladebildschirm, bis Eingaben wieder gehen. Das Anmelde-Popup liegt in einem eigenen Fenster, nachdem die Tastatur weg ist, damit der erste Versuch auf dem Schirm bleibt. Die Finanzen-Ansicht hasht nicht mehr bei jedem Bild Titel und Notizen jeder Buchung. Eine Position ohne Kauf dieser ISIN in der Historie ist ein Geschenk, kein Anfangskauf, auch wenn eine andere Aktie zu einem ähnlichen Kurs gekauft wurde. Das Geschenk behält das Datum des Geschenk-Ereignisses, auch wenn das Ereignis nur Geschenk heißt und die Aktie nicht nennt. Es steht in den Buchungen als Depotgeschenk und hat den Kaufkurs 0, damit die Veränderung seit Kauf dem aktuellen Wert entspricht. Gemischte Geschenk- und Kaufstücke rechnen nur das bezahlte Geld in den Einstand. Eine spätere Anmeldung ersetzt die bisherigen Trade-Republic-Stücke, Bestände und Sitzungsbuchungen; Umbuchungen zwischen eigenen Konten, die nicht aus dieser Sitzung kamen, bleiben. Eine IPO-Zeichnung ist ein Depotkauf nur auf dem Trade-Republic-Girokonto. Die Stücke liegen erst im Depot, wenn die IPO zugeteilt ist. Eine zugeteilte IPO ist ein Kauf. Ein Faktor-Optionsschein bewegt nur Cash, nicht die Aktie darunter. Zwei Kartenzahlungen am selben Tag mit demselben Betrag bleiben beide. Geldbewegungen vor dem ersten Zeitraum des Hauptkontos bleiben in der Liste und liegen außerhalb dieses Zeitraums. Lifify fragt nach dem Kontostand auf Trade Republic an diesem Tag nur, wenn die Sitzung keinen Cash-Stand liefert. Eine Zahlung zwischen zwei eigenen Konten ist eine Umbuchung, und dieselbe Zahlung wird nicht zweimal gebucht, auch wenn die Banken sie zwei oder drei Tage auseinander buchen. Die Umbuchung behält das frühere Datum. Kartenzahlungen, Überweisungen, Steuern, Boni und Empfehlungen nutzen dieselben Auszugstypen. Jeder Kauf und Verkauf aus der Historie wird gebucht, auch ein Verkauf zwischen Sparplan-Ausführungen und eine Aktie, die nicht mehr im Depot liegt. Krypto-Instrumente mit XF-Kennung bekommen einen Yahoo-Kurs, Bitcoin bleibt nicht bei 0. In den Buchungsdetails stehen Ereignistyp, ISIN, Stück und Kurs. Ein Stück, dessen Kurs nicht zum Einstand passt, verschwindet beim nächsten Aktualisieren. Der Auszug enthält jede Timeline-Seite, das Aktivitätslog, die Geschenk-Details und die Sparpläne, nicht nur die erste Seite. Auszug speichern schreibt diese Datei in die Dateien-App. Du kannst einen Trade-Republic-Auszug laden oder einfügen, keine Lifify-JSON-Sicherung. Der Finanzexport unter Daten enthält Depotstücke, Sparpläne, geschlossene Positionen und die Depotverknüpfung, nicht nur Konten und Bestände. Der
PDF-Import bleibt. Den Schritt kannst du überspringen.

Unter Finanzen in den Einstellungen stehen zuerst Konten, dann Bankimport, dann Trade Republic in einer Sektion mit Kontoauszug hochladen und Anmeldung als zwei Update-Wege, zuletzt Depot. Dort liegt dieselbe Anmeldung. Die Sitzung wird
nicht gespeichert, es gibt keinen Knopf zum Aktualisieren aus einer Sitzung.
Jedes Mal neu anmelden. Nichts läuft mit einem Timer, beim Start oder wenn
Finanzen aufgeht. Die PIN wird nicht gespeichert. Lehnt Trade Republic die
erste Anmeldung ab, sagt Lifify, dass keine Bestätigung geschickt wurde. Es
meldet sich nicht von allein an.

Diese Umgebung hat `POST /api/v2/auth/web/login` mit den Headern der Web-App
erreicht. Eine Nummer, die keine Telefonnummer ist, kam als HTTP 400
`NUMBER_INVALID` zurück, bevor eine Sitzung entstand. Eine echte Anmeldung
braucht weiter dein Telefon, deine PIN und die Bestätigung in der
Trade-Republic-App. Dieser Schritt wurde hier nicht ausgeführt, und es wurden
keine Bestände erfunden.

### Kurzbefehle

Lege auf dem iPhone zwei Kurzbefehle an. iOS kann trotzdem nach Tippen auf
Ausführen fragen.

1. **Sparkasse.** Kommt eine Mitteilung der Sparkasse, führe **Bankmitteilung buchen** aus. Setze **Konto** auf Sparkasse und **Mitteilung** auf den Text der Mitteilung.
2. **Trade Republic.** Dasselbe für eine Mitteilung von Trade Republic, mit **Konto** auf Trade Republic.

Derselbe Aufruf ist `lifify://notice?account=sparkasse&text=` mit dem
Mitteilungstext in `text`. Bei Trade Republic ist das Konto `traderepublic`.
Lifify liest Betrag, Richtung und einen kurzen Titel und bucht auf dieses
Girokonto. Eine Trade-Republic-Mitteilung „Überweisung erhalten“ ist eine
Umbuchung vom Hauptkonto, keine Einnahme. „ausgegeben“ ist eine Ausgabe auf
Trade Republic. Dieselbe Umbuchung wird innerhalb von drei Tagen nicht doppelt
gebucht. Dasselbe Konto, derselbe Betrag und dieselbe Richtung innerhalb von
sechs Stunden werden eine Buchung.

Das neue Verhalten hat eine Unit-Prüfung und eine Integrationsprüfung. Die
Prüfungen schreiben keine Nutzerdaten.

Diese Umgebung hat kein Xcode. Das Projekt wurde nicht gebaut, und die
Prüfungen wurden nicht ausgeführt. Die Swift-Klammern wurden lokal geprüft.

### Ideen, nicht umgesetzt

- Soll ein Kurzbefehl das Trade-Republic-Girokonto anlegen, wenn es fehlt?
- Soll das Fenster von sechs Stunden länger sein, wenn die Bankmitteilung erst am nächsten Morgen kommt?
- Soll ein Kurs aus der Sitzung gespeichert werden, oder bleibt die bisherige Kursaktualisierung die einzige Quelle?
