# CLAUDE.md – Arbeitsanweisung für Lifify

Diese Datei liest Claude Code bei jedem Start. Sie hält fest, was mit dem
Eigentümer (mwetzka03) vereinbart wurde.

Stand: 24.11.2026. Version 0.5.5 ist in `main` gemergt. **Version 0.6.0** liegt
auf dem Branch `version0.6.0` und ist noch nicht auf einem echten iPhone
getestet. Teil B ist umgesetzt. Offen sind `DashboardView`, `TransactionsView`
und ein Teil der Methoden-Zerlegung aus A8.

Die erste Code-Analyse liegt als Claude Doc im Projekt „Lifify“:
„Lifify 0.5.0 – Code-Analyse und Rückfragen“. Was in 0.5.5 umgesetzt wurde,
steht in `Changes Documentation/CHANGES-0.5.5.md`.

---

## 1. Zusammenarbeit

- Ideen, Annahmen und Anweisungen kritisch prüfen. Nichts beschönigen,
  Schwachstellen, Trade-offs und Risiken klar benennen.
- Bei Unklarheiten vor der Umsetzung gezielt nachfragen. Zentrale
  Anforderungen nicht raten. **Alle Punkte, die in Abschnitt 4 mit „Vorher
  klären“ markiert sind, werden vor der Umsetzung mit dem Eigentümer
  geklärt.**
- Eigene Ideen sind erwünscht, werden aber **erst vorgeschlagen** (Nutzen,
  Aufwand) und nur nach Zustimmung umgesetzt.
- Jede Änderung nachvollziehbar dokumentieren: was, warum, Auswirkungen und
  Nebenwirkungen.
- Ton: sachlich, direkt, ehrlich, konstruktiv. Antworten auf Deutsch.
- **Funktionierendes Verhalten nicht entfernen.** Vieles wirkt verschachtelt,
  ist aber gewollt (siehe Abschnitt 3). Im Zweifel fragen.

## 2. Arbeitsweise im Repo

- Branch: `version0.6.0`, abgezweigt von `main`. **Ein Commit pro
  abgeschlossenem Schritt**, mit aussagekräftiger Commit-Message.
- Vor jedem Commit: bauen und testen (siehe unten). Ein Schritt ist erst
  fertig, wenn Build und Tests grün sind.
- Pushen und Löschen von Dateien außerhalb des vereinbarten Umbaus nur nach
  Rückfrage.
- Version überall auf **0.6.0** setzen (`MARKETING_VERSION` im Projekt,
  angezeigte Version in den Einstellungen, README, FEATURES).
- Changelog: neue Datei `Changes Documentation/CHANGES-0.6.0.md`, gegliedert
  wie `CHANGES-0.5.5.md`: Überblick, dann ein Abschnitt pro Bereich, kurze
  Aufzählungen statt langer Absätze. Englisch zuerst, dann Deutsch
  (RULES.md). Pro Änderung: was, warum, Auswirkung.
- README, FEATURES, FINANZEN, ERNAEHRUNG und RULES bei jeder betroffenen
  Änderung anpassen. Neue Rechenregeln (Renditeszenario, Tiefenanalyse,
  Dividendenprognose) gehören nach FINANZEN.md.
- Modular bauen: Fachlogik in die Packages (`LififyCore`, `LififyFinance`,
  `LififyChallenges`, `LififyHealth`), keine Fachlogik in Views. Neue Targets
  (Widget-Extension) nutzen dieselben Packages.
- **Code-Regeln aus RULES.md, Abschnitt „Code“, gelten für jede Zeile:**
  kleine Methoden, keine Doppelungen, Wiederverwendung über Protokolle,
  `///`-Doku über jedem Typ und jeder Methode, bei längeren Methoden mit
  Eingabe und Ausgabe.

### Bauen und testen (macOS, Xcode)

```bash
# Simulator-Namen ermitteln
xcrun simctl list devices available | grep iPhone

# Build
xcodebuild -project Lifify.xcodeproj -scheme Lifify \
  -destination 'platform=iOS Simulator,name=<iPhone-Name>' build

# Tests
xcodebuild -project Lifify.xcodeproj -scheme Lifify \
  -destination 'platform=iOS Simulator,name=<iPhone-Name>' test
```

