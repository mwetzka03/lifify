# Finance rules

[English](#english) · [Deutsch](#deutsch)

## English

This file describes how Lifify calculates accounts, periods, income, expenses,
the portfolio, and the home budget. It applies to version 0.3.0.

Period and account are one shared filter. A change applies in the finance
view, in transactions, and in the income and expense lists.

### Accounts

- Account kinds are checking account, savings pot, parent savings pot, and
  portfolio.
- A parent savings pot groups savings pots and is not added to the total
  again.
- The main account is required and cannot be deleted.
- A portfolio is not liquid and must be linked to exactly one checking
  account. It cannot be created without that link.
- Several portfolios may be linked to different checking accounts. In the
  account filter they appear as one **Portfolio** entry. The individual
  portfolio accounts are not listed there separately.
- There is no separate “Portfolio” link under More. The same positions appear
  when **Portfolio** is selected in the filter.
- Settings can store a default checking account and a default fee for buys and
  sales. The fee starts turned off when booking.

### Period

- Back, forward, and Today sit above the finance list, so the change always
  registers.
- Periods follow the primary income when the salary period is active.
  Otherwise they are calendar months.
- The first period begins with the bookings of the main account. Its start is
  the cutoff date.
- Trade Republic bookings before the cutoff date are not created. Bookings on
  the cutoff date and after are created, even when the first period has
  already ended.
- Portfolio positions from the whole statement are still taken, including buys
  before the cutoff date.
- If the main account has no booking yet, there is no period yet. Then every
  statement row is booked.
- The opening balance of the first period is the right-hand balance on the
  statement before the start day, that is the last printed balance of the rows
  before it. If there is no such row, the statement’s opening balance is used.
- The balance is the checking-account balance after that row. It is never
  booked as a payment amount.
- This opening balance is stored as a balance adjustment on the start day. In
  the display it counts as the beginning of the period. Income and other
  bookings on the first day belong to the period, not to the opening balance.

### Balance across all accounts

When **All accounts** is selected, the opening balance is the sum of each
account’s own opening balance plus the portfolio value on the day before.

- Bookings on the first day, including income, are not part of the opening
  balance. A balance adjustment on that day remains the opening value.
- The portfolio value is the shares held at the end of the day before. Buys on
  the first day are missing from the opening balance and belong to the period.
- The price is that day’s closing price once it is stored. If it is missing,
  the current price is used and the share count stays historical.
- If the cutoff date is in the future, the current price is used. Savings
  plans that have not been booked yet increase the share count up to that day.
  Each execution adds as many shares as the plan amount buys at the current
  price. If the ETF costs €100 and the plan is €50, that is half a share,
  including across a year. The value of those shares is the euro amount, with
  no percentage growth. A plan without a matching position still counts only
  as a euro amount. On the linked checking account the same dates reduce the
  opening balance, so the total stays unchanged.
- In the portfolio list, the selected period shows that share count and the
  matching value. The change beside it remains the change of the shares
  already held.
- Opening balance and closing balance sit in the same row. Below them is the
  liquid balance without the portfolio, at the same digit size. The number may
  shrink slightly so both tiles fit side by side. Tiles in a row are the same
  height, even when a number or the note under it wraps.
- The closing balance is the opening balance plus the forecast difference.
  There is no further difference number under the closing balance. The
  forecast difference is booked plus open income, minus booked plus open
  expenses.
- In the current period, the word **Forecast** sits under the difference on
  its own line, and the amount sits under that, also alone. **Open** works the
  same way for income, expenses, fixed costs, and variable costs: the label
  above, the amount below. The large amount there stays what is already
  booked. For income, the large amount already includes the forecast, and Open
  shows only the part that is still open.
- If the whole period is in the future, there is no Open. The large amount is
  then the normal value, booked plus still open. For fixed costs that amount
  sits directly in the fixed-costs tile. The difference shows the forecast
  directly, with no second line.
- The fixed-cost tile shows only how much is booked and how much is open. It
  does not list each savings plan. A tap on that overview opens the
  savings-plans view. Ordinary fixed costs stay in their own list under More.
- A finished period shows only what was booked, with no Open and no forecast
  line.
- While the finance tiles calculate for the first time, or after a change of
  period or account, a loading indicator is shown. Short data changes at
  startup are folded into that one load. After that the tiles stay in place
  and the numbers update without emptying the view again. The filters stay
  usable. In the finance view the transactions below stay visible.
- When **Portfolio** is selected, the net-worth card shows the portfolio value
  at the end of the selected period, including savings plans that have not
  been booked yet, and the change. The positions sit directly below. Both
  appear without waiting for the other tiles. Income, expenses, opening
  balance, and closing balance are omitted there. More is omitted as well.

### Income and expenses

#### All accounts

Income is:

- Inflows from a foreign IBAN or a foreign account
- Dividends (yield)
- Interest
- The positive purchase-to-sale difference of a stock sale

Inflows from your own IBAN, the full sale proceeds, and a refund do not count
as income.

A sale is compared with cost basis and fees. The proceeds are the payment
amount after the fee. The cost basis is the average purchase price of the
shares sold, including purchase fees. Only the difference appears:

- positive, as income
- negative, as an expense
- zero is not shown

Stock buys and savings plans are not expenses when all accounts are selected.
The money only moves from the checking account into the portfolio. Other
transfers between your own accounts do not count as income or an expense
either.

#### Linked checking account

When the checking account linked to the portfolio is selected, buys, savings
plans, and sales count at the full amount. An outflow is an expense, an
inflow is income. The purchase-to-sale difference is not counted again on top.

#### Another single account

Transfers that touch this account count there in full. Portfolio buys of
another checking account do not appear.

#### Income forecasts

A forecast with an account applies only to that account. The income list and
the income tile of a single account show only that account’s forecasts. A
forecast without an account appears only for all accounts, not on a single
account. The same applies to the opening balance: each account calculates only
with its own forecasts.

The income view lists every still-open date in the period, not only the next
one. When exactly one account is selected, transfer forecasts whose money
arrives in that account are listed there as well. All accounts and the
portfolio do not list transfers there. New income forecasts are created in the
finance view with the plus in the Forecasts section. The income view no longer
has its own plus. A forecast that already has a booking assigned stays in the
list and is grayed out.

### Portfolio and individual positions

- Each buy of the same ISIN stays its own position, with date, share count,
  and price.
- The cost basis is the sum of the payments divided by the remaining shares,
  rounded once.
- The unit price of an imported buy is the payment amount divided by the
  quantity.
- A fee increases a buy and reduces sale proceeds. It applies once per
  booking.
- A buy is a transfer from the checking account into the portfolio. A sale is
  a transfer from the portfolio to the checking account.
- A transfer-in changes the portfolio without charging the checking account.
- Selling works by share count or by percent, including 25%, 50%, 75%, and
  100%.
- A fully sold position disappears from the portfolio. The booking stays. The
  purchase history stays, so the purchase-to-sale difference can still be
  calculated.
- The list sorts by value, purchase date, or name. The change is either since
  yesterday or since purchase, in euros or in percent.
- Update prices sits on the left in its own bubble. The plus for a new
  position sits on the right in its own bubble, with space between them. The
  same bounded bubbles are used for search and plus on transactions.
- Prices come from Yahoo Finance. A German listing, such as Xetra, Frankfurt,
  gettex, or Tradegate, is preferred. Lang & Schwarz has no public price API.
  If there are several matches, the request is not aborted.
- Updating stores daily euro closing prices. If a day is missing, the last
  stored price before it is used, otherwise the current price.
- If the request fails, the manual fallback price stays. The share count on
  the cutoff date is still used.
- Under the savings plans, **Shares** opens a pie chart. Each slice is that
  position’s share of the portfolio value, using the same value as the depot
  list. €1,000 in an ETF, €500 in Tesla, and €500 in Amazon are 50%, 25%,
  and 25%.

### Savings plans

- A savings plan comes from the executions in the statement.
- The amount is the last outgoing payment. If several executions fall on the
  same day, the largest amount is used.
- The cadence comes from the gap between execution days: up to 10 days is
  weekly, up to 18 is biweekly, up to 45 is monthly, otherwise yearly. A
  single execution counts as monthly.
- The plan is kept when the last execution is close to the end of the
  statement and the position still has a holding. An ended plan is deleted and
  not shown. There is no switch between active and ended.
- In the portfolio, **Savings plans** is a link to its own list, not an
  expanding block. Swiping edits or deletes a plan. While editing, you can
  choose the account the plan is debited or forecast from. If none is stored,
  the checking account from Settings is used.
- At the top are the costs of all active plans per week and per month. A week
  is a quarter of the month, because a month has four debit dates.
- At the bottom are the executions booked in the selected finance period, with
  name, date, and amount. The period is the same one as in the finance view.
- Trade Republic debits on the 2nd, 9th, 16th, and 23rd. Weekly uses all four
  days, biweekly the 2nd and the 16th, monthly and yearly only the 2nd. If
  that is not a banking day, the next banking day is used.
- The savings plans in the portfolio are the source. Each plan remains a fixed
  cost internally on the linked checking account, so the forecast keeps
  running. The fixed-costs list does not repeat each plan. One overview row
  shows what is already booked and what is still open in the selected period,
  and opens the savings-plans view. Swiping in that view edits or deletes a
  plan.
- An execution that is already booked is not counted again as an open fixed
  cost. It is included in the booked fixed-cost amount of the period, even
  when it fell before the last execution.
- These fixed costs are shown for all accounts. In the forecast difference,
  open savings plans count as open expenses. In the portfolio value at the
  same moment they are an inflow, and on the checking account they are an
  outflow.
- On another account they appear only when it is the linked checking account.
- For ordinary fixed costs, the list shows the next debit day and how many
  dates in the selected period are still open. A tap opens the detail: every
  booking assigned so far, whether by hand or recognized automatically, and
  the next three dates. A booking can be tapped, edited, or removed from the
  assignment. The booking itself stays. Swiping right edits the fixed cost,
  swiping left deletes it. When an account is selected, the assignment shows
  only that account’s bookings.
- The same open dates appear in expenses as forecast expenses, each on its
  day, the way the fixed-cost tile counts them. On the main account those are
  the household fixed costs. On another account, only that account’s savings
  plans. The same list also shows the still-open remainder of each variable
  cost and the planned shopping-list entries that have not been bought.
  Shopping appears only for all accounts and on the main account. When exactly
  one account is selected, transfer forecasts that leave that account are
  listed there too. All accounts and the portfolio do not list transfers
  there. Dates that are already assigned stay in these lists and are grayed
  out.

### Transactions in the finance view

At the bottom are the transactions of the selected period and account, no
longer a separate event list. Above them, a field searches by title or note.
To the right, with space between, the plus creates a transaction. Both sit in
their own bubbles. Each row shows icon, category, date, and amount, opens the
transaction, and can be swiped: left deletes, right edits.

Above the transactions is a separate **Forecasts** section. It holds the
income, fixed costs, variable costs, and shopping items of the period,
filtered as in the income and expense views. When exactly one account is
selected, transfers are there too, an outflow negative and an inflow positive.
Above that, its own field searches, and the plus on the right creates a
forecast. The choices are income forecast, transfer forecast, savings plan,
fixed cost, and variable cost. Each opens its own form. The title names the
kind: New income forecast, New transfer forecast, New savings plan, New fixed
cost, New variable cost. Editing uses Edit income forecast, and the same
pattern for the others. The transaction search does not filter this section. A
tap opens the detail. A real transaction can be assigned there. When an
account is selected, only that account’s transactions are offered. For income,
fixed costs, transfers, and the shopping list, the assignment replaces the
forecast for the whole period. The other dates remain. A forecast that is
already assigned, by hand or automatically, stays visible and is grayed out.
Variable costs are different: each further transaction only reduces the
reserved remainder, and the row stays until that remainder is zero. Swiping
right edits the series. Swiping left deletes only that date. In the portfolio
the section is omitted. The rows do not sit between the transactions.

All savings plans in this section sit in one pot. The pot starts expanded, so
the individual dates are visible. The header shows the total, what is already
booked, and what is still open. The total is the sum of the selected period:
booked plus still open. Booked is what has already been debited. Open is the
remainder. The previous per-week and period caption is not shown there.

On the transactions below, the plus asks for the category first: income,
interest, dividend, expense, refund, transfer, or balance adjustment. Then
only that category’s form opens, without the other categories in the same
form. The title is, for example, New expense. While editing, the category
stays fixed and the title is Edit expense. The same preselection is in the
transaction list.

The displayed category is not its own stored kind. What is stored remains
income, expense, transfer, or balance adjustment. What is shown is:

- Income, interest, dividend, expense, refund, portfolio buy, portfolio sale,
  savings plan, transfer
- A balance adjustment stays a balance adjustment.

Each has its own symbol. The same symbols are used in the income and expense
lists and on the home-screen transactions.

- Income is a banknote, an expense is a shopping cart, a refund is an arrow
  back.
- A portfolio buy is a rising chart, a portfolio sale is a falling chart.
- Savings plan and transfer keep their existing symbols.

The color of portfolio buy, savings plan, and portfolio sale depends on the
filter:

- Checking account: portfolio buy and savings plan are red, icon and amount. A
  sale is green. Under the amount, the difference is smaller, green when
  positive and red when negative.
- All accounts: portfolio buy, savings plan, and the sale amount stay in the
  text color, including the icon. Only the difference under the sale is red or
  green.
- Portfolio: portfolio buy and savings plan are green, icon and amount. A sale
  is red.

Income, interest, and dividends stay green, an expense red. A refund stays in
the text color, icon and amount, and shows the full sum. In the income or
expense list, the purchase-to-sale difference itself is the amount and takes
that color. There is no second difference under it.

A savings plan is recognized by the title “Savings plan:”. A portfolio buy
goes into a portfolio, a portfolio sale comes from a portfolio. Interest and
dividends are marked in the note as type Interest or type Yield.

A transfer between your own accounts is called a transfer when all accounts
are selected. When exactly one account is selected, it is an expense there if
the money leaves the account, and income if it arrives. Portfolio buy,
portfolio sale, and savings plan keep their category, including on a single
account. The counting rules stay the same: for all accounts, a portfolio sale
counts as income only with the positive purchase-to-sale difference, and as an
expense with the negative one. On the linked checking account the full amount
counts.

The detail of a transfer shows both sides, the outflow on one account and the
inflow on the other. A portfolio sale always also shows purchase price, sale
price, and difference. When creating an ordinary transaction, the plus asks
for the category first, then only that form appears. Portfolio buy, portfolio
sale, and savings plan are not in that choice, including while editing. Those
three are created only when a portfolio position is created, bought into, or
sold, or when a savings plan is created. Opening an existing booking of that
kind keeps the category fixed. It cannot be switched there. A portfolio sale
continues to be stored as a transfer from the portfolio to the account, so the
purchase-to-sale difference still applies.

The portfolio is not offered for ordinary transactions, fixed costs, income
forecasts, transfer forecasts, variable costs, or budget pools. Only portfolio
buy, portfolio sale, and savings plan use it, and only on the portfolio side.

### Refund

A refund is its own category. It always needs an original expense. The link
is stored in local settings, not on the transaction itself.

- In the transaction list the refund shows its full amount. It does not count
  in the income pot and does not appear in the income list.
- The original expense stays an expense. Under its amount is the remainder
  that still counts, smaller, like the purchase-to-sale difference on a sale.
  An expense of €100 with a refund of €30 counts as a €70 expense. Several
  refunds are added. If the sum exceeds the expense, the expense counts as
  zero.
- The account balance keeps both movements: the expense goes out, the refund
  comes in.
- The expense detail lists the linked refunds. The refund detail shows the
  original transaction.
- On the detail of an ordinary expense, a button creates a refund that is
  already linked to that expense. The amount is entered there. Further refunds
  of the same expense remain possible. A transfer that looks like an expense
  on a single account does not get this button.

### Transfer forecasts

Besides income and expense forecasts there are transfer forecasts. Creating
one uses the plus in the Forecasts section of the finance view, no longer a
separate list under More. Each forecast has two accounts, neither a portfolio,
an amount, and a cadence.

- Dates in the selected period appear in the Forecasts section above the
  transactions. The income view shows only inflows, the expense view only
  outflows. That applies only when exactly one account is selected. For all
  accounts and in the portfolio, the transfer is missing from those lists. A
  tap opens the detail. The forecast can be assigned to a real transaction
  there. When an account is selected, the list offers only that account’s
  transactions. The assignment applies to the whole period. The dates stay
  visible and are grayed out. The same assignment applies to income, fixed
  costs, and the shopping list. For variable costs, each transaction only
  reduces the reserved remainder, and further transactions remain possible. A
  transaction that is already recognized automatically, for example by IBAN,
  still replaces the forecast on its own and grays it out as well. Swiping
  deletes only that single date, not the whole series.
- Assigning the forecast to a real transfer replaces the forecast for the
  whole period. The dates stay grayed out, and the transaction stays.
- In the account-balance forecast, an open date moves money from one account
  to the other. If both accounts are in the view, the total stays zero. A
  transfer that has already been replaced, but is still in the future, counts
  once at its real amount. Savings plans and portfolio buys are excluded from
  that.
- On a single account, a still-open date also counts as open income when the
  money arrives there, and as an open expense when it leaves. In the current
  period that sits under Open. In a future period it is inside the normal
  income or expense amount. Dates before the period are already in the opening
  balance and are not counted again there. A real transfer assigned to the
  forecast in the period replaces the dates.
- For all accounts and in the portfolio, transfer forecasts do not count as
  income or an expense.
- The closing balance stays opening balance plus forecast difference. On a
  single account, the open transfer therefore moves the closing balance.

### Variable costs

- Swiping right edits a variable cost, swiping left deletes it.
- A tap opens the transactions assigned to it in the selected period. When an
  account is selected, only that account’s transactions. The period is the
  same one as in the finance view.
- When creating one, several accounts can be selected. The monthly amount is
  split evenly, with leftover cents on the first accounts. With no selection,
  the amount applies to every account except the portfolio.
- All accounts show the full amount. A single account shows only its share,
  and the row only when that account takes part.
- The selected accounts are not in the data model. They are in local settings,
  so an existing data file stays readable.
- If an assigned expense is partly refunded, the variable cost counts only the
  same share.
- In the forecast, an assigned transaction does not replace the period. Each
  transaction reduces the reserved amount, and further transactions can be
  added. The row stays visible until the remainder is zero, and only then is
  it grayed out. An older assignment for the period counts at its transaction
  amount, not as completing the whole period. A deleted date stays hidden.

### Budget pools

- A tap opens the pool. Swiping right edits it, swiping left deletes it.
- There is no start day. A salary period is the calendar month, and a calendar
  year is the calendar year. An older pool that stored a start day still
  counts those assignments in the calendar month that contains the start of
  the old period.
- The option is called scalable. When it is on and money remains, that
  remainder is carried into the next period. When it is off, the next period
  starts again at the pool amount.
- Assigning a transaction does not change that transaction outside the pool.
  The pool only counts the assigned amount in its own period.

### Expense groups

- A tap opens the group. Swiping right edits it, swiping left deletes it.
- Positions are not entered freely. Existing transactions are assigned to the
  group, and several can be assigned at once. A transaction belongs to one
  group.
- The group matters only inside expense groups. Outside, the transaction keeps
  its amount, its category, and its effect on the totals.
- The assignment is stored beside the data model, so an existing data file
  stays readable.
- The transaction detail lists an assignment to a budget pool, an expense
  group, a fixed cost, a variable cost, a shopping item, or a similar
  forecast. The transaction itself is unchanged.

### Shopping list

- In the finance view, **Planned** has no plus sign and uses the text color.
  **Applied** is red. The same two values sit at the top of the shopping list
  for the selected finance period.
- When a transaction is assigned to the forecast, Applied uses the
  transaction’s amount, not the planned item amount. Several transactions are
  added. If the item is only checked and has no transaction, the item amount
  counts. Unchecked items without a transaction stay in Planned.
- The assignment checks the item off, in the list and in the detail. A tap
  opens the detail. The assigned transactions are listed there, and a tap on a
  transaction opens it. Swiping right edits the item, swiping left deletes it.

### Home budget

The budget on the home screen is not the same total as the finance view. A
tap opens the breakdown, not the finance view. That breakdown lists the
income, the forecasts, and the transactions that produce the total and the
amount spent.

- Income is only foreign inflows. Your own IBAN, dividends, interest, and
  refunds do not count. Open salary forecasts in the period still count.
- Spending is ordinary expenses plus stock buys and savings-plan executions.
  A refunded expense counts only with the remainder. Other transfers do not
  count.
- The daily budget is the remaining budget divided by the days until the next
  payday.

### Trade Republic import

The import is separate from the bank import. During setup it comes after the
main account and after the optional CSV or CAMT import. In Settings it has
its own section. A destination account exists only for CSV and CAMT. A PDF is
not recognized there automatically.

What is read is the transaction overview, with date, type, description, money
in, money out, and balance.

- A trade changes the portfolio and the linked checking account.
- A card transaction is an expense of the checking account. A refund that
  increases the balance stays positive.
- Yield and interest are income of the checking account, not a portfolio
  booking.
- A transfer to one of your own accounts is no longer turned into a transfer
  automatically. After importing a Trade Republic PDF or a Sparkasse CAMT,
  including during setup, a dialog appears.
- Under “Possible transfer” are rows with the same amount, a known IBAN, and a
  date at most three days apart. The switch is off. Only when it is on do the
  two sides become one transfer, and the duplicate booking on the other
  account is dropped.
- Under “Similar transactions” are matches that already exist. The section is
  collapsed. A fingerprint, or the same amount with a similar date and the
  same title or the same IBAN, counts as a duplicate and is skipped. Expanding
  the section and checking a row imports that row anyway. Executions a week
  apart fall outside the three-day window and stay their own transactions.
- Importing again replaces the previous statement of that checking account and
  rebuilds the linked portfolio.

For the purchase-to-sale difference of names that have already been sold in
full to be right, the statement has to be imported again after a rule change.

## Deutsch

Diese Datei beschreibt, wie Lifify Konten, Zeiträume, Einnahmen, Ausgaben,
Depot und das Home-Budget rechnet. Sie gilt für Version 0.3.0.

Zeitraum und Konto sind ein gemeinsamer Filter. Eine Änderung gilt in der
Finanzansicht, in den Buchungen und in den Listen für Einnahmen und Ausgaben.

### Konten

- Kontenarten sind Girokonto, Spartopf, Oberspartopf und Depot.
- Ein Oberspartopf gruppiert Spartöpfe und wird nicht noch einmal zur Summe
  addiert.
- Das Hauptkonto ist verpflichtend und lässt sich nicht löschen.
- Ein Depot ist nicht liquide und muss mit genau einem Girokonto verknüpft
  sein. Ohne diese Verknüpfung lässt es sich nicht anlegen.
- Mehrere Depots dürfen an verschiedenen Girokonten hängen. Im Kontofilter
  erscheinen sie als ein Eintrag **Depot**. Die einzelnen Depotkonten stehen
  dort nicht separat.
- Der Link „Depot“ unter Weitere Bereiche entfällt. Dieselben Positionen sieht
  man, wenn im Filter **Depot** gewählt ist.
- Für Käufe und Verkäufe lässt sich in den Einstellungen ein Standard-Girokonto
  und eine Standardgebühr hinterlegen. Die Gebühr ist beim Buchen zunächst aus.

### Zeitraum

- Vor und zurück sowie Heute stehen über der Finanzliste, damit der Wechsel
  immer ankommt.
- Zeiträume folgen der Haupteinnahme, wenn der Gehaltszeitraum aktiv ist.
  Sonst sind es Kalendermonate.
- Der erste Zeitraum beginnt mit den Buchungen des Hauptkontos. Sein Start ist
  der Stichtag.
- Trade-Republic-Buchungen vor dem Stichtag werden nicht angelegt. Buchungen am
  Stichtag und danach werden angelegt, auch wenn der erste Zeitraum schon vorbei
  ist.
- Depotpositionen aus dem ganzen Auszug werden trotzdem übernommen, auch Käufe
  vor dem Stichtag.
- Gibt es auf dem Hauptkonto noch keine Buchung, gibt es noch keinen Zeitraum.
  Dann werden alle Auszugszeilen gebucht.
- Der Startsaldo des ersten Zeitraums ist der rechte Saldo des Auszugs vor dem
  Starttag, also der letzte gedruckte Saldo der Zeilen davor. Fehlt so eine
  Zeile, gilt der Eröffnungssaldo des Auszugs.
- Der Saldo ist der Stand des Girokontos nach der Zeile. Er wird nie als
  Zahlungsbetrag gebucht.
- Dieser Startsaldo wird als Saldo-Korrektur am Starttag gespeichert. In der
  Anzeige zählt er zum Beginn des Zeitraums. Einnahmen und andere Buchungen
  am ersten Tag gehören in den Zeitraum, nicht in den Startsaldo.

### Saldo bei allen Konten

Ist **Alle Konten** gewählt, ist der Startsaldo die Summe der Startsalden der
einzelnen Konten plus den Depotwert am Tag davor.

- Buchungen am ersten Tag, auch Einnahmen, zählen nicht in den Startsaldo.
  Eine Saldo-Korrektur an diesem Tag bleibt der Eröffnungswert.
- Der Depotwert sind die Stücke, die am Ende des Tages davor gehalten wurden.
  Käufe am ersten Tag fehlen im Startsaldo und liegen im Zeitraum.
- Der Kurs ist der Schlusskurs dieses Tages, sobald er gespeichert ist. Fehlt
  er, gilt der aktuelle Kurs, die Stückzahl bleibt die historische.
- Liegt der Stichtag in der Zukunft, kommt der aktuelle Kurs zum Einsatz. Noch
  nicht gebuchte Sparpläne erhöhen bis zu diesem Tag die Stückzahl. Pro
  Ausführung kommen so viele Stücke dazu, wie der Planbetrag beim aktuellen
  Kurs kauft. Kostet der ETF 100 € und der Plan 50 €, ist das eine halbe
  Stückzahl, auch über ein Jahr hinweg. Der Wert dieser Stücke ist der
  Eurobetrag, ohne prozentuale Steigerung. Ein Plan ohne passende Position
  zählt weiter nur als Eurobetrag. Auf dem verknüpften Girokonto mindern
  dieselben Termine den Startsaldo, sodass die Summe unverändert bleibt.
- In der Depotliste steht für den gewählten Zeitraum diese Stückzahl und der
  dazu passende Wert. Die Veränderung daneben bleibt die der schon gehaltenen
  Stücke.
- Startsaldo und Endsaldo stehen in derselben Reihe. Darunter steht der liquide
  Saldo ohne Depot, in derselben Zifferngröße. Die Zahl darf leicht schrumpfen,
  damit beide Kacheln nebeneinander passen. Kacheln in einer Reihe sind gleich
  hoch, auch wenn eine Zahl oder der Hinweis darunter umbricht.
- Das Endsaldo ist der Startsaldo plus die Prognose-Differenz. Unter dem
  Endsaldo steht keine weitere Differenzzahl. Die Prognose-Differenz ist
  gebuchte plus offene Einnahmen abzüglich gebuchter plus offener Ausgaben.
- Im laufenden Zeitraum steht unter der Differenz das Wort **Prognose** in
  einer eigenen Zeile und der Betrag darunter, ebenfalls allein. **Offen**
  steht bei Einnahmen, Ausgaben, Fixkosten und variablen Kosten genauso:
  Überschrift oben, Betrag darunter. Der große Betrag bleibt dort der schon
  gebuchte. Bei den Einnahmen enthält der große Betrag die Prognose bereits,
  Offen zeigt nur den noch offenen Teil.
- Liegt der ganze Zeitraum in der Zukunft, gibt es kein Offen. Der große
  Betrag ist dann der normale Wert, also gebucht plus noch offen. Bei den
  Fixkosten steht dieser Betrag direkt in der Kachel Fixkosten. Die Differenz
  zeigt direkt die Prognose, ohne eine zweite Zeile.
- Die Fixkostenkachel zeigt nur, wie viel gebucht ist und wie viel offen ist.
  Die einzelnen Sparpläne stehen nicht darauf. Ein Tipp auf diese Übersicht
  öffnet die Sparplanansicht. Die gewöhnlichen Fixkosten bleiben in einer
  eigenen Liste unter Weitere Bereiche.
- Ein abgeschlossener Zeitraum zeigt nur Gebuchtes, ohne Offen und ohne
  Prognosezeile.
- Während die Finanzkacheln zum ersten Mal oder nach einem Wechsel von
  Zeitraum oder Konto rechnen, steht dort eine Ladeanzeige. Kurze
  Datenänderungen beim Start werden zu diesem einen Ladevorgang
  zusammengezogen. Danach bleiben die Kacheln stehen und die Zahlen
  aktualisieren sich, ohne die Ansicht erneut zu leeren. Die Filter bleiben
  benutzbar. In der Finanzansicht bleiben die Buchungen darunter sichtbar.
- Ist **Depot** gewählt, zeigt die Karte Gesamtvermögen den Depotwert am Ende
  des gewählten Zeitraums, inklusive noch nicht gebuchter Sparpläne, und die
  Veränderung. Die Positionen stehen direkt darunter. Beides erscheint, ohne
  auf die übrigen Kacheln zu warten. Einnahmen, Ausgaben, Startsaldo und
  Endsaldo entfallen dort. Weitere Bereiche entfallen ebenfalls.

### Einnahmen und Ausgaben

#### Alle Konten

Einnahmen sind:

- Eingänge von einer fremden IBAN oder einem fremden Konto
- Dividenden (Ertrag)
- Zinsen
- die positive Kursdifferenz eines Aktienverkaufs

Nicht als Einnahme zählen Eingänge von der eigenen IBAN, der volle
Verkaufserlös und eine Rückerstattung.

Ein Verkauf wird mit Einstand und Gebühren verglichen. Der Erlös ist der
Zahlungsbetrag nach Gebühr, der Einstand ist der durchschnittliche Kaufpreis
der verkauften Stücke inklusive Kaufgebühren. Nur die Differenz erscheint:

- positiv als Einnahme
- negativ als Ausgabe
- null wird nicht gezeigt

Aktienkäufe und Sparpläne sind bei allen Konten keine Ausgaben. Das Geld wechselt
nur vom Girokonto ins Depot. Andere Umbuchungen zwischen eigenen Konten zählen
ebenfalls nicht als Einnahme oder Ausgabe.

#### Verknüpftes Girokonto

Ist das Girokonto gewählt, das mit dem Depot verknüpft ist, zählen Käufe,
Sparpläne und Verkäufe mit dem vollen Betrag. Ein Abfluss ist eine Ausgabe, ein
Zufluss eine Einnahme. Die Kursdifferenz wird dann nicht noch einmal extra
gezählt.

#### Einzelnes anderes Konto

Umbuchungen, die dieses Konto berühren, zählen dort voll mit. Depotkäufe eines
anderen Girokontos erscheinen nicht.

#### Einnahmeprognosen

Eine Prognose mit Konto gilt nur für dieses Konto. In der Einnahmenliste und
in der Einnahmenkachel eines einzelnen Kontos erscheinen nur dessen Prognosen.
Eine Prognose ohne Konto erscheint nur bei allen Konten, nicht auf einem
einzelnen Konto. Dasselbe gilt für den Startsaldo: jedes Konto rechnet nur mit
seinen eigenen Prognosen.

In der Einnahmenansicht steht jeder noch offene Termin des Zeitraums, nicht nur
der nächste. Ist genau ein Konto gewählt, stehen dort zusätzlich die
Umbuchungsprognosen, bei denen das Geld auf diesem Konto ankommt. Bei allen
Konten und im Depot stehen dort keine Umbuchungen. Neue Einnahmeprognosen
legt man in der Finanzansicht über das Plus im Bereich Prognosen an. In der
Einnahmenansicht gibt es dafür kein Plus mehr. Eine Prognose, der schon eine
Buchung zugeordnet ist, bleibt in der Liste und ist ausgegraut.

### Depot und Einzelpositionen

- Jeder Kauf derselben ISIN bleibt eine eigene Position mit Datum, Stückzahl
  und Kurs.
- Der Einstand ist die Summe der Zahlungen geteilt durch die verbleibenden
  Stücke, einmal gerundet.
- Der Stückpreis eines importierten Kaufs ist der Zahlungsbetrag geteilt durch
  die Quantity.
- Eine Gebühr erhöht den Kauf und mindert den Verkaufserlös. Sie gilt einmal
  pro Buchung.
- Ein Kauf ist eine Umbuchung vom Girokonto ins Depot. Ein Verkauf ist eine
  Umbuchung vom Depot auf das Girokonto.
- Ein Übertrag verändert das Depot, ohne das Girokonto zu belasten.
- Verkaufen geht nach Stückzahl oder nach Prozent, einschließlich 25 %, 50 %,
  75 % und 100 %.
- Eine vollständig verkaufte Position verschwindet aus dem Depot. Die Buchung
  bleibt. Die Kaufhistorie bleibt erhalten, damit die Kursdifferenz gerechnet
  werden kann.
- Die Liste sortiert nach Wert, Kaufzeitpunkt oder Name. Die Veränderung steht
  wahlweise seit dem Vortag oder seit dem Kauf, in Euro oder in Prozent.
- Kurse aktualisieren steht links in einer eigenen Blase, das Plus für eine
  neue Position rechts in einer eigenen Blase, mit Abstand dazwischen. Dieselben
  begrenzten Blasen gelten für die Suche und das Plus bei den Buchungen.
- Kurse kommen von Yahoo Finance. Eine deutsche Notierung, etwa Xetra,
  Frankfurt, gettex oder Tradegate, wird bevorzugt. Lang & Schwarz hat keine
  öffentliche Kurs-API. Gibt es mehrere Treffer, wird nicht abgebrochen.
- Beim Aktualisieren werden tägliche Euro-Schlusskurse gespeichert. Fehlt ein
  Tag, gilt der letzte gespeicherte Kurs davor, sonst der aktuelle Kurs.
- Schlägt der Abruf fehl, bleibt der manuelle Fallbackkurs. Die Stückzahl zum
  Stichtag wird trotzdem verwendet.
- Unter den Sparplänen öffnet **Anteile** ein Kreisdiagramm. Jede Position
  zeigt ihren Anteil am Depotwert, mit demselben Wert wie in der Depotliste.
  1.000 € ETF, 500 € Tesla und 500 € Amazon sind 50 %, 25 % und 25 %.

### Sparpläne

- Ein Sparplan entsteht aus den Ausführungen im Auszug.
- Der Betrag ist der letzte Zahlungsausgang. Liegen am selben Tag mehrere
  Ausführungen, gilt der größte Betrag.
- Der Rhythmus ergibt sich aus dem Abstand der Ausführungstage: bis 10 Tage
  wöchentlich, bis 18 zweiwöchentlich, bis 45 monatlich, sonst jährlich. Eine
  einzelne Ausführung gilt als monatlich.
- Der Plan wird übernommen, wenn die letzte Ausführung nah am Auszugsende liegt
  und die Position noch Bestand hat. Ein beendeter Plan wird gelöscht und nicht
  angezeigt. Es gibt keinen Schalter zwischen Aktiv und Beendet.
- Im Depot ist **Sparpläne** ein Link in eine eigene Liste, kein aufklappbarer
  Block. Wischen bearbeitet oder löscht einen Plan. Beim Bearbeiten lässt sich
  das Konto wählen, von dem der Plan abgebucht oder prognostiziert wird. Ist
  noch keins gespeichert, gilt das Girokonto aus den Einstellungen.
- Oben stehen die Kosten aller aktiven Pläne pro Woche und pro Monat. Eine
  Woche ist ein Viertel des Monats, weil ein Monat vier Abbuchungstermine hat.
- Unten stehen die im gewählten Finanzzeitraum gebuchten Ausführungen, mit
  Name, Datum und Betrag. Der Zeitraum ist derselbe wie in der Finanzansicht.
- Trade Republic bucht am 2., 9., 16. und 23. Wöchentlich sind alle vier Tage,
  zweiwöchentlich der 2. und der 16., monatlich und jährlich nur der 2. Ist
  das kein Bankarbeitstag, gilt der nächste Bankarbeitstag.
- Die Sparpläne im Depot sind die Vorlage. Jeder Plan bleibt intern eine
  Fixkosten auf dem verknüpften Girokonto, damit die Prognose weiterläuft.
  Die Fixkostenliste wiederholt die einzelnen Pläne nicht. Eine Übersicht
  zeigt, was im gewählten Zeitraum schon gebucht ist und was noch offen ist,
  und öffnet die Sparplanansicht. Dort bearbeitet oder löscht Wischen einen
  Plan.
- Eine bereits gebuchte Ausführung zählt nicht noch einmal als offene Fixkosten.
  Sie steht aber im gebuchten Fixkostenbetrag des Zeitraums, auch wenn sie vor
  der letzten Ausführung lag.
- Bei allen Konten werden diese Fixkosten angezeigt. In der Prognose-Differenz
  zählen offene Sparpläne als offene Ausgaben. Im Depotwert desselben
  Zeitpunkts stehen sie als Zugang, auf dem Girokonto als Abgang.
- Auf einem anderen Konto erscheinen sie nur, wenn es das verknüpfte Girokonto
  ist.
- In der Fixkostenliste steht bei normalen Fixkosten der nächste Abbuchungstag
  und wie viele Termine im gewählten Zeitraum noch offen sind. Ein Tipp öffnet
  die Detailansicht: alle bisher zugeordneten Buchungen, ob von Hand oder
  automatisch erkannt, und die nächsten drei Termine. Eine Buchung lässt sich
  dort antippen, bearbeiten oder aus der Zuweisung nehmen. Die Buchung selbst
  bleibt dabei stehen. Wischen nach rechts bearbeitet die Fixkosten, Wischen
  nach links löscht sie. Ist ein Konto gewählt, zeigt die Zuweisung nur
  Buchungen dieses Kontos.
- Dieselben offenen Termine stehen in den Ausgaben als Prognoseausgaben, je
  an ihrem Tag, so wie die Fixkostenkachel sie zählt. Auf dem Hauptkonto sind
  das die Haushalts-Fixkosten, auf einem anderen Konto nur dessen Sparpläne.
  In derselben Liste stehen der noch offene Rest jeder variablen Kosten und
  die geplanten, noch nicht gekauften Einträge des Einkaufszettels. Einkäufe
  nur bei allen Konten und auf dem Hauptkonto. Ist genau ein Konto gewählt,
  stehen dort auch die Umbuchungsprognosen, die von diesem Konto abgehen. Bei
  allen Konten und im Depot stehen dort keine Umbuchungen. Schon zugeordnete
  Termine bleiben in diesen Listen und sind ausgegraut.

### Buchungen in der Finanzansicht

Unten stehen die Buchungen des gewählten Zeitraums und Kontos, nicht mehr eine
eigene Ereignisliste. Darüber sucht ein Feld nach Titel oder Notiz. Rechts
daneben, mit Abstand, legt das Plus eine Buchung an. Beide liegen in eigenen
Blasen. Jede Zeile zeigt Icon, Kategorie, Datum und Betrag, öffnet die Buchung
und lässt sich wischen: links löschen, rechts bearbeiten.

Über den Buchungen steht ein eigener Bereich **Prognosen**. Darin liegen die
Einnahmen, Fixkosten, variablen Kosten und Einkäufe des Zeitraums, gefiltert
wie in der Einnahmen- und Ausgabenansicht. Ist genau ein Konto gewählt, liegen
dort auch die Umbuchungen, Abgang negativ und Zugang positiv. Darüber sucht ein
eigenes Feld, rechts daneben legt das Plus eine Prognose an. Zur Auswahl stehen
Einnahmeprognose, Umbuchungsprognose, Sparplan, Fixkosten und variable Kosten.
Jedes öffnet sein eigenes Formular. Die Überschrift nennt die Art: Neue
Einnahmenprognose, Neue Umbuchungsprognose, Neuer Sparplan, Neue Fixkosten,
Neue variable Kosten. Beim Bearbeiten entsprechend Einnahmenprognose
bearbeiten und so weiter. Die Buchungssuche filtert diesen Bereich nicht. Ein
Tipp öffnet die Detailansicht. Dort lässt sich eine echte Buchung zuweisen.
Ist ein Konto gewählt, stehen nur Buchungen dieses Kontos zur Auswahl. Bei
Einnahmen, Fixkosten, Umbuchungen und dem Einkaufszettel ersetzt die Zuweisung
die Prognose für den ganzen Zeitraum, die anderen Termine bleiben. Eine schon
zugeordnete Prognose, von Hand oder automatisch, bleibt sichtbar und ist
ausgegraut. Variable Kosten sind davon ausgenommen: jede weitere Buchung
mindert nur den noch reservierten Betrag, und die Zeile bleibt stehen, bis
dieser Rest null ist. Wischen nach rechts bearbeitet die Serie, Wischen nach
links löscht nur diesen Termin. Im Depot entfällt der Bereich. Die Zeilen
stehen nicht zwischen den Buchungen.

Alle Sparpläne in diesem Bereich stehen in einem Topf. Der Topf ist zuerst
aufgeklappt, die einzelnen Termine sind sichtbar. Die Überschrift zeigt
Gesamt, gebucht und offen. Gesamt ist die Summe des gewählten Zeitraums, also
gebucht plus noch offen. Gebucht ist, was schon abgebucht wurde. Offen ist der
Rest. Die bisherige Angabe pro Woche und Zeitraum steht dort nicht mehr.

Unten bei den Buchungen wählt das Plus zuerst die Kategorie: Einnahme, Zinsen,
Dividende, Ausgabe, Rückerstattung, Umbuchung oder Saldo-Korrektur. Danach
öffnet sich nur das Formular dieser Kategorie, ohne weitere Kategorien in
demselben Formular. Die Überschrift ist zum Beispiel Neue Ausgabe. Beim
Bearbeiten bleibt die Kategorie fest, die Überschrift lautet Ausgabe
bearbeiten. Dieselbe Vorauswahl steht in der Buchungsliste.

Die angezeigte Kategorie ist keine eigene Speicherart. Gespeichert bleibt
Einnahme, Ausgabe, Umbuchung oder Saldo-Korrektur. Angezeigt wird:

- Einnahme, Zinsen, Dividende, Ausgabe, Rückerstattung, Depotkauf,
  Depotverkauf, Sparplan, Umbuchung
- Eine Saldo-Korrektur bleibt eine Saldo-Korrektur.

Jedes davon hat ein eigenes Symbol. Dieselben Symbole stehen in den Listen für
Einnahmen und Ausgaben und bei den Buchungen auf der Home-Seite.

- Einnahme ist ein Geldschein, Ausgabe ein Einkaufswagen, Rückerstattung ein
  Pfeil zurück.
- Depotkauf ist ein steigender Chart, Depotverkauf ein fallender Chart.
- Sparplan und Umbuchung behalten ihre bisherigen Symbole.

Die Farbe von Depotkauf, Sparplan und Depotverkauf hängt vom Filter ab:

- Girokonto: Depotkauf und Sparplan sind rot, Icon und Betrag. Ein Verkauf ist
  grün. Unter dem Betrag steht die Differenz kleiner, grün wenn positiv und rot
  wenn negativ.
- Alle Konten: Depotkauf, Sparplan und der Verkaufsbetrag bleiben in der
  Textfarbe, auch das Icon. Nur die Differenz unter dem Verkauf ist rot oder
  grün.
- Depot: Depotkauf und Sparplan sind grün, Icon und Betrag. Ein Verkauf ist rot.

Einnahme, Zinsen und Dividende bleiben grün, eine Ausgabe rot. Eine
Rückerstattung bleibt in der Textfarbe, Icon und Betrag, und zeigt die ganze
Summe. In der
Einnahmen- oder Ausgabenliste ist die Kursdifferenz selbst der Betrag und trägt
deren Farbe. Dort steht keine zweite Differenz darunter.

Ein Sparplan erkennt man am Titel „Sparplan:“. Ein Depotkauf geht auf ein Depot,
ein Depotverkauf kommt von einem Depot. Zinsen und Dividenden stehen in der
Notiz als Typ Zinsen oder Typ Ertrag.

Eine Umbuchung zwischen eigenen Konten heißt bei allen Konten Umbuchung. Ist
genau ein Konto gewählt, ist sie dort eine Ausgabe, wenn das Geld das Konto
verlässt, und eine Einnahme, wenn es ankommt. Depotkauf, Depotverkauf und
Sparplan behalten ihre Kategorie, auch auf einem einzelnen Konto. Die Zählregeln
bleiben dieselben: bei allen Konten zählt ein Depotverkauf nur mit der positiven
Kursdifferenz als Einnahme und mit der negativen als Ausgabe. Auf dem
verknüpften Girokonto zählt der volle Betrag.

Die Detailansicht einer Umbuchung zeigt beide Seiten, den Abgang auf dem einen
Konto und den Zugang auf dem anderen. Ein Depotverkauf zeigt zusätzlich immer
Einkaufspreis, Verkaufspreis und Differenz. Beim Anlegen einer gewöhnlichen
Buchung wählt das Plus zuerst die Kategorie, danach kommt nur dieses Formular.
Depotkauf, Depotverkauf und Sparplan stehen in dieser Auswahl nicht, auch
nicht beim Bearbeiten. Diese drei entstehen nur,
wenn eine Depotposition angelegt, nachgekauft oder verkauft wird, oder wenn
ein Sparplan angelegt wird. Öffnet man eine bestehende Buchung dieser Art,
bleibt die Kategorie fest und lässt sich dort nicht umstellen. Ein Depotverkauf
wird weiter als Umbuchung vom Depot auf das Konto gespeichert, damit die
Kursdifferenz gilt.

Das Depot steht bei gewöhnlichen Buchungen, Fixkosten, Einnahmeprognosen,
Umbuchungsprognosen, variablen Kosten und Budgetpools nicht zur Auswahl. Nur
Depotkauf, Depotverkauf und Sparplan nutzen es, und dort nur auf der Depotseite.

### Rückerstattung

Eine Rückerstattung ist eine eigene Kategorie. Sie braucht immer eine
ursprüngliche Ausgabe. Die Verknüpfung liegt in den lokalen Einstellungen, nicht
in der Buchung selbst.

- In der Buchungsliste steht die Rückerstattung mit ihrer ganzen Summe. Sie
  zählt nicht in den Einnahmentopf und erscheint nicht in der Einnahmenliste.
- Die ursprüngliche Ausgabe bleibt eine Ausgabe. Unter ihrem Betrag steht der
  Rest, der noch zählt, kleiner und wie die Kursdifferenz bei einem Verkauf.
  Eine Ausgabe von 100 € mit einer Rückerstattung von 30 € zählt als 70 €.
  Mehrere Rückerstattungen werden addiert. Übersteigt die Summe die Ausgabe,
  zählt die Ausgabe als null.
- Der Kontostand behält beide Bewegungen: die Ausgabe geht ab, die
  Rückerstattung kommt an.
- In der Detailansicht der Ausgabe stehen die verknüpften Rückerstattungen.
  In der Detailansicht der Rückerstattung steht die ursprüngliche Buchung.
- In der Detailansicht einer normalen Ausgabe legt ein Button eine
  Rückerstattung an, die schon mit dieser Ausgabe verknüpft ist. Der Betrag
  wird dort eingegeben. Weitere Rückerstattungen derselben Ausgabe bleiben
  möglich. Eine Umbuchung, die auf einem einzelnen Konto wie eine Ausgabe
  aussieht, bekommt diesen Button nicht.

### Umbuchungsprognosen

Neben Einnahme- und Ausgabenprognosen gibt es Umbuchungsprognosen. Anlegen
läuft über das Plus im Bereich Prognosen der Finanzansicht, nicht mehr über
eine eigene Liste in Weitere Bereiche. Jede Prognose hat zwei Konten, beide
ohne Depot, einen Betrag und einen Rhythmus.

- Termine des gewählten Zeitraums stehen im Bereich Prognosen über den
  Buchungen. In der Einnahmenansicht nur die Zugänge, in der Ausgabenansicht
  nur die Abgänge. Das gilt nur, wenn genau ein Konto gewählt ist. Bei allen
  Konten und im Depot fehlt die Umbuchung in diesen Listen. Ein Tipp öffnet
  die Detailansicht. Dort kann die Prognose einer echten Buchung zugewiesen
  werden. Ist ein Konto gewählt, bietet die Liste nur dessen Buchungen an.
  Die Zuweisung gilt für den ganzen Zeitraum. Die Termine bleiben sichtbar
  und werden ausgegraut. Dieselbe Zuweisung gilt für Einnahmen, Fixkosten und
  den Einkaufszettel. Bei variablen Kosten mindert jede Buchung nur den
  reservierten Rest, weitere Buchungen bleiben möglich. Eine Buchung, die
  schon automatisch erkannt wird, zum Beispiel über die IBAN, ersetzt die
  Prognose weiter von selbst und graut sie ebenfalls aus. Wischen löscht nur
  den einzelnen Termin, nicht die ganze Serie.
- Weist man die Prognose einer echten Umbuchung zu, ersetzt diese Buchung die
  Prognose für den ganzen Zeitraum. Die Termine bleiben ausgegraut stehen, die
  Buchung bleibt.
- In der Prognose des Kontostands bewegt ein offener Termin Geld vom einen
  Konto auf das andere. Liegen beide Konten in der Ansicht, bleibt die Summe
  null. Eine schon ersetzte, aber noch zukünftige Umbuchung zählt einmal mit
  ihrem echten Betrag. Sparpläne und Depotkäufe sind davon ausgenommen.
- Auf einem einzelnen Konto zählt ein noch offener Termin zusätzlich als offene
  Einnahme, wenn das Geld dort ankommt, und als offene Ausgabe, wenn es von
  dort geht. Im laufenden Zeitraum steht das unter Offen. In einem zukünftigen
  Zeitraum steckt es im normalen Einnahmen- oder Ausgabenbetrag. Termine vor
  dem Zeitraum liegen schon im Startsaldo und werden dort nicht noch einmal
  gezählt. Eine echte Umbuchung, die der Prognose im Zeitraum zugeordnet ist,
  ersetzt die Termine.
- Bei allen Konten und im Depot zählen Umbuchungsprognosen nicht als Einnahme
  oder Ausgabe.
- Das Endsaldo bleibt Startsaldo plus Prognose-Differenz. Auf einem einzelnen
  Konto verschiebt die offene Umbuchung deshalb das Endsaldo.

### Variable Kosten

- Rechtswischen bearbeitet eine variable Kosten, Linkswischen löscht sie.
- Ein Tipp öffnet die Buchungen, die ihr im gewählten Zeitraum zugeordnet sind.
  Ist ein Konto gewählt, nur die Buchungen dieses Kontos. Der Zeitraum ist
  derselbe wie in der Finanzansicht.
- Beim Anlegen lassen sich mehrere Konten wählen. Der Monatsbetrag wird
  gleichmäßig aufgeteilt, Restcents auf die ersten Konten. Ohne Auswahl gilt
  der Betrag für alle Konten außer Depot.
- Alle Konten zeigen den vollen Betrag. Ein einzelnes Konto zeigt nur seinen
  Anteil, und die Zeile nur, wenn das Konto beteiligt ist.
- Die gewählten Konten liegen nicht im Datenmodell, sondern in den lokalen
  Einstellungen. So bleibt eine bestehende Datendatei lesbar.
- Ist eine zugeordnete Ausgabe teilweise erstattet, zählt bei den variablen
  Kosten nur derselbe Anteil.
- In der Prognose ersetzt eine zugeordnete Buchung den Zeitraum nicht. Jede
  Buchung mindert den reservierten Betrag, weitere Buchungen können dazukommen.
  Die Zeile bleibt sichtbar, bis der Rest null ist, und wird erst dann
  ausgegraut. Eine ältere Zuweisung für den Zeitraum zählt dabei mit ihrem
  Buchungsbetrag, nicht als komplette Erledigung. Ein gelöschter Termin bleibt
  ausgeblendet.

### Budgetpools

- Ein Tipp öffnet den Pool. Wischen nach rechts bearbeitet ihn, Wischen nach
  links löscht ihn.
- Es gibt keinen Starttag. Der Gehaltszeitraum ist der Kalendermonat, das
  Kalenderjahr das Kalenderjahr. Ein älterer Pool mit gespeichertem Starttag
  zählt diese Zuweisungen in dem Kalendermonat, in dem der alte Zeitraum
  beginnt.
- Die Option heißt skalierbar. Ist sie an und bleibt Geld übrig, wird dieser
  Rest in den nächsten Zeitraum mitgenommen. Ist sie aus, beginnt der nächste
  Zeitraum wieder mit dem Poolbetrag.
- Eine zugeordnete Buchung bleibt außerhalb des Pools unverändert. Der Pool
  zählt nur den zugeordneten Betrag in seinem eigenen Zeitraum.

### Ausgabengruppen

- Ein Tipp öffnet die Gruppe. Wischen nach rechts bearbeitet sie, Wischen nach
  links löscht sie.
- Positionen legt man nicht frei an. Der Gruppe werden bestehende Buchungen
  zugewiesen, auch mehrere auf einmal. Eine Buchung gehört zu einer Gruppe.
- Die Gruppe wirkt nur innerhalb der Ausgabengruppen. Außerhalb behält die
  Buchung Betrag, Kategorie und ihre Wirkung auf die Summen.
- Die Zuweisung liegt neben dem Datenmodell, damit eine bestehende Datendatei
  lesbar bleibt.
- In der Detailansicht einer Buchung steht eine Zuweisung zu einem Budgetpool,
  einer Ausgabengruppe, Fixkosten, variablen Kosten, einem Einkauf oder einer
  vergleichbaren Prognose. Die Buchung selbst bleibt unverändert.

### Einkaufszettel

- In der Finanzansicht steht **Geplant** ohne Plus und in der Textfarbe.
  **Angewendet** ist rot. Dieselben zwei Werte stehen oben in der
  Einkaufsliste für den gewählten Finanzzeitraum.
- Wird der Prognose eine Buchung zugewiesen, zählt bei Angewendet der Betrag
  der Buchung, nicht der geplante Artikelbetrag. Mehrere Buchungen werden
  addiert. Ist der Artikel nur abgehakt und hat keine Buchung, zählt der
  Artikelbetrag. Nicht abgehakte Artikel ohne Buchung bleiben bei Geplant.
- Die Zuweisung hakt den Artikel ab, in der Liste und in der Detailansicht.
  Ein Tipp öffnet die Detailansicht. Dort stehen die zugewiesenen Buchungen,
  und ein Tipp auf eine Buchung öffnet sie. Rechtswischen bearbeitet den
  Artikel, Linkswischen löscht ihn.

### Home-Budget

Das Budget auf der Home-Seite ist nicht dieselbe Summe wie die Finanzansicht.
Ein Tipp öffnet die Aufschlüsselung, nicht die Finanzansicht. Dort stehen die
Einnahmen, die Prognosen und die Buchungen, aus denen Gesamt und Verbraucht
entstehen.

- Einnahmen sind nur fremde Eingänge. Die eigene IBAN, Dividenden, Zinsen und
  Rückerstattungen zählen nicht. Offene Gehaltsprognosen im Zeitraum zählen
  weiter.
- Verbrauch sind normale Ausgaben plus Aktienkäufe und Sparplan-Ausführungen.
  Eine erstattete Ausgabe zählt nur mit dem Rest. Andere Umbuchungen zählen
  nicht.
- Das Tagesbudget ist das verbleibende Budget geteilt durch die Tage bis zum
  nächsten Gehalt.

### Trade-Republic-Import

Der Import ist vom Bankimport getrennt. In der Einrichtung kommt er nach dem
Hauptkonto und nach dem optionalen CSV- oder CAMT-Import. Unter Einstellungen
steht er in einem eigenen Abschnitt. Ein Zielkonto gibt es nur für CSV und
CAMT. Ein PDF wird dort nicht automatisch erkannt.

Gelesen wird die Umsatzübersicht mit Datum, Typ, Beschreibung, Zahlungseingang,
Zahlungsausgang und Saldo.

- Handel verändert das Depot und das verknüpfte Girokonto.
- Kartentransaktion ist eine Ausgabe des Girokontos. Eine Erstattung, die den
  Saldo erhöht, bleibt positiv.
- Ertrag und Zinsen sind Einnahmen des Girokontos, keine Depotbuchung.
- Eine Überweisung auf ein eigenes Konto wird nicht mehr automatisch eine
  Umbuchung. Nach dem Import von Trade-Republic-PDF oder Sparkasse-CAMT, auch
  in der Einrichtung, erscheint ein Dialog.
- Unter „Mögliche Umbuchung“ stehen Zeilen mit gleichem Betrag, bekannter IBAN
  und Datum im Abstand von höchstens drei Tagen. Der Schalter ist aus. Nur wenn
  er an ist, werden die beiden Seiten eine Umbuchung und die doppelte Buchung
  auf dem anderen Konto entfällt.
- Unter „Ähnliche Buchungen“ stehen bereits vorhandene Treffer. Der Bereich ist
  eingeklappt. Fingerabdruck oder gleicher Betrag, ähnliches Datum und gleicher
  Titel oder gleiche IBAN gelten als doppelt und werden ausgelassen. Aufklappen
  und anhaken übernimmt eine Zeile trotzdem. Ausführungen im Wochenabstand
  liegen außerhalb des Drei-Tage-Fensters und bleiben eigene Buchungen.
- Ein erneuter Import ersetzt den vorherigen Auszug dieses Girokontos und baut
  das verknüpfte Depot neu auf.

Damit die Kursdifferenz bereits vollständig verkaufter Papiere stimmt, muss der
Auszug nach einer Regeländerung neu importiert werden.
