import Foundation

/// Checks for the features that were already in the app.
/// They use in-memory values and the labels on screen. They do not write user data.
@MainActor
enum LififyCoverageChecks {
    static func run() -> [LififyCheckResult] {
        [
            accountKindsMatchThePicker(),
            balancesRespectTheAnchorAndTheSavingsGroup(),
            forecastLabelsAndBankingDays(),
            occurrencesAndSavingsPlansFollowTheRules(),
            budgetMathMatchesTheTiles(),
            carryShoppingAndGroupsStaySeparate(),
            portfolioCostAndSortLabels(),
            holdingChangeAndSecurityPurchases(),
            importFilesKeepTheirRows(),
            fingerprintsAndImportErrors(),
            backupRoundTripKeepsTheRecord(),
            deleteAndResetSayWhatRemains(),
            shopBalanceAndRedemptionLabels(),
            shopNamesTheShortfall(),
            trainingSetsAndExerciseNames(),
            tabBarShowsFiveAreas(),
            tabsOnboardingAndMoreLinks(),
            developerToggleKeepsTheClock()
        ]
    }

    private static func accountKindsMatchThePicker() -> LififyCheckResult {
        let labels = AccountKind.allCases.map(\.label)
        let bookings = LedgerKind.allCases.map(\.label)
        let debts = DebtDirection.allCases.map(\.label)
        let passed = labels.count == 4
            && shows(labels[0], "Girokonto", "Checking")
            && shows(labels[1], "Spartopf", "Savings pot")
            && shows(labels[2], "Oberspartopf", "Savings group")
            && shows(labels[3], "Depot", "Portfolio")
            && Set(labels).count == labels.count
            && shows(bookings[0], "Einnahme", "Income")
            && shows(bookings[1], "Ausgabe", "Expense")
            && shows(bookings[2], "Umbuchung", "Transfer")
            && shows(bookings[3], "Saldo-Korrektur", "Balance adjustment")
            && shows(debts[0], "Bekomme ich", "Owed to me")
            && shows(debts[1], "Schulde ich", "I owe")
        return check("Konten, Buchungen und Schulden zeigen ihre Namen", .account, .unit, passed, labels.joined(separator: ", "))
    }

    private static func balancesRespectTheAnchorAndTheSavingsGroup() -> LififyCheckResult {
        let day1 = berlin(2026, 1, 1)
        let day2 = berlin(2026, 1, 2)
        let day3 = berlin(2026, 1, 3)
        let checking = Account(name: "Giro", kind: .checking, isMain: true)
        let group = Account(name: "Gruppe", kind: .savingsGroup, isLiquid: false)
        let pot = Account(name: "Topf", kind: .savings, isLiquid: true, parentAccountID: group.id)
        let depot = Account(name: "Depot", kind: .portfolio, isLiquid: false)
        let anchor = LedgerEntry(date: day2, title: "Start", amountCents: 10_000, kind: .adjustment, accountID: checking.id, createdAt: day2)
        let before = LedgerEntry(date: day1, title: "Alt", amountCents: -500, kind: .expense, accountID: checking.id, createdAt: day1)
        let after = LedgerEntry(date: day3, title: "Neu", amountCents: -200, kind: .expense, accountID: checking.id, createdAt: day3)
        let groupAnchor = LedgerEntry(date: day2, title: "Gruppe", amountCents: 99_999, kind: .adjustment, accountID: group.id, createdAt: day2)
        let potAnchor = LedgerEntry(date: day2, title: "Topf", amountCents: 5_000, kind: .adjustment, accountID: pot.id, createdAt: day2)
        let holding = PortfolioHolding(accountID: depot.id, name: "Aktie", symbol: "ABC", quantity: 2, purchasePriceCents: 100, currentPriceCents: 150)
        let entries = [anchor, before, after, groupAnchor, potAnchor]
        let checkingBalance = FinanceService.balance(for: checking, entries: entries, holdings: [])
        let depotBalance = FinanceService.balance(for: depot, entries: [], holdings: [holding])
        let total = FinanceService.totalBalance(accounts: [checking, group, pot, depot], entries: entries, holdings: [holding])
        let passed = checkingBalance == 9_800
            && depotBalance == 300
            && total == 15_100
            && shows(checking.kind.label, "Girokonto", "Checking")
            && shows(depot.kind.label, "Depot", "Portfolio")
        return check(
            "Saldo-Anker, Oberspartopf und Depotwert",
            .account,
            .integration,
            passed,
            "Giro \(checkingBalance) Cent ist Anker 10000 minus 200. Depot \(depotBalance) Cent ist 2 mal 150. Summe \(total) Cent ist Giro plus Spartopf 5000 plus Depot. Die Gruppe 99999 zählt nicht."
        )
    }

