# Changes in 0.4.0

[English](#english) · [Deutsch](#deutsch)

This file is in English and in German. The finance calculations stay in
[FINANZEN.md](FINANZEN.md) and are unchanged. What changed in 0.3.0 is in
[CHANGES-0.3.0.md](CHANGES-0.3.0.md). The displayed version is 0.4.0.

## English

### Look

- Home, Challenges, Health, Settings, and setup sit on a mint-and-peach wash
  in light mode and on a deep green wash in dark mode. Cards and list rows
  keep their own fill, so light mode is not an empty white page and dark mode
  is not the old flat black.
- The finance view keeps its existing surface, type, and colors. Weitere
  Bereiche is the exception: those links use the same type as the tiles and
  less padding.
- Section titles, row text, captions, and values on the other screens share
  one type scale. Health section titles are no longer heavier than the rest.
- The symbol picker adds more symbols, including a hemp leaf and a cigarette.
  Those two are template drawings, so they take the surrounding color.

### Checks

- Finance and the other screens each have a unit check and an integration
  check. Further checks cover accounts, forecasts, budgets, the portfolio,
  import, backup, the shop, training sets, and the tab bar. Where a check can
  see a label, it asserts that label. The checks do not write user data. In
  the test list every category stays collapsed until it is opened.

### Not in this version

- Health data still survives an app reset.
- An empty challenge list can still overlap the recommendations.
- The week strip on Home can stop responding after one tap.
- Nutrition is still the placeholder “Not available yet”.
- There is no snapshot test, because this environment has no Xcode.
- Possible later work: abstinence templates, an iPad layout, widgets, and one
  shared calendar for Home and Challenges.

## Deutsch

### Aussehen

- Home, Challenges, Gesundheit, Einstellungen und die Einrichtung liegen im
  Hellen auf einem Minz- und Pfirsichgrund und im Dunkeln auf einem tiefen
  Grünton. Karten und Listen behalten eine eigene Füllung, damit der helle
  Modus keine leere weiße Seite ist und der dunkle Modus nicht das alte flache
  Schwarz.
- Die Finanzansicht behält Fläche, Schrift und Farben. Ausnahme ist Weitere
  Bereiche: die Links nutzen dieselbe Schrift wie die Kacheln und weniger
  Abstand.
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
  eingeklappt, bis sie geöffnet wird.

### Nicht in dieser Version

- Gesundheitsdaten überstehen ein Zurücksetzen der App weiterhin.
- Eine leere Challenge-Liste kann die Vorschläge weiterhin überdecken.
- Die Wochenleiste auf Home kann nach einem Tippen aufhören zu reagieren.
- Ernährung zeigt weiterhin „Noch nicht verfügbar“.
- Es gibt keinen Snapshot-Test, weil diese Umgebung kein Xcode hat.
- Möglich später: Abstinenz-Vorlagen, ein iPad-Layout, Widgets und ein
  gemeinsamer Kalender für Home und Challenges.