Für den Simulator ist keine Signatur nötig. Für das echte iPhone wählt der
Eigentümer sein Team selbst in Xcode. Widgets, App Groups, HealthKit und
Live Activities brauchen Entitlements. Die dafür nötigen Schritte im
Apple-Developer-Konto beschreibt Claude dem Eigentümer, statt sie zu
raten.

## 3. Bestätigte Fachregeln (nicht ändern)

### Challenges, Zeit-Slots und Gruppen

- Challenges können eine geschätzte Dauer in Minuten haben.
- Ein Kalendertermin ist ein Zeit-Slot. Ihm werden Challenges zugewiesen,
  bis die Minuten aufgebraucht sind (`ChallengeTimeRules.fitCount`,
  `remaining`).
- Ab zwei Challenges an einem Termin entsteht eine Gruppe. Ihr Name ist
  „Termin – Tag“. Gruppen lassen sich auch manuell anlegen und befüllen.
- **Sport und Abstinenz haben keine Minuten und belegen einen Termin immer
  exklusiv.**
- **Einen Termin teilen können sich nur einmalige Challenges.** Eine
  wiederkehrende Challenge darf nur einen leeren Termin allein belegen.
- **Sind alle Challenges eines Termins abgehakt, wird der Termin auf die
  tatsächliche Dauer verschoben** (Ende = letzter Haken, Start = Ende minus
  Ist-Minuten). Im iOS-Kalender wird der alte Termin gelöscht und neu
  angelegt (`ChallengeTimeService.resize`).
- Vergangene Tage sind nachträglich abhakbar.
- Die direkte Terminverknüpfung und die Mitgliederliste des Termins bleiben
  getrennt: Nur die direkte Verknüpfung bestimmt das Streak-Soll.

### Training ↔ Challenge ↔ Termin

- Die Verknüpfung ist **n:m und gewollt**. An einem wiederkehrenden
  Apple-Termin (z. B. Sport) können mehrere Trainingspläne hängen. Wird
  **einer** davon absolviert, gilt die Challenge als abgehakt.
- Nach dem Training wird der Termin auf die echte Trainingszeit gesetzt
  (auf 5 Minuten gerundet, `WorkoutCalendarSync`).
- **Vergangene Trainingstermine ohne passendes Training werden gelöscht**,
  auch im iOS-Kalender (`WorkoutCalendarSync.cleanup`). Gewollt.
- Eine Sport-Challenge mit verknüpftem Training wird nur durch das Beenden
  des Trainings erledigt, nicht von Hand.
- Streaks gelten auch hier.

### Coins und Shop

- Coins sind reine Gamification.
- **Das Wallet darf ins Minus gehen.** Bei negativem Guthaben ist der Shop
  gesperrt, bis das Guthaben wieder bei 0 oder darüber liegt (umgesetzt in
  0.5.5).
- Der automatische Fast-Food-Kauf bucht auch bei gesperrtem Shop.

### Depot und Sparplan-Prognose

- Die Prognose existiert (`PortfolioActivity.futureShares`). Jede künftige
  Sparplan-Ausführung kauft Betrag ÷ **aktueller Kurs** Stücke. Ohne
  Renditeszenario gibt es keine Kursentwicklung. Das bleibt die
  Standardansicht. Das Renditeszenario (Abschnitt 4, B7) ist ein
  zusätzlicher Schalter.

### Trade Republic

- Der Live-Login über die inoffizielle Web-API **bleibt**. Die Risiken sind
  bekannt und akzeptiert.
- PIN wird nicht gespeichert, Sitzung wird nicht gespeichert, kein
  automatischer Abruf. Der PDF-Import bleibt.

### Kurzbefehle und URL-Schema

- `lifify://notice?account=…&text=…` und der AppIntent
  `RecordBankNoticeIntent` bleiben offen. Das ist für Apple Kurzbefehle
  gewollt (Bankmitteilung → Buchung).

### Onboarding

- Wird die App während der Ersteinrichtung geschlossen, beginnt die
  Einrichtung von vorn. Dabei gehen die Teildaten verloren. Gewollt.
- Nach abgeschlossener Einrichtung bleiben alle Daten erhalten.

## 4. Plan für 0.6.0

