# Changes in 0.5.5

[English](#english) · [Deutsch](#deutsch)

## English

Lifify 0.5.0 adds a manual Trade Republic sign-in and a way for the Shortcuts
app to book a Sparkasse or Trade Republic notice. The finance calculations are
unchanged and stay in [FINANZEN.md](../FINANZEN.md). What changed in 0.4.0 is in
[CHANGES-0.4.0.md](CHANGES-0.4.0.md). The displayed version is 0.5.5.

### 0.5.5: Test foundation

**What changed.** `LififyTests` now has real rule tests in Swift Testing. They cover coins and the wallet, streaks and freezes, the multiplier, abstinence payouts, time slots and groups, workout links, due dates, finance balances, forecasts, the savings-plan forecast, and the backup round trip for Finance and Challenges. Services now read UserDefaults through `AppDefaults.store`.

**Why.** Tests must never write real user data, and the next steps change persistence.

**Effect.** The app still uses `UserDefaults.standard`, so its behavior is unchanged. Tests use an in-memory database and a private suite.

**Failed checks.** Two in-app check groups failed before this step, from four outdated conditions. None was an app bug, and the conditions now match the code: twin rows have different old fingerprints because the old title was the purpose, `XF000BTC0017` passes the ISIN checksum, a buy without a share count is sized from the average price, and a full sale closes the holding through its lots without a separate drop.

**Not covered yet.** Paths that write to the iOS calendar or schedule notifications are not run by the tests: the actual calendar rewrite after a resize, `WorkoutCalendarSync.apply`, abstinence bonuses through `settle`, and relapse. Their pure rules are tested. The full-app and Training backup restores are also not run, because they touch workout files.

### 0.5.5: Performance

**What changed.** Finance periods are reused until stored data changes. Fixed-cost matching looks only at bookings of the same day. Refund, skip, rejection, and period-link lookups no longer rebuild their data for every booking. The depot sorts by values it computes once.

**Measured.** Release build in the iPhone 17 simulator, stress data with 5,000 bookings, 30 holdings, 1,200 lots, and 365 prices per holding. Median of three first opens, until the main thread stayed free.

| Screen | Before | After |
| --- | ---: | ---: |
| Finance overview | 8.4 s | 1.4 s |
| Depot | 36.2 s | 1.5 s |

**Effect.** The calculations and their results are unchanged. Unsaved edits skip the reused values. These are simulator values with test data, so times on an iPhone will differ.

**Loading screen.** The loading screen on return to the app stays. It also covers the sync with the iOS calendar, which could not be measured here with real calendar data.

### 0.5.5: Data storage

**What changed.** The database now opens through a versioned migration plan (schema V3). A finished app no longer moves its store aside when it cannot be opened. It shows the error and offers to restore a backup of the entire app. Only that choice moves the old store into an archive folder, and a failed restore puts it back.

**Why.** A silent reset could look like total data loss.

**Effect.** During first-time setup the old behavior stays: closing the app or a broken partial store starts setup again.

**Moved to the database.** On first launch of 0.5.5, data moves once from UserDefaults into SwiftData. Old keys are deleted only after the new rows are saved. Unreadable data stays untouched and the move runs again on the next launch. Moved so far: portfolio lots, savings plans, closed positions, market symbols, previous closes, purchase dates, portfolio links, refund and income links, forecast skips, period links and rejected matches, expense group links, transfer forecasts, Shortcuts templates, budget accounts, bank import cursors, streak states, abstinence data, challenge minutes and event members, workout links, pins, custom categories, reward policies, reminder and event repeats, icons, and meals. Settings such as language, theme, multipliers, body data, and briefing times stay in UserDefaults.

**Group and event links.** A challenge now has one source for its groups. The direct event link and the event member list stay separate on purpose: only the direct link sets the streak quota, so merging them would change streaks. Tests pin this behavior. Removing the old columns needs frozen copies of the version 2 models first.

### 0.5.5: Complete backup

**What changed.** The backup now also carries transfer forecasts, refund links, forecast skips, period links and rejected matches, Shortcuts templates, variable budget accounts, bank import cursors, default trade settings, pinned challenges and groups, event offers, the Fast Food reward link, and display and briefing choices. A Finance or Challenges file carries only its own area. Device-wide choices are in the entire-app backup.

**Why.** These values were reset on restore but never exported, so they were lost.

**Effect.** Older backup files still restore and leave these values as they are. A new backup replaces them, including clearing values it does not contain. Restoring no longer creates a second Fast Food reward.

**Health export.** Export training is now Export health and carries workouts and the meal list. Restoring it keeps fast-food coins in step with the meals: charges of meals that are gone are refunded, and a restored fast-food meal without a charge is booked once. Older training files still restore and leave the meals alone.

**Health delete.** Delete training is now Delete health. It removes workouts, meals, and meal photos, and refunds the fast-food purchases of those meals.

**Not included.** Meal and profile photos, exercise images, price caches, UI refresh counters, developer and setup state, the Trade Republic extract, and everything in the Keychain.

### 0.5.5: Shop lock on a negative balance

**What changed.** While the wallet is below 0, rewards and streak freezes cannot be bought, including free ones. The shop shows a red lock notice with the balance and the coins still missing, and its buy buttons read Locked. At 0 or above the shop opens again.

**Why.** The wallet may go negative, but that debt should be paid off before the next purchase.

**Effect.** The automatic fast-food purchase still books while the shop is locked, so a fast-food meal always costs its coins. Changing that meal's kind or deleting it still refunds the charge. Earning coins, unchecking challenges, and editing rewards stay available.

### 0.5.5: In-app check page removed

**What changed.** The test page under developer mode and its check code are gone from the app. Of the 108 checks, 99 worked examples moved into `LififyTests`. Nine checks, and the conditions inside other checks that only compared UI text, symbols, or constants with themselves, were dropped. The constants that existed only for those checks were removed: `TradeRepublicRefresh`, `TradeRepublicGap`, five `TradeRepublicSample` flags, and three layout constants.

**Why.** Test code does not belong in the shipped app, and Xcode now runs the rules.

**Effect.** Developer mode no longer has Run tests. The simulated day and the Trade Republic extract stay. Trade Republic still stores no PIN or session and does not refresh on its own. That behavior comes from the sign-in code, not from the removed constants.

### Setup

Setup can restore the entire app from one JSON file, or only one area:
Finance, Challenges, or Training. You can pick several of those part files at
once. If setup is not finished, it starts from the first step after every
launch or update. Every step after the first has Back.

### Trade Republic, by hand

Setup has one more optional step, after the PDF statement. You enter the phone
number and the PIN that opens the Trade Republic app, then confirm in that app.
The steps are popups in the same colors as the rest of the app. Phone number and PIN are one step, and a loading popup holds the screen while the depot updates. The sign-in keeps one connection, so the confirmation in the app belongs to the same login that then reads the depot.
A leading 0 is sent as +49. A position the session no longer returns is booked as a sale, with the date and proceeds from that sale, and then removed. When the session has no sale row, the holding stays. A leftover quantity without a sale in the history is not booked as a sale dated today; the lots are scaled to the live position instead.
Each purchase from the sign-in stays its own purchase, with its own date and share count. A position is not collapsed into one buy dated today. A savings plan comes from the live plan, and it shows under fixed costs. A normal buy is not labeled as a savings plan. A later purchase of a stock already held stays its own purchase, with its own share count, date, and price, on the stock and as its own booking. A savings-plan execution is labeled as a savings plan, and the plan keeps the rhythm of its last execution. Bank import and the Trade Republic statement live under Finance. Each portfolio is linked to one checking account. A duplicate is the same payee, the same amount, a nearby date, and the same reference. Two CSV rows to the same payee on the same day with a different End-to-End reference stay two bookings. A re-import keeps the second row when its purpose is not already in the stored notes. Setup imports every bank row without duplicate detection. An import from Settings skips identical rows and older days whose booking count already matches. On the last booking day and on days where the file has extra rows, Lifify asks whether to import. Missing second payments are on by default. The entered cash is applied after you confirm the review. A pending Sparkasse row is not imported. The first salary period follows the main account and is clipped to that first booking or opening balance, so an earlier Trade Republic booking does not start the period. A bank import asks for the current balance and sets the opening at the start of the first booking day so that this stand plus later bookings equal that cash. Today's pin as the last stand is gone. On the current period, net worth is the live cash. On a past or future period it is that period's Endsaldo. Depot stays the market value. The live cash figure from a Trade Republic session is pinned the same way and prefers total cash over available cash. Save extract sits only in developer mode. After a successful Trade Republic sign-in, setup continues to the next step. Statement upload and sign-in are Option A and Option B, each with an icon. A different shop is imported. Setup can add a portfolio before Trade Republic. Only Trade Republic can be chosen. The others are marked not supported. Choosing it creates a secondary checking account linked to the portfolio. The next page offers the PDF statement and sign-in together. Card payments and other
cash movements are booked there too. The existing price update then runs, so the
prices are not left at zero. After sign-in, the last Trade Republic response is kept as a file. Auszug speichern writes it into the Files app, the same way as Export finance. The extract is not stored in Settings. The screen shows the size and a short preview, not the whole timeline. The history is read page by page, including the activity log, and a savings execution keeps the share count from its detail. Dividends and interest are booked as Ertrag and Zinsen, the same categories as the PDF import, and not as share purchases. A Saveback execution buys those shares and takes that money off the cash account. A gift of shares is Depotgeschenk and does not. Only a position with no purchase of that ISIN is a gift, so a later NVIDIA buy does not invent gift lots. Gift dates come from gift events, not from a card check, a savings-plan row, or another Saveback. The gift booking shows the value of those shares, not 0 €. The lot still has purchase price 0. The live cash figure from the session sets the Trade Republic checking account. When the account or period changes, the whole Finance page shows loading, including forecasts and bookings. When the app returns from the background, a loading screen covers every tab until input works again. The sign-in popup is its own window after the keyboard is gone, so the first attempt stays on screen. The Finance tab no longer hashes every booking title and note on each frame. A position with no purchase of that ISIN in the history is a gift, not an opening buy, even when another stock was bought at a similar price. The gift keeps the date of the gift event, including when that event is only titled Geschenk and does not name the stock. It shows as Depotgeschenk in the bookings, and has a purchase price of 0, so since-purchase P&L is the market value. Mixed gift and paid lots use only the cash that was paid in the average. A later sign-in replaces the previous Trade Republic lots, holdings, and session bookings; own-account transfers that did not come from that session stay. An IPO subscription is a Depotkauf on the Trade Republic cash account only. The shares are not in the depot until the IPO is allocated. An allocated IPO is a purchase. A Faktor Optionsschein moves cash, not the underlying stock. Two card payments of the same amount on the same day both stay. Cash movements before the first period of the main account stay in the ledger and sit outside that period. Lifify asks for the Trade Republic cash balance on that day only when the session has no cash figure. A payment between two of your own accounts is a transfer, and the same payment is not booked twice, including when the banks book it two or three days apart. The surviving transfer keeps the earlier date. Card payments, transfers, tax, bonuses, and referrals use those statement types too. Every buy and sale in the history is booked, including a sale that sits between savings-plan lots and a stock that is no longer in the depot. Crypto instruments with an XF identifier get a Yahoo price, so Bitcoin is not left at 0. Booking notes include the Trade Republic event type, ISIN, quantity, and price. A lot whose price is nowhere near the average cost is removed on the next refresh. The extract keeps every timeline page, the activity log, the gift details, and the savings plans, not one clipped page. Save extract writes that file into the Files app. You can load or paste a Trade Republic extract back in, not a Lifify JSON backup. The finance export under Data includes lots, savings plans, closed positions, and the depot link, not only accounts and holdings. The PDF import stays. You can skip the step.

Finance in Settings lists Accounts, then Bank import, then Shortcuts, then Trade Republic as one section with statement upload and sign-in as two update paths, then Portfolio last. The same sign-in is there. The session is not saved, so there is
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

Under Finance, Shortcuts, you add a template per checking account: an example notice and whether it is an expense, income, or a transfer. The Apple Shortcut still sends the text; Lifify books it from that template.

The same call is `lifify://notice?account=sparkasse&text=` with the notification
text in `text`. For Trade Republic the account is `traderepublic`. Lifify reads
the amount, the direction, and a short title, then books it on that checking
account. A Trade Republic notice that a transfer was received is an own-account
transfer from the main checking account, not income. “ausgegeben” is a card
expense on Trade Republic. The same transfer is not booked twice within three
days. The same account, amount, and direction inside six hours becomes one
booking.

The real sign-in with a phone, PIN, and app confirmation is not part of the automated tests.

### Ideas, not built

- Should a shortcut create the Trade Republic checking account when it is missing?
- Should the six-hour window be longer when the bank notice arrives the next morning?
- Should a market price from the session be stored, or should the existing price update stay the only source?

## Deutsch

Lifify 0.5.0 ergänzt eine manuelle Anmeldung bei Trade Republic und einen Weg,
mit dem die Kurzbefehle-App eine Sparkassen- oder Trade-Republic-Mitteilung
bucht. Die Finanzrechnung ist unverändert und bleibt in
[FINANZEN.md](../FINANZEN.md). Was sich in 0.4.0 geändert hat, steht in
[CHANGES-0.4.0.md](CHANGES-0.4.0.md). Die angezeigte Version ist 0.5.5.

### 0.5.5: Testgerüst

**Was sich geändert hat.** `LififyTests` enthält jetzt echte Regeltests mit Swift Testing. Sie decken Coins und Wallet, Streaks und Freezes, den Multiplikator, Abstinenz-Auszahlungen, Zeit-Slots und Gruppen, Training-Verknüpfungen, Fälligkeit, Finanzsalden, Prognosen, die Sparplan-Prognose und den Backup-Rundlauf für Finanzen und Challenges ab. Services lesen UserDefaults jetzt über `AppDefaults.store`.

**Warum.** Tests dürfen nie echte Nutzerdaten schreiben, und die nächsten Schritte ändern die Persistenz.

**Auswirkung.** Die App nutzt weiter `UserDefaults.standard`, ihr Verhalten bleibt gleich. Tests nutzen eine In-Memory-Datenbank und eine eigene Suite.

**Fehlgeschlagene Prüfungen.** Vor diesem Schritt schlugen zwei In-App-Prüfgruppen fehl, wegen vier veralteter Bedingungen. Keine davon war ein App-Fehler, die Bedingungen entsprechen jetzt dem Code: Zwillingszeilen haben verschiedene alte Fingerabdrücke, weil der alte Titel der Verwendungszweck war. `XF000BTC0017` besteht die ISIN-Prüfsumme. Ein Kauf ohne Stückzahl wird über den Durchschnittspreis bemessen. Ein vollständiger Verkauf schließt die Position über ihre Lots, ohne eigenes Entfernen.

**Noch nicht abgedeckt.** Wege, die in den iOS-Kalender schreiben oder Mitteilungen planen, laufen in den Tests nicht: das echte Umschreiben des Termins nach einer Größenänderung, `WorkoutCalendarSync.apply`, Abstinenz-Boni über `settle` und der Rückfall. Ihre reinen Regeln sind getestet. Auch die Wiederherstellung des Gesamt- und des Trainings-Backups läuft nicht, weil sie Trainingsdateien berührt.

### 0.5.5: Performance

**Was sich geändert hat.** Finanzzeiträume werden wiederverwendet, bis sich gespeicherte Daten ändern. Der Fixkosten-Abgleich prüft nur noch Buchungen desselben Tages. Erstattungen, übersprungene Prognosen, Ablehnungen und Zeitraum-Verknüpfungen bauen ihre Daten nicht mehr für jede Buchung neu auf. Das Depot sortiert nach einmal berechneten Werten.

**Gemessen.** Release-Build im iPhone-17-Simulator, Stresstest mit 5.000 Buchungen, 30 Positionen, 1.200 Lots und 365 Kursen je Position. Median aus drei ersten Aufrufen, bis der Hauptthread frei blieb.

| Bildschirm | Vorher | Nachher |
| --- | ---: | ---: |
| Finanzübersicht | 8,4 s | 1,4 s |
| Depot | 36,2 s | 1,5 s |

**Auswirkung.** Die Berechnungen und ihre Ergebnisse bleiben gleich. Ungespeicherte Änderungen umgehen die wiederverwendeten Werte. Es sind Simulatorwerte mit Testdaten, auf dem iPhone weichen die Zeiten ab.

**Ladebildschirm.** Der Ladebildschirm beim Zurückkehren bleibt. Er deckt auch den Abgleich mit dem iOS-Kalender ab, der sich hier nicht mit echten Kalenderdaten messen ließ.

### 0.5.5: Datenspeicher

**Was sich geändert hat.** Die Datenbank öffnet jetzt über einen versionierten Migrationsplan (Schema V3). Eine fertig eingerichtete App schiebt ihren Speicher nicht mehr weg, wenn er sich nicht öffnen lässt. Sie zeigt den Fehler und bietet an, eine Sicherung der gesamten App wiederherzustellen. Erst diese Wahl verschiebt den alten Speicher in einen Archivordner, ein fehlgeschlagener Restore legt ihn zurück.

**Warum.** Ein stilles Zurücksetzen konnte wie ein vollständiger Datenverlust wirken.

**Auswirkung.** Während der Ersteinrichtung bleibt das bisherige Verhalten: Schließen der App oder ein defekter Teilstand beginnt die Einrichtung von vorn.

**In die Datenbank umgezogen.** Beim ersten Start von 0.5.5 ziehen Daten einmalig von UserDefaults nach SwiftData um. Alte Schlüssel werden erst gelöscht, wenn die neuen Zeilen gespeichert sind. Unlesbare Daten bleiben unangetastet, der Umzug läuft beim nächsten Start erneut. Bisher umgezogen: Depot-Lots, Sparpläne, geschlossene Positionen, Marktsymbole, Vortageskurse, Kaufdaten, Depot-Verknüpfungen, Erstattungs- und Einkommens-Verknüpfungen, übersprungene Prognosen, Zeitraum-Verknüpfungen und abgelehnte Treffer, Ausgabengruppen-Zuordnungen, Umbuchungsprognosen, Kurzbefehl-Vorlagen, Budget-Konten, Bankimport-Stände, Streak-Zustände, Abstinenzdaten, Challenge-Minuten und Termin-Mitglieder, Workout-Links, Pins, eigene Kategorien, Einlöse-Regeln, Wiederholungen von Erinnerungen und Terminen, Symbole und Mahlzeiten. Einstellungen wie Sprache, Design, Multiplikatoren, Körperdaten und Briefing-Zeiten bleiben in UserDefaults.

**Gruppen- und Terminverknüpfungen.** Eine Challenge hat jetzt eine Quelle für ihre Gruppen. Die direkte Terminverknüpfung und die Mitgliederliste bleiben bewusst getrennt: Nur die direkte Verknüpfung bestimmt das Streak-Soll, ein Zusammenlegen würde Streaks verändern. Tests halten dieses Verhalten fest. Um alte Spalten zu entfernen, braucht es zuerst eingefrorene Kopien der Modelle aus Version 2.

### 0.5.5: Vollständiges Backup

**Was sich geändert hat.** Das Backup enthält jetzt auch Umbuchungsprognosen, Erstattungs-Verknüpfungen, übersprungene Prognosen, Zeitraum-Verknüpfungen und abgelehnte Treffer, Kurzbefehl-Vorlagen, Konten variabler Budgets, Bankimport-Stände, Handelsvorgaben, angepinnte Challenges und Gruppen, Termin-Angebote, die Verknüpfung der Fast-Food-Belohnung sowie Anzeige- und Briefing-Einstellungen. Eine Finanz- oder Challenge-Datei enthält nur ihren Bereich. Geräteweite Einstellungen stehen im Gesamt-Backup.

**Warum.** Diese Werte wurden beim Wiederherstellen zurückgesetzt, aber nie exportiert, und gingen dadurch verloren.

**Auswirkung.** Ältere Backup-Dateien lassen sich weiter einspielen und lassen diese Werte unverändert. Ein neues Backup ersetzt sie und entfernt auch Werte, die es nicht enthält. Eine Wiederherstellung legt keine zweite Fast-Food-Belohnung mehr an.

**Gesundheits-Export.** Aus „Training exportieren“ wird „Gesundheit exportieren“ mit Trainings und Mahlzeitenliste. Beim Einspielen bleiben die Fast-Food-Coins passend zu den Mahlzeiten: Buchungen nicht mehr vorhandener Mahlzeiten werden erstattet, eine wiederhergestellte Fast-Food-Mahlzeit ohne Buchung wird einmal gebucht. Ältere Trainingsdateien lassen sich weiter einspielen und lassen die Mahlzeiten unverändert.

**Gesundheit löschen.** Aus „Training löschen“ wird „Gesundheit löschen“. Die Aktion entfernt Trainings, Mahlzeiten und Mahlzeitenfotos und erstattet die Fast-Food-Käufe dieser Mahlzeiten.

**Nicht enthalten.** Mahlzeiten- und Profilfotos, Übungsbilder, Kurs-Caches, UI-Aktualisierungszähler, Entwickler- und Einrichtungszustand, der Trade-Republic-Auszug und alles im Schlüsselbund.

### 0.5.5: Shop-Sperre bei negativem Guthaben

**Was sich geändert hat.** Solange das Wallet unter 0 liegt, lassen sich Belohnungen und Streak-Freezes nicht kaufen, auch kostenlose nicht. Der Shop zeigt einen roten Sperrhinweis mit Guthaben und fehlenden Coins, seine Kaufknöpfe heißen Gesperrt. Ab 0 ist der Shop wieder offen.

**Warum.** Das Wallet darf ins Minus gehen, das Minus soll aber vor dem nächsten Kauf ausgeglichen sein.

**Auswirkung.** Der automatische Fast-Food-Kauf bucht auch bei gesperrtem Shop, eine Fast-Food-Mahlzeit kostet also immer ihre Coins. Wird ihre Art geändert oder die Mahlzeit gelöscht, wird der Betrag weiter erstattet. Coins verdienen, Haken entfernen und Belohnungen bearbeiten bleiben möglich.

### 0.5.5: In-App-Prüfseite entfernt

**Was sich geändert hat.** Die Testseite im Entwicklermodus und ihr Prüfcode sind aus der App entfernt. Von den 108 Prüfungen sind 99 Rechenbeispiele nach `LififyTests` umgezogen. Neun Prüfungen und die Bedingungen in anderen Prüfungen, die nur UI-Texte, Symbole oder Konstanten mit sich selbst verglichen, sind entfallen. Die nur dafür vorhandenen Konstanten sind entfernt: `TradeRepublicRefresh`, `TradeRepublicGap`, fünf Schalter in `TradeRepublicSample` und drei Layout-Konstanten.

**Warum.** Testcode gehört nicht in die ausgelieferte App, und Xcode führt die Regeln jetzt aus.

**Auswirkung.** Im Entwicklermodus gibt es „Tests ausführen“ nicht mehr. Der simulierte Tag und der Trade-Republic-Auszug bleiben. Trade Republic speichert weiter weder PIN noch Sitzung und aktualisiert nicht von selbst. Das Verhalten kommt aus dem Anmeldecode, nicht aus den entfernten Konstanten.

### Einrichtung

Die Einrichtung lädt die ganze App aus einer JSON-Datei, oder nur einen
Bereich: Finanzen, Challenges oder Training. Mehrere Teildateien gehen auf
einmal. Ist die Einrichtung nicht abgeschlossen, beginnt sie nach jedem Start
oder Update wieder beim ersten Schritt. Ab dem zweiten Schritt gibt es Zurück.

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
Jeder Kauf aus der Anmeldung bleibt ein eigener Kauf, mit eigenem Datum und eigener Stückzahl. Eine Position wird nicht zu einem Kauf mit heutigem Datum zusammengezogen. Ein Sparplan kommt aus dem laufenden Plan und steht unter den Fixkosten. Ein normaler Kauf heißt nicht Sparplan. Ein späterer Kauf einer Aktie, die schon im Depot liegt, bleibt ein eigener Kauf, mit eigener Stückzahl, eigenem Datum und eigenem Kurs, an der Aktie und als eigene Buchung. Eine Sparplan-Ausführung heißt Sparplan, und der Plan übernimmt den Rhythmus der letzten Ausführung. Bankimport und der Trade-Republic-Auszug liegen unter Finanzen. Jedes Depot hängt an genau einem Girokonto. Eine Doppelung ist derselbe Empfänger, derselbe Betrag, ein nahes Datum und dieselbe Referenz. Zwei CSV-Zeilen an denselben Empfänger am selben Tag mit unterschiedlicher End-to-End-Referenz bleiben zwei Buchungen. Zwei Buchungen am selben Tag mit demselben Betrag bleiben beide; sie werden nicht zu einer Zahlung zusammengezogen. Ein erneuter Import behält die zweite Zeile, wenn ihr Verwendungszweck noch nicht in den gespeicherten Notizen steht. Die Einrichtung übernimmt jede Bankzeile ohne Duplikaterkennung. Ein Import aus den Einstellungen überspringt identische Zeilen und ältere Tage, deren Anzahl schon stimmt. Am letzten Buchungstag und an Tagen mit mehr Zeilen in der Datei fragt Lifify, ob die Buchung übernommen wird. Fehlende Zweit-Zahlungen stehen angeschaltet. Der Kontostand wird erst nach Übernehmen gesetzt. Ein vorgemerkter Sparkassen-Umsatz wird nicht importiert. Der erste Gehaltszeitraum folgt dem Hauptkonto und wird auf dessen erste Buchung oder Eröffnungssaldo geschnitten, damit eine frühere Trade-Republic-Buchung den Zeitraum nicht startet. Ein Bankimport fragt nach dem aktuellen Kontostand und setzt den Eröffnungssaldo an den Anfang des ersten Buchungstags, vor den Buchungen dieses Tages, so dass dieser Stand plus alle späteren Buchungen den angegebenen Kontostand ergeben. Eine heutige Saldo-Korrektur als letzter Stand entfällt. Ein späterer Import überspringt alte Zeilen, übernimmt neue und setzt nur eine Saldo-Korrektur seit dem letzten Import. Im aktuellen Zeitraum ist Gesamtvermögen der Live-Cash; ohne offene Kosten ist der Endsaldo derselbe Stand. In einem vergangenen oder zukünftigen Zeitraum ist Gesamtvermögen der Endsaldo dieses Zeitraums. Depot bleibt der Marktwert. Der Live-Cash-Stand einer Trade-Republic-Sitzung wird genauso gesetzt und nimmt den Total-Cash vor dem verfügbaren Cash. Auszug speichern steht nur im Entwicklermodus. Nach einer erfolgreichen Trade-Republic-Anmeldung geht die Einrichtung in den nächsten Schritt. Kontoauszug hochladen und Anmelden sind Variante A und Variante B, jeweils mit Icon. Ein anderer Laden wird importiert. Vor Trade Republic kann ein Depot angelegt werden. Nur Trade Republic ist wählbar. Die anderen Broker sind als nicht unterstützt gekennzeichnet. Die Auswahl legt ein Girokonto als Nebenkonto an und verknüpft das Depot damit. Auf der nächsten Seite liegen PDF-Auszug und Anmeldung zusammen. Kartenzahlungen und
andere Geldbewegungen werden dort ebenfalls gebucht. Danach läuft die bisherige
Kursaktualisierung, damit die Kurse nicht auf null stehen bleiben. Nach der Anmeldung liegt die letzte Trade-Republic-Antwort als Datei vor. Auszug speichern schreibt sie in die Dateien-App, wie Finanzen exportieren. Der Auszug liegt nicht in den Einstellungen. Der Bildschirm zeigt die Größe und eine kurze Vorschau, nicht die ganze Timeline. Die Historie wird Seite für Seite gelesen, inklusive Aktivitätslog, und eine Sparplan-Ausführung behält die Stückzahl aus ihrem Detail. Dividenden und Zinsen werden als Ertrag und Zinsen gebucht, dieselben Kategorien wie beim PDF-Import, und nicht als Aktienkauf. Eine Saveback-Ausführung kauft die Stücke und geht vom Girokonto ab. Geschenkte Aktien sind ein Depotgeschenk und tun das nicht. Ein Geschenk gibt es nur bei einer Position ohne Kauf dieser ISIN, ein späterer NVIDIA-Kauf erfindet keine Geschenk-Lose. Das Geschenkdatum kommt vom Geschenk-Ereignis, nicht von einer Kartenprüfung, einer Sparplan-Zeile oder einem anderen Saveback. Die Geschenk-Buchung zeigt den Wert der Stücke, nicht 0 €. Der Kaufkurs am Stück bleibt 0. Der Live-Cash-Stand aus der Sitzung setzt das Trade-Republic-Girokonto. Beim Wechsel von Konto oder Zeitraum zeigt die ganze Finanzen-Seite den Ladezustand, inklusive Prognosen und Buchungen. Kommt die App aus dem Hintergrund zurück, liegt über jedem Tab ein Ladebildschirm, bis Eingaben wieder gehen. Das Anmelde-Popup liegt in einem eigenen Fenster, nachdem die Tastatur weg ist, damit der erste Versuch auf dem Schirm bleibt. Die Finanzen-Ansicht hasht nicht mehr bei jedem Bild Titel und Notizen jeder Buchung. Eine Position ohne Kauf dieser ISIN in der Historie ist ein Geschenk, kein Anfangskauf, auch wenn eine andere Aktie zu einem ähnlichen Kurs gekauft wurde. Das Geschenk behält das Datum des Geschenk-Ereignisses, auch wenn das Ereignis nur Geschenk heißt und die Aktie nicht nennt. Es steht in den Buchungen als Depotgeschenk und hat den Kaufkurs 0, damit die Veränderung seit Kauf dem aktuellen Wert entspricht. Gemischte Geschenk- und Kaufstücke rechnen nur das bezahlte Geld in den Einstand. Eine spätere Anmeldung ersetzt die bisherigen Trade-Republic-Stücke, Bestände und Sitzungsbuchungen; Umbuchungen zwischen eigenen Konten, die nicht aus dieser Sitzung kamen, bleiben. Eine IPO-Zeichnung ist ein Depotkauf nur auf dem Trade-Republic-Girokonto. Die Stücke liegen erst im Depot, wenn die IPO zugeteilt ist. Eine zugeteilte IPO ist ein Kauf. Ein Faktor-Optionsschein bewegt nur Cash, nicht die Aktie darunter. Zwei Kartenzahlungen am selben Tag mit demselben Betrag bleiben beide. Geldbewegungen vor dem ersten Zeitraum des Hauptkontos bleiben in der Liste und liegen außerhalb dieses Zeitraums. Lifify fragt nach dem Kontostand auf Trade Republic an diesem Tag nur, wenn die Sitzung keinen Cash-Stand liefert. Eine Zahlung zwischen zwei eigenen Konten ist eine Umbuchung, und dieselbe Zahlung wird nicht zweimal gebucht, auch wenn die Banken sie zwei oder drei Tage auseinander buchen. Die Umbuchung behält das frühere Datum. Kartenzahlungen, Überweisungen, Steuern, Boni und Empfehlungen nutzen dieselben Auszugstypen. Jeder Kauf und Verkauf aus der Historie wird gebucht, auch ein Verkauf zwischen Sparplan-Ausführungen und eine Aktie, die nicht mehr im Depot liegt. Krypto-Instrumente mit XF-Kennung bekommen einen Yahoo-Kurs, Bitcoin bleibt nicht bei 0. In den Buchungsdetails stehen Ereignistyp, ISIN, Stück und Kurs. Ein Stück, dessen Kurs nicht zum Einstand passt, verschwindet beim nächsten Aktualisieren. Der Auszug enthält jede Timeline-Seite, das Aktivitätslog, die Geschenk-Details und die Sparpläne, nicht nur die erste Seite. Auszug speichern schreibt diese Datei in die Dateien-App. Du kannst einen Trade-Republic-Auszug laden oder einfügen, keine Lifify-JSON-Sicherung. Der Finanzexport unter Daten enthält Depotstücke, Sparpläne, geschlossene Positionen und die Depotverknüpfung, nicht nur Konten und Bestände. Der
PDF-Import bleibt. Den Schritt kannst du überspringen.

Unter Finanzen in den Einstellungen stehen zuerst Konten, dann Bankimport, dann Kurzbefehle, dann Trade Republic in einer Sektion mit Kontoauszug hochladen und Anmeldung als zwei Update-Wege, zuletzt Depot. Dort liegt dieselbe Anmeldung. Die Sitzung wird
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

Unter Finanzen, Kurzbefehle, legst du pro Girokonto eine Vorlage an: eine Beispielmitteilung und ob es Ausgabe, Einnahme oder Umbuchung ist. Der Apple-Kurzbefehl schickt weiter den Text; Lifify bucht nach dieser Vorlage.

Derselbe Aufruf ist `lifify://notice?account=sparkasse&text=` mit dem
Mitteilungstext in `text`. Bei Trade Republic ist das Konto `traderepublic`.
Lifify liest Betrag, Richtung und einen kurzen Titel und bucht auf dieses
Girokonto. Eine Trade-Republic-Mitteilung „Überweisung erhalten“ ist eine
Umbuchung vom Hauptkonto, keine Einnahme. „ausgegeben“ ist eine Ausgabe auf
Trade Republic. Dieselbe Umbuchung wird innerhalb von drei Tagen nicht doppelt
gebucht. Dasselbe Konto, derselbe Betrag und dieselbe Richtung innerhalb von
sechs Stunden werden eine Buchung.

Die echte Anmeldung mit Telefon, PIN und Bestätigung in der App ist nicht Teil der automatischen Tests.

### Ideen, nicht umgesetzt

- Soll ein Kurzbefehl das Trade-Republic-Girokonto anlegen, wenn es fehlt?
- Soll das Fenster von sechs Stunden länger sein, wenn die Bankmitteilung erst am nächsten Morgen kommt?
- Soll ein Kurs aus der Sitzung gespeichert werden, oder bleibt die bisherige Kursaktualisierung die einzige Quelle?
