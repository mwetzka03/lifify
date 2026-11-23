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

### Code

**Small methods, no duplication**

- A method does one thing. Guideline: at most about 30 lines. A longer
  method is split into helpers whose names say what they do, so the outer
  method reads like a short list of steps.
- Logic that appears a second time moves into one shared function or type in
  the right package. Copies are not allowed, including copied view code.
- Reuse goes through **protocols with default implementations** (protocol
  extensions), generics, and composition. This is Swift's form of
  inheritance and works for structs, enums, and classes alike.
- Class inheritance only where it really models an “is a” relationship or a
  framework requires it. SwiftData model inheritance needs iOS 26 and is not
  used while the app supports iOS 17.
- SwiftUI: shared look and behavior go into `ViewModifier`s and small
  subviews, not into repeated modifier chains.
- An `enum` with only static functions is fine as a namespace. Data with
  behavior is a `struct` (or a class where reference semantics are needed)
  that conforms to the right protocols.

**Documentation in the code**

- Every type (struct, class, enum, protocol, extension with its own purpose)
  and every method or property that is not trivially private gets a `///`
  comment above it: one or two sentences on what it does, and why when that
  is not obvious.
- Longer methods (more than about 15 lines) or methods with parameters whose
  meaning is not obvious also list their input and output in DocC form:

  ```swift
  /// Builds the forecast for one finance period.
  ///
  /// - Parameters:
  ///   - period: The salary or calendar period to forecast.
  ///   - entries: All bookings of the selected accounts.
  /// - Returns: Booked and open income and expenses of the period.
  func forecast(for period: FinancePeriod, entries: [LedgerEntry]) -> PeriodForecast
  ```

- Short, self-explanatory methods only get the summary line.
- Comments inside a method explain why, not what. Code comments are in
  English, like the rest of the code.
- Code that is touched for any reason is brought up to these rules in the
  same change.

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

### Code

**Kleine Methoden, keine Doppelungen**

- Eine Methode erledigt eine Aufgabe. Richtwert: höchstens etwa 30 Zeilen.
  Eine längere Methode wird in Hilfsmethoden zerlegt, deren Namen sagen, was
  sie tun, so dass die äußere Methode wie eine kurze Liste von Schritten
  lesbar ist.
- Logik, die ein zweites Mal vorkommt, wandert in eine gemeinsame Funktion
  oder einen gemeinsamen Typ im passenden Package. Kopien sind nicht erlaubt,
  auch kein kopierter View-Code.
- Wiederverwendung läuft über **Protokolle mit Standard-Implementierungen**
  (Protocol Extensions), Generics und Komposition. Das ist die Swift-Form der
  Vererbung und funktioniert für Structs, Enums und Klassen gleichermaßen.
- Klassenvererbung nur, wo sie wirklich eine „ist ein“-Beziehung abbildet
  oder ein Framework sie verlangt. Vererbung bei SwiftData-Modellen braucht
  iOS 26 und wird nicht genutzt, solange die App iOS 17 unterstützt.
- SwiftUI: Gemeinsames Aussehen und Verhalten gehört in `ViewModifier` und
  kleine Unter-Views, nicht in wiederholte Modifier-Ketten.
- Ein `enum` nur mit statischen Funktionen ist als Namensraum in Ordnung.
  Daten mit Verhalten sind ein `struct` (oder eine Klasse, wo
  Referenzsemantik nötig ist), das die passenden Protokolle erfüllt.

**Dokumentation im Code**

- Jeder Typ (Struct, Klasse, Enum, Protokoll, Extension mit eigenem Zweck)
  und jede Methode oder Eigenschaft, die nicht trivial privat ist, bekommt
  darüber einen `///`-Kommentar: ein bis zwei Sätze, was sie tut, und warum,
  wenn das nicht offensichtlich ist.
- Längere Methoden (mehr als etwa 15 Zeilen) oder Methoden mit Parametern,
  deren Bedeutung nicht offensichtlich ist, nennen zusätzlich Eingabe und
  Ausgabe im DocC-Format (`- Parameters:`, `- Returns:`, ggf. `- Throws:`),
  wie im englischen Beispiel oben.
- Kurze, selbsterklärende Methoden bekommen nur die Zusammenfassung.
- Kommentare innerhalb einer Methode erklären das Warum, nicht das Was.
  Code-Kommentare sind wie der übrige Code auf Englisch.
- Code, der aus irgendeinem Grund angefasst wird, wird in derselben Änderung
  auf diese Regeln gebracht.

### Design

Der gewählte Stil ist Grün, Blau, Bordeaux oder Violett, und das
Erscheinungsbild bleibt System, Hell oder Dunkel. Die Tableiste, die
Zeitraumwahl auf Home, die Symbole in den Einstellungen, Links, hervorgehobene
Zeilen, Karten und die Zeilen von Listen oder Formularen nutzen diesen Stil.
Auf diesen Flächen bleibt kein Systemblau und kein schwarz-weißer
Listenhintergrund übrig. Positive Beträge bleiben grün, negative rot. Symbole,
die man für eine Challenge gewählt hat, und die Symbole an Finanzbuchungen
behalten ihre eigene Farbe.