    private static func forecastLabelsAndBankingDays() -> LififyCheckResult {
        let cadences = Cadence.allCases.map(\.label)
        let rules = DueRule.allCases.map(\.label)
        let first = CalendarService.dueDate(year: 2026, month: 1, day: 1, rule: .firstBusinessDay)
        let last = CalendarService.dueDate(year: 2026, month: 5, day: 31, rule: .lastBusinessDay)
        let firstParts = berlinParts(first)
        let lastParts = berlinParts(last)
        let passed = shows(cadences[0], "Wöchentlich", "Weekly")
            && shows(cadences[1], "Alle zwei Wochen", "Biweekly")
            && shows(cadences[2], "Monatlich", "Monthly")
            && shows(cadences[3], "Jährlich", "Yearly")
            && shows(rules[0], "Kalendertag", "Calendar day")
            && shows(rules[1], "Erster Bankarbeitstag", "First banking day")
            && shows(rules[2], "Letzter Bankarbeitstag", "Last banking day")
            && !CalendarService.isBankingDay(berlin(2026, 1, 1))
            && CalendarService.isBankingDay(berlin(2026, 1, 2))
            && !CalendarService.isBankingDay(berlin(2026, 5, 1))
            && !CalendarService.isBankingDay(berlin(2026, 5, 14))
            && firstParts.day == 2 && firstParts.month == 1
            && lastParts.day == 29 && lastParts.month == 5
            && CalendarService.chargeDays(for: .weekly) == [2, 9, 16, 23]
            && CalendarService.chargeDays(for: .biweekly) == [2, 16]
        return check(
            "Fälligkeit und Bankarbeitstage",
            .forecast,
            .unit,
            passed,
            "Erster Bankarbeitstag im Januar ist der \(firstParts.day ?? 0). Letzter Bankarbeitstag im Mai ist der \(lastParts.day ?? 0), weil der 31. ein Sonntag und der 30. ein Samstag ist."
        )
    }

    private static func occurrencesAndSavingsPlansFollowTheRules() -> LififyCheckResult {
        let monthly = CalendarService.nextOccurrences(
            firstDate: berlin(2026, 1, 15),
            cadence: .monthly,
            rule: .calendarDay,
            day: 15,
            endDate: nil,
            through: berlin(2026, 3, 20)
        )
        let weekly = CalendarService.nextOccurrences(
            firstDate: berlin(2026, 1, 5),
            cadence: .weekly,
            rule: .calendarDay,
            day: 1,
            endDate: nil,
            through: berlin(2026, 1, 26)
        )
        let plans = CalendarService.savingsPlanDates(
            cadence: .monthly,
            from: berlin(2026, 5, 1),
            through: berlin(2026, 5, 31)
        )
        let planDays = plans.map { berlinParts($0).day }
        let text = CalendarService.savingsPlanScheduleText(cadence: .weekly)
        let passed = monthly.count == 3
            && monthly.allSatisfy { berlinParts($0).day == 15 }
            && weekly.count == 4
            && planDays == [4]
            && !planDays.contains(2)
            && (text.contains("2., 9., 16. und 23.") || text.contains("2nd, 9th, 16th and 23rd"))
        return check(
            "Wiederholungen und Sparplan-Abbuchung",
            .forecast,
            .integration,
            passed,
            "Monatlich \(monthly.count) Termine, wöchentlich \(weekly.count). Die Mai-Abbuchung landet am \(planDays), weil der 1. ein Feiertag und der 2. ein Samstag ist."
        )
    }