Jeder Schritt: (falls markiert) vorher klären → umsetzen → bauen → testen →
Doku anpassen → committen. Teil A zuerst, weil er die Grundlage für Teil B
verbessert. Innerhalb von Teil B ist die Reihenfolge ein Vorschlag; der
Eigentümer darf umsortieren.

### Teil A – Verbesserungen am Code (alle freigegeben)

**A1 – EventKit testbar machen**
- EventKit-Zugriffe (`EventKitSyncService`) hinter ein Protokoll legen. Die
  App nutzt die echte Implementierung, Tests eine Attrappe, die Aufrufe
  aufzeichnet.
- Tests für die Pfade, die heute ungetestet sind und echte Kalenderdaten
  löschen: Termin-Umschreiben nach dem Abhaken (`ChallengeTimeService`),
  `WorkoutCalendarSync.apply` und `cleanup`, Abstinenz-Boni über `settle`
  und Rückfall. Dazu die Wiederherstellung von Gesamt- und
  Gesundheits-Backup.
- Verhalten unverändert.

**A2 – Views verschlanken**
- Ein `@Observable`-Modell pro großem Screen, das Abfragen und Berechnungen
  hält. Zuerst `PortfolioView` (≈1.700 Zeilen), `ChallengesView` (≈1.700),
  `DashboardView` (≈1.300), `TransactionsView` (22 `@Query`) und
  `DataManagementView` (22 `@Query`).
- Ungefilterte `@Query` durch gefilterte Abfragen oder das Screen-Modell
  ersetzen.
- Verhalten und Aussehen unverändert. Performance vorher und nachher messen,
  wie in 0.5.5.
- Stand 23.11.2026: `PortfolioView` und `ChallengesView` sind umgebaut.
  `DashboardView`, `TransactionsView` und `DataManagementView` waren in der
  Messung nicht spürbar langsam und werden auf Wunsch des Eigentümers
  **zusammen mit A8** umgebaut.

**A3 – V2-Altspalten entfernen**
- `ChallengeItem.groupID`, `groupIDsRaw` und andere Spalten, die nach dem
  Umzug in 0.5.5 nicht mehr gelesen werden, über eingefrorene V2- und
  V3-Modellkopien und ein neues Schema V4 entfernen.
- Migrationstest: Ein Store aus 0.5.5 öffnet mit 0.6.0 und behält alle
  Daten.
- Erledigt: Nur `groupID` wurde entfernt. `groupIDsRaw` ist die aktuelle
  Quelle der Gruppenzugehörigkeit und bleibt.

**A4 – entfällt** (Entscheidung des Eigentümers, 23.11.2026): kein
automatischer Testlauf (CI).

**A5 – Doku lesbar halten**
- Der Changelog 0.5.5 ist aufgeräumt. In FINANZEN.md lange Fließtext-Absätze
  ebenso in Aufzählungen gliedern, ohne Regeln zu verlieren.
- Einrichtungstext angleichen: `OnboardingView` spricht beim Wiederherstellen
  noch von „nur Training“. Der Bereich heißt seit 0.5.5 Gesundheit
  (Trainings und Mahlzeiten).

**A6 – Entwicklermodus: Coins aus simulierten Tagen**
- Heute zahlt `AbstinenceService` Coins für simulierte Tage dauerhaft aus.
- Lösung: Jede Coin-Buchung, die entsteht, während ein simulierter Tag aktiv
  ist, wird markiert. Beim Zurücksetzen auf den echten Tag (und beim Start,
  wo `AppClock.resetSimulatedDay()` schon läuft) werden markierte Buchungen
  und die zugehörigen Auszahlungs-Merker entfernt. So bleibt der
  Entwicklermodus zum Testen nutzbar, ohne echte Coins zu verfälschen.
- Gemischte Nutzung von `Date.now` und `AppClock.now` prüfen und
  vereinheitlichen, wo es fachlich um „heute“ geht.

**A7 – Face ID nur für Finanzen**
- Beim Wechsel in den Finanzen-Tab wird mit Face ID (Fallback: Gerätecode)
  entsperrt. Der Rest der App bleibt ohne Sperre.
