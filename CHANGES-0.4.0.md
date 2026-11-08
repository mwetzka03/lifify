# Changes in 0.4.0

[English](#english) · [Deutsch](#deutsch)

This file is in English and in German. The finance calculations stay in
[FINANZEN.md](FINANZEN.md) and are unchanged. What changed in 0.3.0 is in
[CHANGES-0.3.0.md](CHANGES-0.3.0.md). The displayed version is 0.4.0.

## English

### Look

- Home, Challenges, Health, Settings, and setup use Liquid Glass. On iOS 26 the
  cards use the system glass. On earlier versions they use a thin material.
- The finance view, including Weitere Bereiche, keeps its existing surface,
  type, and colors.
- Section titles, row text, captions, and values on the other screens share
  one type scale. Health section titles are no longer heavier than the rest.
- The symbol picker adds more symbols, including a hemp leaf and a cigarette.
  Those two are template drawings, so they take the surrounding color.

### Checks

- Finance and the other screens each have a unit check and an integration
  check. The integration checks assert the labels the booking picker, the
  health sections, and the settings rows show. The checks do not write user data.

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

- Home, Challenges, Gesundheit, Einstellungen und die Einrichtung nutzen
  Liquid Glass. Ab iOS 26 verwenden die Karten das Systemglas. Davor nutzen
  sie ein dünnes Material.
- Die Finanzansicht, einschließlich Weitere Bereiche, behält Fläche, Schrift
  und Farben.
- Abschnittstitel, Zeilentext, Beschriftungen und Werte auf den anderen
  Bildschirmen teilen sich eine Schriftgröße. Die Abschnittstitel unter
  Gesundheit sind nicht mehr schwerer als der Rest.
- Die Symbolauswahl enthält mehr Symbole, darunter ein Hanfblatt und eine
  Zigarette. Die beiden sind Zeichnungen, die die umgebende Farbe annehmen.

### Prüfungen

- Finanzen und die anderen Bildschirme haben je eine Unit- und eine
  Integrationsprüfung. Die Integrationsprüfungen prüfen die Beschriftungen,
  die die Buchungsauswahl, die Gesundheitsabschnitte und die Einstellungszeilen
  zeigen. Die Prüfungen schreiben keine Nutzerdaten.

### Nicht in dieser Version

- Gesundheitsdaten überstehen ein Zurücksetzen der App weiterhin.
- Eine leere Challenge-Liste kann die Vorschläge weiterhin überdecken.
- Die Wochenleiste auf Home kann nach einem Tippen aufhören zu reagieren.
- Ernährung zeigt weiterhin „Noch nicht verfügbar“.
- Es gibt keinen Snapshot-Test, weil diese Umgebung kein Xcode hat.
- Möglich später: Abstinenz-Vorlagen, ein iPad-Layout, Widgets und ein
  gemeinsamer Kalender für Home und Challenges.