    private static func budgetMathMatchesTheTiles() -> LififyCheckResult {
        let snapshot = HomeBudgetSnapshot(
            planned: 1_000,
            spent: 2_500,
            nextSalary: nil,
            periodStart: berlin(2026, 3, 1),
            periodEnd: berlin(2026, 3, 31),
            countsAllExpenses: true,
            incomeLines: [],
            forecastLines: [],
            forecastAdjustment: 0,
            expenseLines: [],
            purchaseLines: [],
            variableLines: [],
            poolLines: []
        )
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let march = CalendarService.periodKey(for: berlin(2026, 3, 20), mode: .salaryPeriod, startDay: 1)
        let marchEnd = CalendarService.periodKey(for: berlin(2026, 3, 31), mode: .salaryPeriod, startDay: 1)
        let april = CalendarService.periodKey(for: berlin(2026, 4, 1), mode: .salaryPeriod, startDay: 1)
        let year = CalendarService.periodKey(for: berlin(2026, 11, 8), mode: .calendarYear, startDay: 1)
        let modes = DashboardPeriodMode.allCases.map(\.label)
        let themes = AppTheme.allCases.map(\.label)
        let passed = snapshot.remaining == -1_500
            && Money.signed(cents: snapshot.remaining).contains("15")
            && VariableBudgetAccounts.share(total: 100, accountID: first, targets: [first, second, third]) == 34
            && VariableBudgetAccounts.share(total: 100, accountID: second, targets: [first, second, third]) == 33
            && march == marchEnd
            && march != april
            && year == "2026"
            && shows(modes[0], "Kalendermonat", "Calendar month")
            && shows(modes[1], "Seit letztem Gehalt", "Since last salary")
            && shows(themes[0], "System", "System")
            && shows(themes[1], "Hell", "Light")
            && shows(themes[2], "Dunkel", "Dark")
            && shows(FinanceTileCopy.applied, "Angewendet", "Applied")
            && shows(FinanceTileCopy.planned, "Geplant", "Planned")
        return check("Restbudget, Anteil und Zeitraum", .budget, .unit, passed, Money.signed(cents: snapshot.remaining))
    }

    private static func carryShoppingAndGroupsStaySeparate() -> LififyCheckResult {
        let now = Date()
        let created = Calendar.current.date(byAdding: .month, value: -1, to: now) ?? now
        let pool = BudgetPool(name: "Essen", amountCents: 10_000, periodMode: .salaryPeriod, isScalable: true, createdAt: created)
        let keys = CalendarService.periodKeys(from: created, through: now, pool: pool)
        let current = CalendarService.periodKey(for: now, pool: pool)
        let previous = keys.first ?? ""
        let spent = TransactionSplit(transactionID: UUID(), targetID: pool.id, kind: .budgetPool, periodKey: previous, amountCents: 4_000)
        let over = TransactionSplit(transactionID: UUID(), targetID: pool.id, kind: .budgetPool, periodKey: previous, amountCents: 15_000)
        let carry = FinanceService.poolCarry(pool: pool, currentPeriodKey: current, splits: [spent])
        let negative = FinanceService.poolCarry(pool: pool, currentPeriodKey: current, splits: [over])
        var fixed = pool
        fixed.isScalable = false
        let stopped = FinanceService.poolCarry(pool: fixed, currentPeriodKey: current, splits: [spent])
        let period = ForecastPeriod(start: berlin(2026, 3, 1), end: berlin(2026, 3, 31))
        let open = ShoppingItem(name: "Milch", amountCents: 199, plannedDate: berlin(2026, 3, 10))
        let bought = ShoppingItem(name: "Brot", amountCents: 250, plannedDate: berlin(2026, 3, 11), isPurchased: true)
        let bias = FinanceService.shoppingBias(shopping: [open, bought], entries: [], period: period)
        let legacy = BudgetPool(name: "Alt", amountCents: 1, periodMode: .salaryPeriod, salaryStartDay: 15)
        let marchKey = CalendarService.periodKey(for: berlin(2026, 3, 20), pool: legacy)
        let aprilKey = CalendarService.periodKey(for: berlin(2026, 4, 2), pool: legacy)
        let oldKey = "2026-03-15:2026-04-14"
        let entry = LedgerEntry(title: "Essen", amountCents: -800, kind: .expense)
        let line = ExpenseGroupLine(groupID: UUID(), name: "Essen", amountCents: 800)
        let passed = keys.count >= 2
            && previous != current
            && carry == 6_000
            && negative == -5_000
            && stopped == 0
            && bias.planned == 199
            && bias.applied == 250
            && CalendarService.splitCounts(in: marchKey, splitKey: oldKey, pool: legacy)
            && !CalendarService.splitCounts(in: aprilKey, splitKey: oldKey, pool: legacy)
            && entry.amountCents == -800
            && line.amountCents == 800
            && shows(FinanceMoreDirectory.rows[1].title, "Ausgabengruppen", "Expense groups")
        return check("Übertrag, Einkauf und Ausgabengruppe", .budget, .integration, passed, "Übertrag \(carry), geplant \(bias.planned)")
    }

