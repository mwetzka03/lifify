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
The steps are popups, and a loading popup holds the screen while the depot updates.
A leading 0 is sent as +49. A position the session no longer returns is removed.
A later purchase of a stock already held is added, with its date, on the stock
and as a booking on the Trade Republic checking account. Card payments and other
cash movements are booked there too. The existing price update then runs, so the
prices are not left at zero. The PDF import stays. You can skip the step.

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
und bestätigst in der App. Die Schritte sind Pop-ups, und ein Lade-Popup hält
den Bildschirm, solange das Depot aktualisiert wird. Eine 0 am Anfang geht als
+49 mit. Eine Position, die die Sitzung nicht mehr liefert, verschwindet. Ein
späterer Kauf einer Aktie, die schon im Depot liegt, kommt mit Datum dazu, an
der Aktie und als Buchung auf dem Trade-Republic-Girokonto. Kartenzahlungen und
andere Geldbewegungen werden dort ebenfalls gebucht. Danach läuft die bisherige
Kursaktualisierung, damit die Kurse nicht auf null stehen bleiben. Der
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
