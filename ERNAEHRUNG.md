# Nutrition

[English](#english) · [Deutsch](#deutsch)

This is what the nutrition board is for. The board itself is in the app.
Photo recognition is not connected, and no photo leaves the device.

## English

### What is in the app

Health has Training and Nutrition. Nutrition is one day at a time. Today is
the start, and earlier days can be filled in. A later day cannot.

A day shows the calorie target, what was eaten, what is left, and protein.
The goal is lose fat, maintain, or build muscle. A finished workout on that
day adds 250 kcal. The line under the board says the figure is an estimate,
not medical advice.

A meal can be added by hand. A photo can be attached too. Until recognition
is connected, the photo stays on the device and the values start empty. The
meal stays a draft. The person can type the values and tap Correct, or write
feedback and keep only that feedback. Confirming stores the meal on that day.
Deleting removes the meal and its photo.

Each meal can hold calories, protein, carbohydrates, fat, saturated fat,
omega-3, omega-6, fiber, vitamin D, vitamin B12, vitamin C, calcium, iron,
and magnesium. The first group is open. The rest sits under More settings.

### Who it is for

Settings starts with User, above General. User holds the name, the date of
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

### What recognition should do later

The main path is a photo of the plate. The model names the meal, estimates
the portion, and fills the nutrients above. The person sees that reading
before it is stored. If it is right, Correct stores it. If it is wrong, the
correction goes back with the same photo. Example: the photo is pasta, the
model says spaghetti bolognese, about one plate, and the person answers that
it is only pasta with tomato sauce, half a plate. The revised reading is
shown again before it is stored.

Hand entry stays available. The body profile, the goal, and whether a workout
was logged that day are part of the request, so the portion and the target
can use them. Nothing is sent until the person adds their own API key and
turns recognition on. The key stays on the device. There is no Lifify
account and no Lifify server for this.

### Which API fits

OpenAI **GPT-4.1** through the Responses API is the best fit. It accepts the
photo, it can be told to answer with a fixed JSON schema, and a second turn
can take the person's correction without starting over. The request would
carry the image, the draft nutrients, the correction text, age, height,
weight, sex, the goal, and whether that day has a workout.

Google **Gemini 2.5 Flash** is the cheaper alternative with the same shape:
one image, one JSON object, one follow-up turn. It is the right second
choice if the cost of GPT-4.1 is too high. Portion sizes are the part to
compare before switching.

Either way the app should trust only the JSON fields it knows, show them for
confirmation, and keep the photo local if the request fails.

## Deutsch

### Was in der App ist

Gesundheit hat Training und Ernährung. Ernährung gilt immer für einen Tag.
Heute ist der Anfang, frühere Tage lassen sich nachtragen. Ein späterer Tag
geht nicht.

Ein Tag zeigt das Kalorienziel, das Gegessene, das Übrige und das Eiweiß.
Das Ziel ist Fett verlieren, Halten oder Muskeln aufbauen. Ein abgeschlossenes
Training an dem Tag gibt 250 kcal dazu. Unter der Ansicht steht, dass die
Zahl eine Schätzung ist und keine medizinische Beratung.

Eine Mahlzeit lässt sich von Hand anlegen. Ein Foto kann auch angehängt
werden. Solange die Erkennung nicht verbunden ist, bleibt das Foto auf dem
Gerät und die Werte starten leer. Die Mahlzeit bleibt ein Entwurf. Die Person
kann die Werte eintragen und auf Stimmt tippen, oder eine Rückmeldung
schreiben und nur die behalten. Bestätigen speichert die Mahlzeit an dem Tag.
Löschen entfernt die Mahlzeit und ihr Foto.

Jede Mahlzeit kann Kalorien, Eiweiß, Kohlenhydrate, Fett, gesättigte
Fettsäuren, Omega-3, Omega-6, Ballaststoffe, Vitamin D, Vitamin B12,
Vitamin C, Kalzium, Eisen und Magnesium halten. Die erste Gruppe ist offen.
Der Rest liegt unter Weitere Einstellungen.

### Für wen

Die Einstellungen beginnen mit Nutzer, über Allgemein. Nutzer hält den Namen,
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

### Was die Erkennung später tun soll

Der Hauptweg ist ein Foto vom Teller. Das Modell nennt die Mahlzeit, schätzt
die Portion und füllt die Nährstoffe oben. Die Person sieht diese Lesung,
bevor sie gespeichert wird. Stimmt sie, speichert Stimmt sie. Stimmt sie
nicht, geht die Korrektur mit demselben Foto zurück. Beispiel: das Foto zeigt
Nudeln, das Modell sagt Spaghetti Bolognese, etwa ein Teller, und die Person
antwortet, es seien nur Nudeln mit Tomatensauce, ein halber Teller. Die neue
Lesung wird wieder gezeigt, bevor sie gespeichert wird.

Die Eingabe von Hand bleibt. Das Körperprofil, das Ziel und ob an dem Tag ein
Training gespeichert ist, gehören zur Anfrage, damit Portion und Ziel sie
nutzen können. Es wird nichts geschickt, bis die Person einen eigenen
API-Schlüssel einträgt und die Erkennung einschaltet. Der Schlüssel bleibt
auf dem Gerät. Dafür gibt es kein Lifify-Konto und keinen Lifify-Server.

### Welche API passt

OpenAI **GPT-4.1** über die Responses-API passt am besten. Sie nimmt das
Foto, sie lässt sich auf ein festes JSON-Schema festlegen, und eine zweite
Runde kann die Korrektur der Person aufnehmen, ohne von vorn zu beginnen. Die
Anfrage würde das Bild, die Entwurfsnährstoffe, den Korrekturtext, Alter,
Größe, Gewicht, Geschlecht, das Ziel und ob der Tag ein Training hat,
mitnehmen.

Google **Gemini 2.5 Flash** ist die günstigere Alternative mit derselben
Form: ein Bild, ein JSON-Objekt, eine Nachrunde. Sie ist die richtige zweite
Wahl, wenn GPT-4.1 zu teuer ist. Die Portionsgrößen sind der Teil, den man
vor einem Wechsel vergleichen sollte.

In beiden Fällen sollte die App nur die JSON-Felder glauben, die sie kennt,
sie zur Bestätigung zeigen und das Foto lokal behalten, wenn die Anfrage
fehlschlägt.