    private static func portfolioCostAndSortLabels() -> LififyCheckResult {
        let buy = HoldingLot(date: berlin(2026, 2, 1), quantity: 2, unitPriceCents: 500, amountCents: 1_000, isSale: false, isSavingsPlan: false)
        let sale = HoldingLot(date: berlin(2026, 3, 1), quantity: 1, unitPriceCents: 500, amountCents: 700, isSale: true, isSavingsPlan: false)
        let average = HoldingMaintenance.averagePurchaseCents(for: [buy, sale])
        let sorts = PortfolioSort.allCases.map(\.label)
        let units = PortfolioUnit.allCases.map(\.label)
        let passed = average?.quantity == 1.0
            && average?.priceCents == 500
            && shows(sorts[0], "Wert", "Value")
            && shows(sorts[1], "Kauf", "Purchase")
            && sorts[2] == "A–Z"
            && units == ["%", "€"]
        return check("Einstand und Sortierung im Depot", .portfolio, .unit, passed, "Preis \(average?.priceCents ?? -1)")
    }

    private static func holdingChangeAndSecurityPurchases() -> LififyCheckResult {
        let depot = Account(name: "Depot", kind: .portfolio)
        let checking = Account(name: "Giro", kind: .checking, iban: "DE89370400440532013000")
        let holding = PortfolioHolding(accountID: depot.id, name: "Aktie", quantity: 2, purchasePriceCents: 100, currentPriceCents: 150)
        let performance = holdingPerformance(holding)
        let purchase = LedgerEntry(title: "Kauf", amountCents: 300, kind: .transfer, fromAccountID: checking.id, toAccountID: depot.id)
        let move = LedgerEntry(title: "Umbuchung", amountCents: 300, kind: .transfer, fromAccountID: checking.id, toAccountID: UUID())
        let dividend = LedgerEntry(title: "Dividende", notes: "Typ: Ertrag", amountCents: 40, kind: .income, accountID: checking.id)
        let salary = LedgerEntry(title: "Gehalt", amountCents: 1_000, kind: .income, accountID: checking.id)
        let passed = performance.value == 300
            && performance.purchaseCents == 100
            && performance.dayCents == nil
            && PortfolioCashFlow.isSecurityPurchase(purchase, portfolioIDs: [depot.id])
            && !PortfolioCashFlow.isSecurityPurchase(move, portfolioIDs: [depot.id])
            && !ExternalIncome.countsInHomeBudget(dividend, accounts: [checking, depot])
            && ExternalIncome.countsInHomeBudget(salary, accounts: [checking, depot])
            && shows(FinanceTileCopy.shopping, "Einkaufszettel", "Shopping list")
        return check("Kaufveränderung und Depotkauf", .portfolio, .integration, passed, "Wert \(performance.value), Kauf \(performance.purchaseCents)")
    }