- Schalter in Einstellungen, Finanzen (Standard: an).
- Entsperrt bleibt Finanzen, bis die App in den Hintergrund geht.
- Widgets (B1): Solange die Face-ID-Sperre an ist, zeigen Finanz-Widgets
  ihre Beträge nur, wenn in Einstellungen, Finanzen der Schalter
  „Finanzwerte in Widgets zeigen“ an ist (Standard: aus). Sonst steht dort
  „Gesperrt“ mit einem Schloss.

**A8 – Code kompakter und dokumentiert (Wunsch des Eigentümers)**
- Regeln: RULES.md, Abschnitt „Code“. Sie gelten ab sofort für jede
  Änderung.
- Bestandsaufnahme: Der Code hat heute **kein einziges Protokoll**, rund
  260 Enums (meist Namensräume mit statischen Funktionen) und nur rund 370
  `///`-Zeilen bei rund 1.700 Funktionen.
- Durchgang Package für Package (Core, Finance, Challenges, Health, dann
  App-Target), je ein Commit:
  1. Doppelte Logik finden und in gemeinsame Funktionen, Typen oder
     Protokolle mit Standard-Implementierung zusammenführen.
  2. Methoden über etwa 30 Zeilen in benannte Hilfsmethoden zerlegen.
  3. `///`-Kommentare für alle Typen und nicht trivialen Methoden; bei
     Methoden über etwa 15 Zeilen zusätzlich `- Parameters:` und
     `- Returns:`.
- Verhalten unverändert; die Tests müssen ohne Anpassung grün bleiben. Wo
  ein Test angepasst werden muss, im Changelog begründen.
- Mit A2 (Views verschlanken) verzahnen: Was A2 ohnehin umbaut, wird dort
  gleich nach diesen Regeln gebaut.

### Teil B – Neue Features (freigegeben)

**B1 – Widgets (Home- und Sperrbildschirm)**
- Der Eigentümer hat die Auswahl freigegeben („kreativ werden“). Umfang:
  - **Tagesbudget** (klein): Restbudget heute und Tagesbudget als Ring in
    Budgetfarben; rot, wenn überschritten.
  - **Heute** (mittel): die nächsten 3–4 offenen Challenges des Tages,
    **interaktiv abhakbar** (AppIntent, iOS 17), dazu der nächste
    Termin-Slot. Sport-Challenges mit verknüpftem Training sind nicht
    abhakbar (Regel aus Abschnitt 3); stattdessen öffnet ein Tipp das
    Training.
  - **Coins & Streak** (klein): Wallet-Stand; bei Minus rot mit Hinweis
    „Shop gesperrt“; dazu der längste laufende Streak.
  - **Depot** (klein/mittel): Depotwert und Veränderung zum Vortag.
  - **Nächstes Training** (klein): Plan und Termin; ein Tipp öffnet die
    Session.
  - **Überblick** (groß): Budgetring, Challenges von heute, nächstes
    Training.
  - **Sperrbildschirm:** rund (Budget-Ring in %), rechteckig (nächste offene
    Challenge), Zeile (Coins).
- Finanz-Widgets folgen der Regel aus A7.
- Widgets aktualisieren sich nach jeder relevanten Änderung in der App
  (`WidgetCenter.reloadTimelines`) und zum Tageswechsel.
- Umsetzung (abweichend vom ursprünglichen Plan, Freigabe des Eigentümers
  steht aus): Der SwiftData-Store bleibt am alten Ort. Die App schreibt einen
  Snapshot in die App Group, Haken aus Widgets warten dort, bis die App sie
  bucht. So ist keine Migration des Speicherorts nötig.
- Die Schritte im Apple-Developer-Konto (App Group, Widget-Extension)
  beschreibt Claude dem Eigentümer.

**B2 – Siri und Kurzbefehle**
- Neue AppIntents neben `RecordBankNoticeIntent`: Challenge abhaken,
  Mahlzeit eintragen, Restbudget abfragen.
- Sport-Challenges mit verknüpftem Training sind über den Intent nicht
  abhakbar (Regel aus Abschnitt 3).

**B3 – Budget-Warnungen**
- Lokale Mitteilung, wenn eine variable Kostenposition bzw. ein Budgetpool
  80 % und 100 % erreicht, und wenn das Tagesbudget überschritten ist.
- Prüfung bei jeder neuen Buchung, auch aus Kurzbefehlen und Importen. Pro
  Schwelle und Zeitraum nur eine Mitteilung.
