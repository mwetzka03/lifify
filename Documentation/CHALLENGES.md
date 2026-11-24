# Lifify – Challenges

[English](#english) · [Deutsch](#deutsch)

## English

### What you can do

- Challenges and groups with repeats, check-offs, streaks, freezes, and a
  growing coin multiplier. Categories: sport, abstinence, other, and your own.
- A calendar event is a time slot: challenges with minutes fill it, several
  one-time challenges can share it, and it moves to the real duration once all
  are checked.
- Abstinence runs a timer, pays coins each day, and pays bonuses at milestones.
- Automatic challenges: the calorie challenge follows the meals, and the step
  challenge follows Apple Health. Neither can be checked by hand.
- A reward shop and a wallet. The wallet may go below zero; the shop is then
  locked. Rewards can be one-time or repeatable.
- iPhone reminders appear as suggestions and become challenges only when you
  take them; their done state is written back.
- Up to four challenges can be pinned. Symbols can be chosen freely.

### Time slots and groups

- A challenge can have an estimated duration in minutes.
- A calendar event is a time slot. Challenges are assigned to it until its
  minutes are used up.
- Two or more challenges on one event form a group named "Event – Day".
  Groups can also be made and filled by hand.
- Sport and abstinence have no minutes and always take an event alone.
- Only one-time challenges can share an event. A recurring challenge may only
  take an empty event alone.
- When all challenges of an event are checked, the event moves to the real
  duration: the end is the last check, the start is the end minus the actual
  minutes. In the iOS calendar the old event is deleted and created anew.
- Past days can be checked afterward.
- The direct event link and the event's member list stay separate; only the
  direct link sets the streak target.

### Training and sport challenges

- A training plan, a challenge, and an event can be linked many-to-many.
  Several plans can hang on one recurring event; finishing one of them checks
  the challenge.
- After training, the event moves to the real training time, rounded to five
  minutes. Past training events without a matching training are deleted, also
  in the iOS calendar.
- A sport challenge with a linked training finishes only when the training
  ends, not by hand.

### Automatic challenges

- The calorie challenge counts a day when the confirmed meals fit the body
  goal. A day without meals does not spend a freeze. Details are in
  [HEALTH.md](HEALTH.md).
- The step challenge counts a day when Apple Health reports the step goal.
  Lifify reads the steps in the background and when it opens, and books
  reached days late if needed.
- Automatic challenges cannot be checked by hand, by Siri, or in a widget, and
  cannot be placed in a time slot.

### Coins, streaks, and shop

- Each check pays the challenge's coins. A running streak raises a coin
  multiplier. A challenge starts with two freezes; a freeze covers a missed
  day so the streak survives.
- Coins are pure gamification. The wallet may go below zero; the shop is then
  locked until the balance is back at zero or above. The automatic fast-food
  purchase books even while the shop is locked.
- The birthday pays 500 coins once a year.

## Deutsch

### Was möglich ist

- Challenges und Gruppen mit Wiederholungen, Haken, Streaks, Freezes und einem
  wachsenden Coin-Multiplikator. Kategorien: Sport, Abstinenz, Sonstiges und
  eigene.
- Ein Kalendertermin ist ein Zeit-Slot: Challenges mit Minuten füllen ihn,
  mehrere einmalige Challenges können ihn teilen, und er rückt auf die echte
  Dauer, sobald alle abgehakt sind.
- Abstinenz läuft mit Timer, zahlt täglich Coins und Boni an Meilensteinen.
- Automatische Challenges: Die Kalorien-Challenge folgt den Mahlzeiten, die
  Schritt-Challenge Apple Health. Beide lassen sich nicht von Hand abhaken.
- Belohnungsshop und Wallet. Das Wallet darf ins Minus; dann ist der Shop
  gesperrt. Belohnungen sind einmalig oder mehrfach einlösbar.
- iPhone-Erinnerungen erscheinen als Empfehlungen und werden erst durch
  Übernahme zu Challenges; ihr Erledigt-Status wird zurückgeschrieben.
- Bis zu vier Challenges lassen sich anheften. Symbole sind frei wählbar.

### Zeit-Slots und Gruppen

- Eine Challenge kann eine geschätzte Dauer in Minuten haben.
- Ein Kalendertermin ist ein Zeit-Slot. Ihm werden Challenges zugewiesen, bis
  seine Minuten aufgebraucht sind.
- Ab zwei Challenges an einem Termin entsteht eine Gruppe „Termin – Tag“.
  Gruppen lassen sich auch von Hand anlegen und füllen.
- Sport und Abstinenz haben keine Minuten und belegen einen Termin immer
  allein.
- Einen Termin teilen können sich nur einmalige Challenges. Eine
  wiederkehrende Challenge darf nur einen leeren Termin allein belegen.
- Sind alle Challenges eines Termins abgehakt, rückt der Termin auf die echte
  Dauer: Ende ist der letzte Haken, Start ist Ende minus Ist-Minuten. Im
  iOS-Kalender wird der alte Termin gelöscht und neu angelegt.
- Vergangene Tage sind nachträglich abhakbar.
- Direkte Terminverknüpfung und Mitgliederliste des Termins bleiben getrennt;
  nur die direkte Verknüpfung bestimmt das Streak-Soll.

### Training und Sport-Challenges

- Trainingsplan, Challenge und Termin lassen sich n:m verknüpfen. An einem
  wiederkehrenden Termin können mehrere Pläne hängen; wird einer absolviert,
  ist die Challenge abgehakt.
- Nach dem Training rückt der Termin auf die echte Trainingszeit, auf fünf
  Minuten gerundet. Vergangene Trainingstermine ohne passendes Training werden
  gelöscht, auch im iOS-Kalender.
- Eine Sport-Challenge mit verknüpftem Training ist nur durch das Beenden des
  Trainings erledigt, nicht von Hand.

### Automatische Challenges

- Die Kalorien-Challenge zählt einen Tag, wenn die bestätigten Mahlzeiten zum
  Körperziel passen. Ein Tag ohne Mahlzeiten verbraucht keinen Freeze. Details
  stehen in [HEALTH.md](HEALTH.md).
- Die Schritt-Challenge zählt einen Tag, wenn Apple Health das Schrittziel
  meldet. Lifify liest die Schritte im Hintergrund und beim Öffnen und bucht
  erreichte Tage bei Bedarf nach.
- Automatische Challenges lassen sich weder von Hand, per Siri noch im Widget
  abhaken und nicht in einen Termin legen.

### Coins, Streaks und Shop

- Jeder Haken zahlt die Coins der Challenge. Ein laufender Streak erhöht einen
  Coin-Multiplikator. Eine Challenge startet mit zwei Freezes; ein Freeze deckt
  einen verpassten Tag, damit der Streak hält.
- Coins sind reine Gamification. Das Wallet darf ins Minus; dann ist der Shop
  gesperrt, bis es wieder bei null oder darüber liegt. Der automatische
  Fast-Food-Kauf bucht auch bei gesperrtem Shop.
- Der Geburtstag zahlt einmal im Jahr 500 Coins.