    private static func importFilesKeepTheirRows() -> LififyCheckResult {
        let csv = """
        Buchungstag;Betrag;Verwendungszweck;Empfaenger-IBAN
        02.01.2026;-12,50;Bäcker;DE89370400440532013000
        """
        let xml = """
        <Document><Ntry><Amt>19.99</Amt><CdtDbtInd>DBIT</CdtDbtInd><BookgDt><Dt>2026-01-02</Dt></BookgDt><AddtlNtryInf>Cafe</AddtlNtryInf><CdtrAcct><IBAN>DE89370400440532013000</IBAN></CdtrAcct></Ntry></Document>
        """
        let rows = (try? BankImportService.parseCSV(csv)) ?? []
        let camt = (try? BankImportService.parseCAMT(data: Data(xml.utf8))) ?? []
        let again = (try? BankImportService.parseCSV(csv)) ?? []
        let passed = rows.count == 1
            && rows[0].title == "Bäcker"
            && rows[0].amountCents == -1_250
            && rows[0].recipientIBAN == "DE89370400440532013000"
            && rows[0].notes.contains("DE89370400440532013000")
            && (rows[0].notes.contains("Empfänger-IBAN") || rows[0].notes.contains("Recipient IBAN"))
            && camt.count == 1
            && camt[0].title == "Cafe"
            && camt[0].amountCents == -1_999
            && again.first?.fingerprint == rows.first?.fingerprint
        return check("CSV und CAMT zeigen die Buchung", .bankImport, .unit, passed, "CSV \(rows.count), CAMT \(camt.first?.amountCents ?? 0)")
    }

    private static func fingerprintsAndImportErrors() -> LififyCheckResult {
        let day = berlin(2026, 1, 2)
        let first = BankImportService.makeFingerprint(date: day, amount: -1_250, title: "Bäcker", iban: "DE89370400440532013000")
        let second = BankImportService.makeFingerprint(date: day, amount: -1_250, title: "Bäcker", iban: "DE89370400440532013000")
        let other = BankImportService.makeFingerprint(date: day, amount: -1_251, title: "Bäcker", iban: "DE89370400440532013000")
        var pdf = ""
        do {
            _ = try BankImportService.parseDocument(data: Data("%PDF-1.4".utf8), fileExtension: "pdf")
        } catch let error as BankImportError {
            pdf = error.errorDescription ?? ""
        } catch {
            pdf = error.localizedDescription
        }
        var columns = ""
        do {
            _ = try BankImportService.parseCSV("foo;bar\n1;2")
        } catch let error as BankImportError {
            columns = error.errorDescription ?? ""
        } catch {
            columns = error.localizedDescription
        }
        let passed = first == second
            && first != other
            && first.count == 64
            && shows(pdf, "PDF-Dateien gehören in den separaten Trade-Republic-Import.", "PDF files belong in the separate Trade Republic import.")
            && shows(columns, "CSV-Spalten wurden nicht erkannt.", "CSV columns were not recognized.")
        return check("Fingerabdruck und Import-Hinweise", .bankImport, .integration, passed, pdf)
    }

    private static func backupRoundTripKeepsTheRecord() -> LififyCheckResult {
        let id = UUID()
        let backup = LififyBackup(
            version: 4,
            exportedAt: berlin(2026, 11, 8),
            records: [BackupRecord(type: "account", id: id, strings: ["Giro"], integers: [1])]
        )
        let data = (try? JSONEncoder().encode(backup)) ?? Data()
        let decoded = try? JSONDecoder().decode(LififyBackup.self, from: data)
        let prefixes = BackupScope.allCases.map(\.exportFilenamePrefix)
        let passed = decoded?.version == 4
            && decoded?.records.first?.id == id
            && decoded?.records.first?.strings == ["Giro"]
            && prefixes == ["Lifify", "Lifify-Finanzen", "Lifify-Challenges", "Lifify-Training"]
        return check("Sicherung behält das Konto", .backup, .unit, passed, prefixes.joined(separator: ", "))
    }

