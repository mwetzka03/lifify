# Changes in 0.4.0

[English](#english) · [Deutsch](#deutsch)

This file is in English and in German. The finance calculations stay in
[FINANZEN.md](FINANZEN.md) and are unchanged. What changed in 0.3.0 is in
[CHANGES-0.3.0.md](CHANGES-0.3.0.md). The displayed version is 0.4.0.

## English

### Look

- Challenges use a card grid: two cards in a row. A section with one card, or
  a leftover card, uses the full width. The title sits to the right of the
  symbol and lines up with its middle. Coins and the streak sit on the right.
  A duration shows in the same green caption as a linked event. A group is one
  wide card above those. Health is one framed row of three switches, Training,
  Abstinence, and Nutrition. The chosen switch changes the board underneath.
  Long-press a card to edit or delete it.
- The shop and coin capsules in the Challenges bar are as tall as the plus
  button. In the shop, the reward title lines up with the middle of its symbol.
- Recommendations leave more room around each Accept button.
- Finance keeps the account choice pinned at the top. The choices are bubbles
  in a row. A long name wraps to the next row, and that row shares the space
  evenly. All accounts, each account, and Portfolio stay the same views.
- In Challenge settings, the streak multiplier and the abstinence bonus are
  bubbles. Tap a step, then type the factor underneath. More settings on a new
  challenge or event starts closed.
- Home, Challenges, Health, Settings, and setup sit on a mint-and-peach wash
  in light mode and on a deep green wash in dark mode. Cards and list rows
  keep their own fill, so light mode is not an empty white page and dark mode
  is not the old flat black.
- Finance keeps the same arrangement of tiles, forecasts, and transactions.
  It now uses the same light and dark wash as the other screens. The links
  under More are a step larger than the tile titles, and the gap above
  Forecasts is tighter.
- In General, the daily briefing is a row of day circles, Mo through Su.
  Tap a circle to include that day. The time sits in the row underneath.
  Developer mode sits above the version, and the version stays last.
- Dates follow the device time zone, the way Calendar and Clock do. Changing
  the time zone keeps a developer day on the calendar day you picked and
  reschedules the pushes. The daily briefing stays at the same local time.
  An abstinence bonus stays the same instant, and developer mode still uses
  the real clock for those pushes.
- An abstinence bonus opens with a short cheer. The message still names the
  challenge, the step, and the coins.
- A new challenge or event starts with the fields you need first. Reminders,
  the linked event, streaks, and the group sit under More settings, which
  starts closed. Saving to Apple Reminders stays on unless you turn it off.
- Section titles, row text, captions, and values on the other screens share
  one type scale. Health section titles are no longer heavier than the rest.
- The symbol picker adds more symbols, including a hemp leaf and a cigarette.
  Those two are template drawings, so they take the surrounding color.

### Checks

- Finance and the other screens each have a unit check and an integration
  check. Further checks cover accounts, forecasts, budgets, the portfolio,
  import, backup, the shop, training sets, and the tab bar. Where a check can
  see a label, it asserts that label. The checks do not write user data. In
  the test list every category stays collapsed until it is opened. Categories
  are sorted alphabetically by their title. Tapping a check opens a page with
  what the check does, then each step with the expected result, the measured
  result, and the file that step reads.

### Not in this version

- Health data still survives an app reset.
- An empty challenge list can still overlap the recommendations.
- The week strip on Home can stop responding after one tap.
- Nutrition is still the placeholder “Not available yet”.
- There is no snapshot test, because this environment has no Xcode.
- Possible later work: abstinence templates, an iPad layout, widgets, and one
  shared calendar for Home and Challenges.
- Further notifications are not built yet: a nudge for an open challenge, a
  streak that is about to break, a streak milestone, the birthday bonus, a
  savings-plan debit, and a budget that is nearly spent.

## Deutsch

### Aussehen

- Challenges nutzen ein Kartenraster: zwei Karten in einer Reihe. Eine einzelne
  Karte oder eine übrige Karte nutzt die volle Breite. Der Titel steht rechts
  neben dem Symbol und auf dessen Mitte. Coins und die Serie stehen rechts.
  Eine Dauer erscheint in derselben grünen Zeile wie ein verknüpfter Termin.
  Eine Gruppe ist eine breite Karte darüber. Gesundheit ist eine umrahmte
  Reihe aus drei Schaltern, Training, Abstinenz und Ernährung. Der gewählte
  Schalter wechselt die Ansicht darunter. Ein langes Drücken bearbeitet oder
  löscht eine Karte.
- Die Shop- und Coin-Kapseln in der Challenge-Leiste sind so hoch wie das
  Plus. Im Shop steht der Titel der Belohnung auf der Mitte des Symbols.
- Die Vorschläge lassen mehr Abstand um jeden Übernehmen-Knopf.
- Finanzen behält die Kontoauswahl oben fest. Die Auswahl sind Blasen in einer
  Reihe. Ein langer Name bricht in die nächste Reihe, und diese Reihe teilt
  den Platz gleichmäßig. Alle Konten, jedes Konto und das Depot bleiben
  dieselben Ansichten.
- Unter Herausforderung sind Streak-Multiplikator und Abstinenz-Bonus Blasen.
  Ein Tipp wählt die Stufe, danach setzt man den Faktor. Weitere Einstellungen
  bei einer neuen Challenge oder einem neuen Termin starten geschlossen.
- Home, Challenges, Gesundheit, Einstellungen und die Einrichtung liegen im
  Hellen auf einem Minz- und Pfirsichgrund und im Dunkeln auf einem tiefen
  Grünton. Karten und Listen behalten eine eigene Füllung, damit der helle
  Modus keine leere weiße Seite ist und der dunkle Modus nicht das alte flache
  Schwarz.
- Finanzen behält die Anordnung von Kacheln, Prognosen und Buchungen. Die
  Ansicht nutzt jetzt dieselbe helle und dunkle Fläche wie die anderen
  Bildschirme. Die Links unter Weitere Bereiche sind eine Stufe größer als die
  Kacheltitel, und der Abstand über den Prognosen ist enger.
- Unter Allgemein ist das tägliche Briefing eine Reihe Kreise von Mo bis So.
  Ein Tipp nimmt den Tag auf oder heraus. Die Uhrzeit steht in der Reihe
  darunter. Der Entwicklermodus steht über der Version, und die Version bleibt
  ganz unten.
- Daten folgen der Zeitzone des Geräts, so wie Kalender und Uhr. Wechselt die
  Zeitzone, bleibt ein Entwicklertag auf dem gewählten Kalendertag, und die
  Mitteilungen werden neu gesetzt. Das Tagesbriefing bleibt zur selben
  Ortszeit. Ein Abstinenz-Bonus bleibt derselbe Augenblick, und der
  Entwicklermodus nutzt für diese Mitteilungen weiter die echte Uhr.
- Ein Abstinenz-Bonus beginnt mit einem kurzen Jubel. Die Meldung nennt
  weiter die Challenge, die Stufe und die Coins.
- Eine neue Challenge oder ein neuer Termin beginnt mit den Feldern, die man
  zuerst braucht. Erinnerungen, der verknüpfte Termin, Streaks und die Gruppe
  liegen unter Weitere Einstellungen, und die Gruppe startet zu. In Apple
  Erinnerungen sichern bleibt an, bis man es ausschaltet.
- Abschnittstitel, Zeilentext, Beschriftungen und Werte auf den anderen
  Bildschirmen teilen sich eine Schriftgröße. Die Abschnittstitel unter
  Gesundheit sind nicht mehr schwerer als der Rest.
- Die Symbolauswahl enthält mehr Symbole, darunter ein Hanfblatt und eine
  Zigarette. Die beiden sind Zeichnungen, die die umgebende Farbe annehmen.

### Prüfungen

- Finanzen und die anderen Bildschirme haben je eine Unit- und eine
  Integrationsprüfung. Weitere Prüfungen decken Konten, Prognosen, Budgets,
  das Depot, den Import, die Sicherung, den Shop, Trainingssätze und die
  Tableiste ab. Wo eine Prüfung eine Beschriftung sehen kann, prüft sie diese.
  Die Prüfungen schreiben keine Nutzerdaten. In den Tests ist jede Kategorie
  eingeklappt, bis sie geöffnet wird. Die Kategorien stehen alphabetisch nach
  ihrem Titel. Ein Tipp auf eine Prüfung öffnet eine Seite mit dem, was die
  Prüfung tut, danach jeden Schritt mit dem erwarteten Ergebnis, dem gemessenen
  Ergebnis und der Datei, die der Schritt liest.

### Nicht in dieser Version

- Gesundheitsdaten überstehen ein Zurücksetzen der App weiterhin.
- Eine leere Challenge-Liste kann die Vorschläge weiterhin überdecken.
- Die Wochenleiste auf Home kann nach einem Tippen aufhören zu reagieren.
- Ernährung zeigt weiterhin „Noch nicht verfügbar“.
- Es gibt keinen Snapshot-Test, weil diese Umgebung kein Xcode hat.
- Möglich später: Abstinenz-Vorlagen, ein iPad-Layout, Widgets und ein
  gemeinsamer Kalender für Home und Challenges.
- Weitere Mitteilungen sind noch nicht gebaut: ein Stups für eine offene
  Challenge, eine Serie, die abreißt, eine Streak-Stufe, der Geburtstagsbonus,
  eine Sparplan-Abbuchung und ein Budget, das fast aufgebraucht ist.