- Schwellen und Schalter in Einstellungen, Finanzen.
- Ein Bankimport mit vielen Altbuchungen löst keine Flut aus: Warnungen nur
  für den laufenden Zeitraum, gebündelt.

**B4 – Monatsrückblick**
- Ausgaben je Kategorie im abgelaufenen Zeitraum, verglichen mit dem
  Durchschnitt der letzten 3 bis 6 Zeiträume; die größten Abweichungen
  zuerst.
- Optional als Mitteilung zum Zeitraumwechsel.
- Zeitraum: folgt der Einstellung aus der Einrichtung
  (`dashboardPeriodMode`: Kalendermonat oder Gehaltszeitraum), wie der Rest
  der Finanzen. Ändert der Nutzer die Einstellung, folgt der Rückblick.
- Platz: als Eintrag unter Finanzen, Weitere Bereiche. Zum Zeitraumwechsel
  optional eine Mitteilung, die den Rückblick öffnet.

**B5 – Abo-Erkennung**
- Wiederkehrende Buchungen finden, die noch keine Fixkosten sind: derselbe
  Empfänger, ähnlicher Betrag (Toleranz z. B. ±10 %), regelmäßiger Abstand
  (wöchentlich, monatlich, jährlich), mindestens drei Vorkommen.
- Als Vorschlag anzeigen; mit einem Tipp als Fixkosten anlegen. Abgelehnte
  Vorschläge werden gemerkt und kommen nicht wieder. Die Ablehnungen kommen
  ins Backup.

**B6 – Dividenden-Übersicht und -Prognose**
- Übersicht der erhaltenen Dividenden je Position und je Monat bzw. Jahr,
  aus den bestehenden Ertrag-Buchungen.
- Prognose der nächsten 12 Monate: Dividende je Stück der letzten 12 Monate
  × heutige Stückzahl, inklusive künftiger Sparplan-Stücke, mit den
  bisherigen Zahlmonaten.
- Thesaurierende ETFs zahlen nichts und erscheinen nicht.

**B7 – Optionales Renditeszenario**
- Schalter in **Einstellungen → Finanzen → Depot**: „Renditeszenario“.
  Standard: aus. Kein Button in den Ansichten.
- Ist er an, wachsen in allen **künftigen** Prognosezeiträumen die
  **ETF-Bestände** mit einer jährlichen Rendite. Das betrifft das Depot und
  damit alle Ansichten, die den Depotwert enthalten (Gesamtvermögen, alle
  Konten). Vergangene und der laufende Zeitraum bleiben unverändert.
- **Nur ETFs.** Einzelaktien, Krypto und Sonstiges bleiben beim aktuellen
  Kurs.
- **Jeder ETF bekommt seine eigene Rendite** (entschieden):
  1. Gibt es mindestens 10 Jahre Kurshistorie: jährliche
     Durchschnittsrendite (CAGR) über 10 Jahre.
  2. Sonst, bei mindestens 5 Jahren: CAGR über 5 Jahre.
  3. Sonst: **3 % pro Jahr**.
- Kursquelle: Yahoo Finance (`range=10y`, Monatswerte). Die Rendite gilt für
  bestehende Stücke und für künftige Sparplan-Stücke dieses ETFs; monatlich
  zinseszinsartig gerechnet.
- In den Einstellungen steht pro ETF der verwendete Prozentsatz und seine
  Grundlage (10 J., 5 J. oder Standard 3 %). Er wird zwischengespeichert und
  mit der Kursaktualisierung erneuert.
- Prognosewerte mit Szenario sind in der Oberfläche als Szenario erkennbar
  (z. B. ein Hinweis unter dem Wert).
- Hebel-ETFs (z. B. Amundi MSCI USA Daily 2x Leveraged) bekommen ihre eigene
  historische Rendite wie jeder andere ETF; keine Sonderrechnung.
- **Vorher prüfen:** wie ein ETF zuverlässig erkannt wird (Yahoo
  `quoteType == "ETF"`, Typ aus Trade Republic oder beides). Erkennung im
  Depot sichtbar machen und von Hand korrigierbar.