    private static func deleteAndResetSayWhatRemains() -> LififyCheckResult {
        let deleteAll = DestructiveAction.deleteData
        let reset = DestructiveAction.resetApp
        let finance = DestructiveAction.deleteFinance
        let passed = shows(deleteAll.title, "Alle Daten löschen?", "Delete all data?")
            && (deleteAll.message.contains("Konten") || deleteAll.message.contains("Accounts"))
            && (deleteAll.message.contains("bleiben") || deleteAll.message.contains("remain"))
            && shows(reset.title, "App vollständig zurücksetzen?", "Reset the entire app?")
            && (reset.message.contains("Konten") || reset.message.contains("Accounts"))
            && (reset.message.contains("Ersteinrichtung") || reset.message.contains("Initial setup"))
            && shows(finance.title, "Finanzen löschen?", "Delete finance?")
            && (finance.message.contains("Konten") || finance.message.contains("Accounts"))
            && finance.message != reset.message
        return check("Löschen und Zurücksetzen sagen, was bleibt", .backup, .integration, passed, reset.title)
    }

    private static func shopBalanceAndRedemptionLabels() -> LififyCheckResult {
        let transactions = [
            CoinTransaction(title: "Serie", amount: 10),
            CoinTransaction(title: "Bonus", amount: 5),
            CoinTransaction(title: "Kauf", amount: -3)
        ]
        let balance = ChallengeService.walletBalance(transactions: transactions)
        let reward = RewardItem(title: "Kino", price: 25, icon: "film")
        let passed = balance == 12
            && balance < reward.price
            && shows(ShopCopy.notEnough, "Nicht genug Coins.", "Not enough coins.")
            && shows(ShopCopy.oneTime, "Einmalig", "One-time")
            && shows(ShopCopy.repeatable, "Mehrmals", "Repeatable")
            && shows(ShopCopy.redemption, "Einlösbarkeit", "Redemption")
            && reward.icon == "film"
        return check("Wallet und Einlösbarkeit", .shop, .unit, passed, "Guthaben \(balance)")
    }

    private static func shopNamesTheShortfall() -> LififyCheckResult {
        let balance = ChallengeService.walletBalance(transactions: [CoinTransaction(title: "Serie", amount: 12)])
        let reward = RewardItem(title: "Kino", price: 25)
        let passed = balance < reward.price
            && shows(ShopCopy.notEnough, "Nicht genug Coins.", "Not enough coins.")
            && shows(ShopCopy.oneTime, "Einmalig", "One-time")
            && shows(ShopCopy.repeatable, "Mehrmals", "Repeatable")
        return check("Der Shop nennt fehlende Coins", .shop, .integration, passed, "Guthaben \(balance), Preis \(reward.price)")
    }

    private static func trainingSetsAndExerciseNames() -> LififyCheckResult {
        let done = WorkoutSessionSet(weightKg: 10, reps: 8, completed: true, targetWeightKg: 10, targetReps: 8)
        let short = WorkoutSessionSet(weightKg: 10, reps: 6, completed: true, targetWeightKg: 10, targetReps: 8)
        let open = WorkoutSessionSet(weightKg: 10, reps: 8, completed: false, targetWeightKg: 10, targetReps: 8)
        let name = ExerciseName.formatted("barbell squat")
        let passed = WorkoutProgress.metPlan([done, done])
            && !WorkoutProgress.metPlan([done, short])
            && WorkoutProgress.volume(of: [done, open]) == 80.0
            && name == "Barbell Squat"
            && shows(ExerciseSearchCopy.create, "Übung anlegen", "Create exercise")
            && shows(ExerciseSearchCopy.nameField, "Name der Übung", "Exercise name")
            && RestChime.tones.contains { $0.id == 1005 && $0.name == "Alarm" }
        return check("Trainingssatz, Übungsname und Klingelton", .training, .integration, passed, name)
    }

    private static func tabBarShowsFiveAreas() -> LififyCheckResult {
        let tabs = AppTabs.items()
        let passed = tabs.map(\.symbol) == ["house", "eurosign.circle", "target", "leaf.fill", "gear"]
            && shows(tabs[0].title, "Home", "Home")
            && shows(tabs[1].title, "Finanzen", "Finance")
            && shows(tabs[2].title, "Challenges", "Challenges")
            && shows(tabs[3].title, "Gesundheit", "Health")
            && shows(tabs[4].title, "Einstellungen", "Settings")
            && shows(OnboardingSteps.title, "Lifify einrichten", "Set up Lifify")
            && shows(OnboardingSteps.account, "Hauptkonto", "Main account")
            && !tabs.contains { $0.symbol == "vision" }
        return check("Die Leiste zeigt fünf Bereiche", .navigation, .unit, passed, tabs.map(\.title).joined(separator: ", "))
    }

