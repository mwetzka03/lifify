# Nutrition

[English](#english) · [Deutsch](#deutsch)

This is what the nutrition board is for. The board itself is in the app.
Photo recognition calls Gemini 2.5 Flash when a key is saved under Settings,
Health. Without that key, the photo stays on the device.

## English

### What is in the app

Health has Training and Nutrition. Nutrition is one day at a time. Today is
the start, and earlier days can be filled in. A later day cannot.

A day shows the calorie target, what was eaten, what is left, and protein.
The goal is lose fat, maintain, or build muscle. A finished workout on that
day adds 250 kcal.

A meal can be added by hand. A photo can be taken or chosen from the library.
A new photo stays in the app and is not saved to the library unless Health,
Nutrition, turns that on. The switch is off. With a Gemini key
under Health, the photo is sent and the reading fills the meal. Without a
key, the photo stays on the device and the values start empty. The meal stays
a draft until Correct. The person can type the values, or write feedback and
send the same photo again. Confirming stores the meal on that day. Deleting
removes the meal and its photo.

Tapping the date in the middle of the day bar opens a calendar. The arrows
still move one day. A future day cannot be selected.

Each meal has a kind: whole food, balanced, hearty, sweet, fast food, or
alcohol. The model picks one. The person can change it. Fast food buys the
Fast Food reward in the shop for 25 coins, even if the balance goes negative.
Changing the kind, or deleting the meal, refunds that purchase.

Staying at or under the calorie target pays the challenge Calorie deficit.
It lives under More, is daily, uses streaks, and is pinned the first
time it is created. The day pays 20 coins, or 30 when every confirmed meal
is whole food or balanced. Over the target, or a day with no confirmed meal,
pays nothing. The board shows that amount, including the streak multiplier,
and the fast-food debit in red. Archiving or unpinning the challenge does
not create a second one. Deleting it does.

Each meal can hold calories, protein, carbohydrates, fat, saturated fat,
omega-3, omega-6, fiber, vitamin D, vitamin B12, vitamin C, calcium, iron,
and magnesium. The first group is open. The rest sits under More settings.

### Who it is for

Settings starts with the name and profile photo, above General. The line
under the name is User settings. That page holds the name, the date of
birth, height in centimeters, weight in kilograms, sex, and the goal. Setup
asks for the same things after the name. The birthday still pays 500 coins
once that year.

Sex is female, male, or unspecified. The estimate needs it. Unspecified uses
the midpoint of the two formulas. Without height or weight there is no
calorie target, and the board says so.

### How the target is calculated

The resting energy is Mifflin–St Jeor, in kilocalories:

- male: `10 × kg + 6.25 × cm − 5 × age + 5`
- female: `10 × kg + 6.25 × cm − 5 × age − 161`
- unspecified: `10 × kg + 6.25 × cm − 5 × age − 78`

Age is the completed years on that day. If no birthday is stored, the
estimate uses 30.

Maintenance is 120 percent of that resting energy. Lifify does not ask for a
job, so the baseline is sedentary. The goal then takes a percent of
maintenance:

- lose fat: 85 percent
- maintain: 100 percent
- build muscle: 110 percent

The result does not go under a floor: 1200 for female, 1500 for male, and
1350 when sex is unspecified. A finished workout adds 250 kcal after that
floor. Example: a woman of 30 years, 165 cm, and 70 kg who wants to lose fat
lands on 1448 kcal, or 1698 kcal if she trained that day.

### What recognition does

The main path is a photo of the plate. Gemini names the meal, picks a kind,
estimates the portion, and fills the nutrients above. The person sees that
reading before it is stored. If it is right, Correct stores it. If it is
wrong, the correction goes back with the same photo. Example: the photo is
pasta, the model says spaghetti bolognese, about one plate, and the person
answers that it is only pasta with tomato sauce, half a plate. The revised
reading is shown again before it is stored.

Hand entry stays available. The body profile, the goal, and whether a workout
was logged that day are part of the request, so the portion can use them.
Nothing is sent until a Gemini key is saved under Health. The key stays in
the keychain on this device. It is not in backups and it is not logged.
There is no Lifify account and no Lifify server for this. If the request
fails, the photo stays, and the person can fill the values by hand.

### Which API the app calls

The app calls Google **Gemini 2.5 Flash** at
`generativelanguage.googleapis.com`, model `gemini-2.5-flash`, with the
header `x-goog-api-key`. The photo is a JPEG whose long edge is at most 768
pixels. The answer is one JSON object. A failed call is tried once more
without the thinking setting. After 1 December 2026 Google routes that model
name to Gemini 3.5 Flash-Lite at the same standard paid rate. The free tier
is $0, and Google may use that content to improve its products. The paid
rate is $0.30 per million input tokens and $2.50 per million output tokens.
A personal month of a few meal photos is under $1 on the paid rate.

OpenAI **GPT-4.1** is not connected. It remains the alternative if the Gemini
reading is not good enough: $2 per million input tokens and $8 per million
output tokens, or $0.40 and $1.60 for GPT-4.1 mini. ChatGPT Plus does not
pay the API.

## Deutsch

### Was in der App ist

Gesundheit hat Training und Ernährung. Ernährung gilt immer für einen Tag.
Heute ist der Anfang, frühere Tage lassen sich nachtragen. Ein späterer Tag
geht nicht.

Ein Tag zeigt das Kalorienziel, das Gegessene, das Übrige und das Eiweiß.
Das Ziel ist Fett verlieren, Halten oder Muskeln aufbauen. Ein abgeschlossenes
Training an dem Tag gibt 250 kcal dazu.

Eine Mahlzeit lässt sich von Hand anlegen. Ein Foto kann aufgenommen oder
aus der Galerie gewählt werden. Eine Aufnahme bleibt in der App und kommt
nicht in die Galerie, solange das unter Gesundheit, Ernährung, aus ist. Der
Schalter ist aus. Mit einem Gemini-Schlüssel unter Gesundheit wird das Foto geschickt
und die Lesung füllt die Mahlzeit. Ohne Schlüssel bleibt das Foto auf dem
Gerät und die Werte starten leer. Die Mahlzeit bleibt ein Entwurf, bis Stimmt
sie speichert. Die Person kann die Werte eintragen oder eine Rückmeldung
schreiben und dasselbe Foto noch einmal schicken. Bestätigen speichert die
Mahlzeit an dem Tag. Löschen entfernt die Mahlzeit und ihr Foto.

Ein Tipp auf das Datum in der Mitte der Tagesleiste öffnet einen Kalender.
Die Pfeile wechseln weiter einen Tag. Ein späterer Tag geht nicht.

Jede Mahlzeit hat eine Art: unverarbeitet, ausgewogen, deftig, süß, Fast Food
oder Alkohol. Das Modell wählt eine. Die Person kann sie ändern. Fast Food
kauft die Belohnung Fast Food im Shop für 25 Coins, auch wenn das Guthaben
dabei negativ wird. Ändert man die Art oder löscht die Mahlzeit, wird der
Kauf erstattet.

Wer am oder unter dem Kalorienziel bleibt, bekommt die Challenge
Kaloriendefizit. Sie steht unter Weitere, ist täglich, nutzt Streaks und wird
beim ersten Anlegen angepinnt. Der Tag zahlt 20 Coins, oder 30, wenn jede
bestätigte Mahlzeit unverarbeitet oder ausgewogen ist. Über dem Ziel, oder
ein Tag ohne bestätigte Mahlzeit, zahlt nichts. Die Ansicht zeigt diesen
Betrag inklusive Streak-Faktor und den Fast-Food-Abzug in Rot. Archivieren
oder Lösen legt keine zweite Challenge an. Löschen schon.

Jede Mahlzeit kann Kalorien, Eiweiß, Kohlenhydrate, Fett, gesättigte
Fettsäuren, Omega-3, Omega-6, Ballaststoffe, Vitamin D, Vitamin B12,
Vitamin C, Kalzium, Eisen und Magnesium halten. Die erste Gruppe ist offen.
Der Rest liegt unter Weitere Einstellungen.

### Für wen

Die Einstellungen beginnen mit dem Namen und dem Profilbild, über Allgemein.
Darunter steht Nutzereinstellungen. Diese Seite hält den Namen,
das Geburtsdatum, die Größe in Zentimetern, das Gewicht in Kilogramm, das
Geschlecht und das Ziel. Die Einrichtung fragt dasselbe nach dem Namen. Der
Geburtstag zahlt weiterhin einmal im Jahr 500 Coins.

Das Geschlecht ist weiblich, männlich oder keine Angabe. Die Schätzung
braucht es. Keine Angabe nimmt die Mitte der beiden Formeln. Ohne Größe oder
Gewicht gibt es kein Kalorienziel, und die Ansicht sagt das.

### Wie das Ziel gerechnet wird

Der Ruheumsatz ist Mifflin–St Jeor, in Kilokalorien:

- männlich: `10 × kg + 6,25 × cm − 5 × Alter + 5`
- weiblich: `10 × kg + 6,25 × cm − 5 × Alter − 161`
- keine Angabe: `10 × kg + 6,25 × cm − 5 × Alter − 78`

Das Alter sind die vollendeten Jahre an dem Tag. Ohne Geburtsdatum rechnet
die Schätzung mit 30.

Der Erhalt ist 120 Prozent dieses Ruheumsatzes. Lifify fragt nicht nach dem
Beruf, deshalb ist die Grundlage sitzend. Das Ziel nimmt dann einen Prozent
vom Erhalt:

- Fett verlieren: 85 Prozent
- Halten: 100 Prozent
- Muskeln aufbauen: 110 Prozent

Das Ergebnis fällt nicht unter eine Grenze: 1200 bei weiblich, 1500 bei
männlich und 1350 ohne Angabe. Ein abgeschlossenes Training gibt danach
250 kcal dazu. Beispiel: eine Frau, 30 Jahre, 165 cm und 70 kg, die Fett
verlieren will, landet bei 1448 kcal, oder bei 1698 kcal, wenn sie an dem
Tag trainiert hat.

### Was die Erkennung tut

Der Hauptweg ist ein Foto vom Teller. Gemini nennt die Mahlzeit, wählt eine
Art, schätzt die Portion und füllt die Nährstoffe oben. Die Person sieht
diese Lesung, bevor sie gespeichert wird. Stimmt sie, speichert Stimmt sie.
Stimmt sie nicht, geht die Korrektur mit demselben Foto zurück. Beispiel: das
Foto zeigt Nudeln, das Modell sagt Spaghetti Bolognese, etwa ein Teller, und
die Person antwortet, es seien nur Nudeln mit Tomatensauce, ein halber
Teller. Die neue Lesung wird wieder gezeigt, bevor sie gespeichert wird.

Die Eingabe von Hand bleibt. Das Körperprofil, das Ziel und ob an dem Tag ein
Training gespeichert ist, gehören zur Anfrage, damit die Portion sie nutzen
kann. Es wird nichts geschickt, bis unter Gesundheit ein Gemini-Schlüssel
steht. Der Schlüssel bleibt im Schlüsselbund auf diesem Gerät. Er steht nicht
in Sicherungen und nicht in Protokollen. Dafür gibt es kein Lifify-Konto und
keinen Lifify-Server. Schlägt die Anfrage fehl, bleibt das Foto, und die
Person kann die Werte von Hand setzen.

### Welche API die App aufruft

Die App ruft Google **Gemini 2.5 Flash** unter
`generativelanguage.googleapis.com` auf, Modell `gemini-2.5-flash`, mit dem
Header `x-goog-api-key`. Das Foto ist ein JPEG, dessen lange Kante höchstens
768 Pixel hat. Die Antwort ist ein JSON-Objekt. Eine fehlgeschlagene Anfrage
wird einmal ohne die Thinking-Einstellung wiederholt. Ab dem 1. Dezember 2026
leitet Google diesen Modellnamen auf Gemini 3.5 Flash-Lite um, zum selben
bezahlten Standardpreis. Die kostenlose Stufe ist 0 $, und Google darf diese
Inhalte zur Verbesserung seiner Produkte nutzen. Der bezahlte Preis ist
0,30 $ je Million Eingabe-Tokens und 2,50 $ je Million Ausgabe-Tokens. Ein
persönlicher Monat mit wenigen Essensfotos liegt auf dem bezahlten Preis
unter 1 $.

OpenAI **GPT-4.1** ist nicht verbunden. Sie bleibt die Alternative, wenn die
Gemini-Lesung nicht reicht: 2 $ je Million Eingabe-Tokens und 8 $ je Million
Ausgabe-Tokens, oder 0,40 $ und 1,60 $ für GPT-4.1 mini. ChatGPT Plus zahlt
die API nicht.