**B8 – Depot-Anteile: Design und Tiefenanalyse**
- Die Anteile-Ansicht (Liste und Grafik) bekommt das Design der App: die
  Stile und Farbflächen wie die übrigen Screens, kein schlichtes Schwarz.
- Zwischen Grafik und Liste ein Umschalter: **Normal** | **Tiefenanalyse**.
  - Normal: wie heute.
  - Tiefenanalyse: ETFs werden in ihre Einzelwerte aufgebrochen. Für jede
    Aktie zählt der direkte Bestand plus der Anteil aus jedem ETF
    (ETF-Positionswert × Gewicht der Aktie im ETF). Ergebnis: Anteil jeder
    Aktie am gesamten Depot in Prozent. Grafik und Liste nutzen diese Werte.
  - **Nur Einträge mit mindestens 0,1 % Depotanteil** stehen einzeln in der
    Liste. Alles darunter wird zu **einer Zeile „Sonstige“** zusammengefasst
    (entschieden).
  - Hebel-ETFs zählen mit ihrem Hebel: Ein 2x-ETF trägt 2 × Positionswert
    × Gewicht bei. Die Summe kann dann über 100 % liegen; das wird unter der
    Liste erklärt.
- **ETFs des Eigentümers** (Stand 23.11.2026; Liste kann wachsen):
  - Xtrackers MSCI World (USD)
  - iShares Core MSCI World (USD)
  - iShares MSCI USA (USD)
  - Xtrackers MSCI World ex USA (USD)
  - Xtrackers Artificial Intelligence & Big Data (USD)
  - Amundi MSCI Emerging Markets (EUR)
  - iShares MSCI World Small Cap
  - Amundi MSCI USA Daily 2x Leveraged (EUR)
  - VanEck Rare Earth and Strategic Metals (USD)
  - iShares Space Technologies (USD; Name prüfen)
  - VanEck Space Innovators (USD)
  - VanEck Quantum Computing (USD)
  - ein MSCI World Consumer Staples (Anbieter noch unbekannt)
- **Datenquelle – vom Eigentümer am 23.11.2026 bestätigt (1 und 2
  automatisch, 3 als Rückfall):**
  1. **Adapter pro Anbieter**, automatisch abgerufen und zwischengespeichert:
     - iShares: Holdings-CSV der Fondsseite (`…ajax?fileType=csv…` bzw.
       `latest-holdings.csv`). Für UCITS-Fonds die deutsche oder britische
       Seite nutzen; die URL pro Fonds ermitteln und testen.
     - Xtrackers (DWS): Holdings-Download auf etf.dws.com, Excel.
     - VanEck: vollständige Holdings auf vaneck.com, Download prüfen.
     - Amundi: Zusammensetzung auf amundietf.com prüfen.
  2. **Index-Stellvertreter:** Fonds, die denselben Index abbilden, haben
     dieselben Gewichte. Ein synthetischer oder schwer abrufbarer Fonds
     (z. B. Amundi MSCI Emerging Markets, Amundi MSCI USA 2x als
     Swap-Konstruktion, deren Fondsbestand ein Ersatzkorb ist) nutzt die
     Gewichte eines iShares-Fonds auf denselben Index. Bei Swap-ETFs ist
     **nur der Index aussagekräftig, nicht der Fondsbestand.**
  3. **Manueller Import als Rückfall:** Der Eigentümer lädt eine
     Holdings-Datei (CSV oder Excel) über die Dateien-App, wenn ein Abruf
     scheitert oder ein Anbieter nicht unterstützt ist.
  - Excel-Dateien (`.xlsx`) sind ZIP-Archive mit XML. Ohne
    Drittanbieter-Bibliothek muss ein kleiner Leser gebaut werden
    (Entpacken über das `Compression`-Framework). Aufwand vorher nennen.
  - Keine Inhalte von Drittportalen wie justETF, Lightyear oder
    stockanalysis abgreifen (Nutzungsbedingungen, instabil).
- Zusammenführen derselben Unternehmen: zuerst über ISIN, sonst über
  Ticker und Börse, zuletzt über normalisierten Namen. Mehrere Aktiengattungen
  (z. B. Alphabet A und C) zu einem Unternehmen zusammenfassen.
- Aktualisierung: Zusammensetzungen ändern sich monatlich bis quartalsweise.
  Abruf höchstens einmal pro Woche oder von Hand; Stand-Datum pro ETF
  anzeigen.