    private static func tabsOnboardingAndMoreLinks() -> LififyCheckResult {
        let tabs = AppTabs.items()
        let more = FinanceMoreDirectory.rows
        let reminder = ChallengeCalendarEvent(
            title: "Nicht rauchen",
            startDate: berlin(2026, 11, 8),
            endDate: berlin(2026, 11, 8),
            externalIdentifier: "reminder:1"
        )
        let event = ChallengeCalendarEvent(
            title: "Termin",
            startDate: berlin(2026, 11, 8),
            endDate: berlin(2026, 11, 8)
        )
        let passed = tabs.map(\.symbol) == ["house", "eurosign.circle", "target", "leaf.fill", "gear"]
            && tabs.map(\.title) == [
                L("Home", "Home"),
                L("Finanzen", "Finance"),
                L("Challenges", "Challenges"),
                L("Gesundheit", "Health"),
                L("Einstellungen", "Settings")
            ]
            && shows(tabs[1].title, "Finanzen", "Finance")
            && !tabs.contains { $0.title == "Bucketlist" || $0.symbol == "vision" }
            && AppChrome.glassScreens.contains("finance")
            && shows(OnboardingSteps.title, "Lifify einrichten", "Set up Lifify")
            && shows(OnboardingSteps.newSetup, "Neu einrichten", "Set up as new")
            && shows(OnboardingSteps.restore, "JSON-Sicherung laden", "Restore JSON backup")
            && shows(OnboardingSteps.account, "Hauptkonto", "Main account")
            && OnboardingSteps.tradeRepublic == "Trade Republic"
            && more.map(\.route) == [.budgetPools, .expenseGroups, .debts]
            && shows(more[0].title, "Budgetpools", "Budget pools")
            && shows(more[2].title, "Schulden", "Debts")
            && FinanceMoreDirectory.rowFontName == "body"
            && FinanceMoreDirectory.sectionFontName == "headline"
            && FinanceMoreDirectory.rowVerticalPadding == 14
            && FinanceMoreDirectory.rowVerticalPadding < 18
            && FinanceMoreDirectory.sectionSpacing <= 8
            && reminder.isReminderSuggestion
            && !event.isReminderSuggestion
            && shows(RecommendationCopy.empty, "Keine importierten Empfehlungen", "No imported recommendations")
            && shows(RecommendationCopy.heading, "Empfehlungen", "Recommendations")
        return check("Tabs, Einrichtung und Weitere Bereiche", .navigation, .integration, passed, more.map(\.title).joined(separator: ", "))
    }

    private static func developerToggleKeepsTheClock() -> LififyCheckResult {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 8)) ?? .distantPast
        let time = calendar.date(from: DateComponents(year: 2024, month: 1, day: 1, hour: 7, minute: 30, second: 15)) ?? .distantPast
        let combined = AppClock.combining(day: day, time: time, calendar: calendar)
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: combined)
        let passed = parts.year == 2026 && parts.month == 11 && parts.day == 8
            && parts.hour == 7 && parts.minute == 30 && parts.second == 15
            && shows(DeveloperCopy.toggle, "Entwicklermodus", "Developer mode")
            && AppClock.modeKey == "lifify.developerMode"
        return check("Entwicklertag und Schalter", .developer, .integration, passed, DeveloperCopy.toggle)
    }

    private static func shows(_ value: String, _ german: String, _ english: String) -> Bool {
        value == german || value == english
    }

    private static func berlin(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .distantPast
    }

    private static func berlinParts(_ date: Date) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
        return calendar.dateComponents([.year, .month, .day], from: date)
    }

    private static func check(
        _ name: String,
        _ topic: LififyCheckTopic,
        _ kind: LififyCheckKind,
        _ passed: Bool,
        _ detail: String
    ) -> LififyCheckResult {
        LififyCheckResult(name: name, passed: passed, detail: passed ? nil : detail, reading: detail, kind: kind, topic: topic)
    }
}
