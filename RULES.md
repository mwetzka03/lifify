# Rules

[English](#english) · [Deutsch](#deutsch)

These rules apply to every change in Lifify.

## English

### Language

Document a change in English and in German. English comes first. Each version
has its own changelog, as [CHANGES-0.5.5.md](Changes%20Documentation/CHANGES-0.5.5.md) does for 0.5.5.
Those version files live in Changes Documentation. The README and the other
documents stay at the top and stay bilingual in the same way.

### Tests

New behavior gets automated tests in `LififyTests`, written with Swift Testing
and grouped by topic. Test real rules, not constants or UI text against
themselves. Tests run through `withTestStore`, which provides an in-memory
database and a private UserDefaults suite, so they never write user data.
Services read UserDefaults through `AppDefaults.store`, never directly. A step
is finished when the build and all tests pass.

### Design

The selected style is Green, Blue, Bordeaux, or Violet, and Appearance is
still System, Light, or Dark. The tab bar, the Home period control, settings
icons, links, highlighted rows, cards, and list or form rows use that style.
Do not leave system blue, or a plain black or white list background, on those
surfaces. Positive amounts stay green and negative amounts stay red. Symbols
the user picked for a challenge, and the icons on finance entries, keep their
own colors.

## Deutsch

### Sprache

Eine Änderung wird auf Englisch und auf Deutsch dokumentiert. Englisch steht
zuerst. Jede Version hat ihr eigenes Änderungsprotokoll, so wie
[CHANGES-0.5.5.md](Changes%20Documentation/CHANGES-0.5.5.md) für 0.5.5. Diese
Versionsdateien liegen in Changes Documentation. Die README und die übrigen
Dokumente bleiben oben und auf dieselbe Weise zweisprachig.

### Tests

Neues Verhalten bekommt automatische Tests in `LififyTests`, geschrieben mit
Swift Testing und nach Thema gruppiert. Getestet werden echte Regeln, nicht
Konstanten oder UI-Texte gegen sich selbst. Tests laufen über `withTestStore`,
das eine In-Memory-Datenbank und eine eigene UserDefaults-Suite bereitstellt.
Sie schreiben also nie Nutzerdaten. Services lesen UserDefaults über
`AppDefaults.store`, nie direkt. Ein Schritt ist fertig, wenn Build und alle
Tests grün sind.

### Design

Der gewählte Stil ist Grün, Blau, Bordeaux oder Violett, und das
Erscheinungsbild bleibt System, Hell oder Dunkel. Die Tableiste, die
Zeitraumwahl auf Home, die Symbole in den Einstellungen, Links, hervorgehobene
Zeilen, Karten und die Zeilen von Listen oder Formularen nutzen diesen Stil.
Auf diesen Flächen bleibt kein Systemblau und kein schwarz-weißer
Listenhintergrund übrig. Positive Beträge bleiben grün, negative rot. Symbole,
die man für eine Challenge gewählt hat, und die Symbole an Finanzbuchungen
behalten ihre eigene Farbe.