- Neue externe Quellen im README unter Datenschutz nennen (es werden nur
  Fonds-IDs abgefragt, keine Nutzerdaten).

**B9 – Live Activity**
- **Nur** für den Trainings-Timer einer laufenden Session, auf
  Sperrbildschirm und Dynamic Island: Plan, aktuelle Übung, Satz, Zeit und
  Pausen-Timer. Keine Live Activities für Challenges (entschieden).

**B10 – Apple Health**
- Gewicht aus Apple Health lesen und die Körperdaten in den Einstellungen
  aktuell halten. Abgeschlossene Trainings als Workouts nach Apple Health
  schreiben.
- Nur nach ausdrücklicher Freigabe, Texte für die Berechtigungen in
  Info.plist. Ohne Freigabe funktioniert alles wie bisher.
- Zusätzlich lesen (entschieden): **Schritte**, **aktive Energie** und
  **Ruhepuls**. Anzeige im Gesundheit-Tab, Tageswerte und kurzer Verlauf als
  Zahlen (kein Diagramm-Zwang).
- **Schlaf** (`sleepAnalysis`) ist noch nicht entschieden, siehe unten.

**B11 – Progressive Overload**
- Pro Übung ein Gewichtsvorschlag für die nächste Session: Wurden in der
  letzten Session alle Zielwiederholungen geschafft, steigt das Gewicht um
  eine einstellbare Stufe (Standard 2,5 kg), sonst bleibt es gleich.
- Verlauf von Volumen (Sätze × Wiederholungen × Gewicht) pro Übung.
  Bestleistungen gibt es schon; darauf aufbauen.

**B12 – Mahlzeiten: Favoriten und „zuletzt gegessen“**
- Mahlzeiten mit einem Herz als Favorit markieren. Favoriten und die zuletzt
  gegessenen Mahlzeiten lassen sich mit einem Tipp erneut eintragen.
- Favoriten kommen ins Gesundheits-Backup.
- Kein Gewichts- oder Kalorien-Diagramm (ausdrücklich nicht gewünscht).

### Nicht gewünscht (nicht umsetzen)

- Sparziele, Sparerpauschbetrag, Gewichtsverlauf neben Kalorienbilanz,
  Challenge-Statistik und Wochen-Review.
- Automatischer Testlauf (CI, GitHub Actions).

### Noch nicht entschieden

- **Abhaken aus der Benachrichtigung:** Erinnerungen an Challenges
  bekommen Knöpfe wie „Erledigt“, mit denen man direkt in der Mitteilung
  abhakt, ohne die App zu öffnen. Der Eigentümer hat das noch nicht
  entschieden; nicht umsetzen, bis er zustimmt.
- **Schlaf aus Apple Health:** Der Eigentümer möchte wissen, wie das
  funktioniert, und hat noch nicht entschieden. Nicht umsetzen, bis er
  zustimmt.
- **Vorschläge, nicht freigegeben:** automatische Challenges aus
  Health-Werten (z. B. „10.000 Schritte“ hakt sich selbst ab). Erst
  vorschlagen.
- Spätere Ideen des Eigentümers: Desktop-Version oder ein lokales Dashboard
  über localhost.

## 5. Bekannte Widersprüche zwischen Doku und Code

- `MealRecognition.send(thinking: true)` setzt `thinkingBudget: 0`, schaltet
  das Nachdenken also gerade aus. Die Benennung ist irreführend und wird in
  A2 oder bei passender Gelegenheit bereinigt.

## 6. Technische Leitplanken

- iOS 17+, SwiftUI, SwiftData, Swift 6.
- Keine Drittanbieter-Abhängigkeiten, keine Secrets im Repo.
- Beträge als ganzzahlige Cent.
- Zweisprachige Texte über `L("Deutsch", "English")`.
- Stil: Grün, Blau, Bordeaux und Violett; kein Systemblau auf gestylten
  Flächen; positive Beträge grün, negative rot (RULES.md).
- Netzwerk nur, wo nötig (Yahoo Finance, Gemini mit Schlüssel, Trade
  Republic, ggf. ETF-Zusammensetzungen nach B8). Jede neue externe Quelle
  steht im README unter Datenschutz.
