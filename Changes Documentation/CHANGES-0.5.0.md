# Changes in 0.5.0

[English](#english) · [Deutsch](#deutsch)

## English

Lifify 0.5.0 adds a manual Trade Republic sign-in and a way for the Shortcuts
app to book a Sparkasse or Trade Republic notice. The finance calculations are
unchanged and stay in [FINANZEN.md](../FINANZEN.md). What changed in 0.4.0 is in
[CHANGES-0.4.0.md](CHANGES-0.4.0.md). The displayed version is 0.5.0.

### Trade Republic, by hand

Setup has one more optional step, after the PDF statement. You enter the phone
number and the PIN that opens the Trade Republic app, then confirm in that app.
The steps are popups in the same colors as the rest of the app. Phone number and PIN are one step, and a loading popup holds the screen while the depot updates. The sign-in keeps one connection, so the confirmation in the app is the same session that gets saved.
A leading 0 is sent as +49. A position the session no longer returns is booked as a sale, with the date and proceeds from that sale, and then removed. When the session has no sale row, the remaining shares are sold at their cost basis so the position does not vanish without a booking.
Each purchase from the sign-in stays its own purchase, with its own date and share count. A position is not collapsed into one buy dated today. A savings plan comes from the live plan, and it shows under fixed costs. A normal buy is not labeled as a savings plan. A later purchase of a stock already held stays its own purchase, with its own share count, date, and price, on the stock and as its own booking. A savings-plan execution is labeled as a savings plan, and the plan keeps the rhythm of its last execution. Bank import and the Trade Republic statement live under Finance. Each portfolio is linked to one checking account. A duplicate is the same payee, the same amount, and a nearby date. A different shop is imported. Setup can add a portfolio before Trade Republic. Only Trade Republic can be chosen. The others are marked not supported. Choosing it creates a secondary checking account linked to the portfolio. The next page offers the PDF statement and sign-in together. Card payments and other
cash movements are booked there too. The existing price update then runs, so the
prices are not left at zero. With developer mode on, the last Trade Republic response can be copied from the app. The history is read page by page, and a savings execution keeps the share count from its detail. The PDF import stays. You can skip the step.

Finance in Settings has the same sign-in, and a button that refreshes the depot
from the saved session. Nothing refreshes on a timer, at launch, or when
Finance opens. The session cookie stays in the keychain, on this device only,
and out of backups, the same way as the Gemini key. The PIN is not saved. A first sign-in that Trade Republic refuses says that no
confirmation was sent. It does not call that an expired session. When a saved
session is dead, Lifify asks you to confirm again. It does not sign in by
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
account. The same account, amount, and direction inside six hours becomes one
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

### Trade Republic, von Hand

Die Einrichtung hat einen weiteren optionalen Schritt, nach dem PDF-Auszug. Du
gibst Telefonnummer und die PIN ein, mit der du die Trade-Republic-App öffnest,
und bestätigst in der App. Die Schritte sind Pop-ups in denselben Farben wie der Rest der App. Telefonnummer
und PIN sind ein Schritt, und ein Lade-Popup hält den Bildschirm, solange das Depot
aktualisiert wird. Die Anmeldung bleibt auf einer Verbindung, damit die Bestätigung
in der App zu derselben Sitzung gehört, die gespeichert wird. Eine 0 am Anfang geht als
+49 mit. Eine Position, die die Sitzung nicht mehr liefert, wird als Verkauf gebucht,
mit Datum und Erlös, und verschwindet danach. Fehlt die Verkaufszeile, werden die
restlichen Stücke zum Einstand verkauft, damit die Position nicht ohne Buchung
weg ist.
Jeder Kauf aus der Anmeldung bleibt ein eigener Kauf, mit eigenem Datum und eigener Stückzahl. Eine Position wird nicht zu einem Kauf mit heutigem Datum zusammengezogen. Ein Sparplan kommt aus dem laufenden Plan und steht unter den Fixkosten. Ein normaler Kauf heißt nicht Sparplan. Ein späterer Kauf einer Aktie, die schon im Depot liegt, bleibt ein eigener Kauf, mit eigener Stückzahl, eigenem Datum und eigenem Kurs, an der Aktie und als eigene Buchung. Eine Sparplan-Ausführung heißt Sparplan, und der Plan übernimmt den Rhythmus der letzten Ausführung. Bankimport und der Trade-Republic-Auszug liegen unter Finanzen. Jedes Depot hängt an genau einem Girokonto. Eine Doppelung ist derselbe Empfänger, derselbe Betrag und ein nahes Datum. Ein anderer Laden wird importiert. Vor Trade Republic kann ein Depot angelegt werden. Nur Trade Republic ist wählbar. Die anderen Broker sind als nicht unterstützt gekennzeichnet. Die Auswahl legt ein Girokonto als Nebenkonto an und verknüpft das Depot damit. Auf der nächsten Seite liegen PDF-Auszug und Anmeldung zusammen. Kartenzahlungen und
andere Geldbewegungen werden dort ebenfalls gebucht. Danach läuft die bisherige
Kursaktualisierung, damit die Kurse nicht auf null stehen bleiben. Mit
Entwicklermodus lässt sich die letzte Trade-Republic-Antwort in der App kopieren. Die Historie wird Seite für Seite gelesen, und eine Sparplan-Ausführung behält die Stückzahl aus ihrem Detail. Der
PDF-Import bleibt. Den Schritt kannst du überspringen.

Unter Finanzen in den Einstellungen liegt dieselbe Anmeldung und ein Knopf, der
das Depot aus der gespeicherten Sitzung aktualisiert. Nichts aktualisiert sich
mit einem Timer, beim Start oder wenn Finanzen aufgeht. Das Sitzungs-Cookie
bleibt im Schlüsselbund, nur auf diesem Gerät und außerhalb der Sicherung, so
wie der Gemini-Schlüssel. Die PIN wird nicht gespeichert. Lehnt Trade Republic
die erste Anmeldung ab, sagt Lifify, dass keine Bestätigung geschickt wurde.
Das ist keine abgelaufene Sitzung. Ist eine gespeicherte Sitzung tot, bittet
Lifify um eine neue Bestätigung. Es meldet sich nicht von allein an.

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
Girokonto. Dasselbe Konto, derselbe Betrag und dieselbe Richtung innerhalb von
sechs Stunden werden eine Buchung.

Das neue Verhalten hat eine Unit-Prüfung und eine Integrationsprüfung. Die
Prüfungen schreiben keine Nutzerdaten.

Diese Umgebung hat kein Xcode. Das Projekt wurde nicht gebaut, und die
Prüfungen wurden nicht ausgeführt. Die Swift-Klammern wurden lokal geprüft.

### Ideen, nicht umgesetzt

- Soll ein Kurzbefehl das Trade-Republic-Girokonto anlegen, wenn es fehlt?
- Soll das Fenster von sechs Stunden länger sein, wenn die Bankmitteilung erst am nächsten Morgen kommt?
- Soll ein Kurs aus der Sitzung gespeichert werden, oder bleibt die bisherige Kursaktualisierung die einzige Quelle?
