import Testing
@testable import Lifify

/// Every scenario runs against its own in-memory store and defaults suite.
extension LififyRuleTests {
    @Suite("ChallengeScenarios")
    @MainActor
    struct ChallengeScenariosTests {
        @Test func multiplierReplacesLowerStep() async throws { try await expectScenario(ChallengeScenarios.multiplierReplacesLowerStep) }
        @Test func challengeCaptionNamesTheChallenge() async throws { try await expectScenario(ChallengeScenarios.challengeCaptionNamesTheChallenge) }
        @Test func calendarCaptionNamesTheEntry() async throws { try await expectScenario(ChallengeScenarios.calendarCaptionNamesTheEntry) }
        @Test func developerDayKeepsClockTime() async throws { try await expectScenario(ChallengeScenarios.developerDayKeepsClockTime) }
        @Test func linkingChallengePullsCalendar() async throws { try await expectScenario(ChallengeScenarios.linkingChallengePullsCalendar) }
        @Test func linkingEventPullsChallenge() async throws { try await expectScenario(ChallengeScenarios.linkingEventPullsChallenge) }
        @Test func removingChallengeDropsItsEvents() async throws { try await expectScenario(ChallengeScenarios.removingChallengeDropsItsEvents) }
        @Test func uncheckingOneEventDropsTheChallenge() async throws { try await expectScenario(ChallengeScenarios.uncheckingOneEventDropsTheChallenge) }
        @Test func manualEventStaysOffTheChallenge() async throws { try await expectScenario(ChallengeScenarios.manualEventStaysOffTheChallenge) }
        @Test func weeklyQuotaWhileOpen() async throws { try await expectScenario(ChallengeScenarios.weeklyQuotaWhileOpen) }
        @Test func extraDaysStillCount() async throws { try await expectScenario(ChallengeScenarios.extraDaysStillCount) }
        @Test func weeklyQuotaKeepsStreakWithFreeze() async throws { try await expectScenario(ChallengeScenarios.weeklyQuotaKeepsStreakWithFreeze) }
        @Test func weeklyQuotaResetsAfterFreezes() async throws { try await expectScenario(ChallengeScenarios.weeklyQuotaResetsAfterFreezes) }
        @Test func monthlyQuota() async throws { try await expectScenario(ChallengeScenarios.monthlyQuota) }
        @Test func dailyStreakCountsEachDay() async throws { try await expectScenario(ChallengeScenarios.dailyStreakCountsEachDay) }
        @Test func defaultMultipliersMatchSettings() async throws { try await expectScenario(ChallengeScenarios.defaultMultipliersMatchSettings) }
        @Test func defaultMultiplierScalesTheBaseReward() async throws { try await expectScenario(ChallengeScenarios.defaultMultiplierScalesTheBaseReward) }
        @Test func freezePriceUsesWholeFactor() async throws { try await expectScenario(ChallengeScenarios.freezePriceUsesWholeFactor) }
        @Test func recurringChallengeStaysActive() async throws { try await expectScenario(ChallengeScenarios.recurringChallengeStaysActive) }
        @Test func completionHistoryGroupsByDay() async throws { try await expectScenario(ChallengeScenarios.completionHistoryGroupsByDay) }
        @Test func dueDatesFollowRecurrence() async throws { try await expectScenario(ChallengeScenarios.dueDatesFollowRecurrence) }
        @Test func coinsStayAtBaseWithoutStreak() async throws { try await expectScenario(ChallengeScenarios.coinsStayAtBaseWithoutStreak) }
        @Test func countedCalendarTitles() async throws { try await expectScenario(ChallengeScenarios.countedCalendarTitles) }
        @Test func syncWindowCoversOneYear() async throws { try await expectScenario(ChallengeScenarios.syncWindowCoversOneYear) }
        @Test func seriesKeepsChallengeLink() async throws { try await expectScenario(ChallengeScenarios.seriesKeepsChallengeLink) }
        @Test func syncKeepsEventsOutsideTheWindow() async throws { try await expectScenario(ChallengeScenarios.syncKeepsEventsOutsideTheWindow) }
        @Test func nextYearInWindowJoinsTheLinkedWorkout() async throws { try await expectScenario(ChallengeScenarios.nextYearInWindowJoinsTheLinkedWorkout) }
        @Test func nextOccurrenceJoinsWorkout() async throws { try await expectScenario(ChallengeScenarios.nextOccurrenceJoinsWorkout) }
        @Test func workoutClockUsesFiveMinutes() async throws { try await expectScenario(ChallengeScenarios.workoutClockUsesFiveMinutes) }
        @Test func abstinenceClockCountsUp() async throws { try await expectScenario(ChallengeScenarios.abstinenceClockCountsUp) }
        @Test func abstinenceBonusUsesDifficulty() async throws { try await expectScenario(ChallengeScenarios.abstinenceBonusUsesDifficulty) }
        @Test func abstinenceMilestonesStayInOrder() async throws { try await expectScenario(ChallengeScenarios.abstinenceMilestonesStayInOrder) }
        @Test func abstinenceRunPaysDaysAndStepsOnce() async throws { try await expectScenario(ChallengeScenarios.abstinenceRunPaysDaysAndStepsOnce) }
        @Test func abstinenceExceptionLeavesTheTimer() async throws { try await expectScenario(ChallengeScenarios.abstinenceExceptionLeavesTheTimer) }
        @Test func challengeSlotFitsFourOfFive() async throws { try await expectScenario(ChallengeScenarios.challengeSlotFitsFourOfFive) }
        @Test func finishedChallengesShrinkTheSlot() async throws { try await expectScenario(ChallengeScenarios.finishedChallengesShrinkTheSlot) }
        @Test func challengeBelongsToEventAndGroup() async throws { try await expectScenario(ChallengeScenarios.challengeBelongsToEventAndGroup) }
        @Test func emptyNutritionDayKeepsStartingFreezes() async throws { try await expectScenario(ChallengeScenarios.emptyNutritionDayKeepsStartingFreezes) }
        @Test func calendarLineSitsOnTheGroup() async throws { try await expectScenario(ChallengeScenarios.calendarLineSitsOnTheGroup) }
        @Test func scheduleLineAndOpenGroup() async throws { try await expectScenario(ChallengeScenarios.scheduleLineAndOpenGroup) }
        @Test func oldChallengesAreSuggested() async throws { try await expectScenario(ChallengeScenarios.oldChallengesAreSuggested) }
        @Test func briefingNamesTheDay() async throws { try await expectScenario(ChallengeScenarios.briefingNamesTheDay) }
        @Test func todaysAbstinenceNoticeOnly() async throws { try await expectScenario(ChallengeScenarios.todaysAbstinenceNoticeOnly) }
        @Test func openChallengesGetEveningAndClock() async throws { try await expectScenario(ChallengeScenarios.openChallengesGetEveningAndClock) }
        @Test func streakWarningAndBirthdayFollowTheClock() async throws { try await expectScenario(ChallengeScenarios.streakWarningAndBirthdayFollowTheClock) }
        @Test func recentEventsCanBeAssigned() async throws { try await expectScenario(ChallengeScenarios.recentEventsCanBeAssigned) }
        @Test func linkingSetsTheChallengeDay() async throws { try await expectScenario(ChallengeScenarios.linkingSetsTheChallengeDay) }
        @Test func categoriesSplitTheActiveList() async throws { try await expectScenario(ChallengeScenarios.categoriesSplitTheActiveList) }
        @Test func briefingClockFollowsTheWeekday() async throws { try await expectScenario(ChallengeScenarios.briefingClockFollowsTheWeekday) }
        @Test func shopTilesShareARow() async throws { try await expectScenario(ChallengeScenarios.shopTilesShareARow) }
        @Test func abstinenceHistoryStaysOneRow() async throws { try await expectScenario(ChallengeScenarios.abstinenceHistoryStaysOneRow) }
        @Test func birthdayPaysFiveHundredOnce() async throws { try await expectScenario(ChallengeScenarios.birthdayPaysFiveHundredOnce) }
        @Test func birthdayFollowsTheYear() async throws { try await expectScenario(ChallengeScenarios.birthdayFollowsTheYear) }
    }

    @Suite("FeatureScenarios")
    @MainActor
    struct FeatureScenariosTests {
        @Test func manualCategoriesStayOutOfThePicker() async throws { try await expectScenario(FeatureScenarios.manualCategoriesStayOutOfThePicker) }
        @Test func manualPickerMatchesTheAmountField() async throws { try await expectScenario(FeatureScenarios.manualPickerMatchesTheAmountField) }
        @Test func symbolChoicesIncludeLeafAndCigarette() async throws { try await expectScenario(FeatureScenarios.symbolChoicesIncludeLeafAndCigarette) }
        @Test func lightAndDarkPaintsDiffer() async throws { try await expectScenario(FeatureScenarios.lightAndDarkPaintsDiffer) }
        @Test func fourPalettesKeepLightAndDark() async throws { try await expectScenario(FeatureScenarios.fourPalettesKeepLightAndDark) }
        @Test func briefingDaysSitInOneRow() async throws { try await expectScenario(FeatureScenarios.briefingDaysSitInOneRow) }
        @Test func advancedEditorSettingsStartClosed() async throws { try await expectScenario(FeatureScenarios.advancedEditorSettingsStartClosed) }
        @Test func cardsUseTwoColumns() async throws { try await expectScenario(FeatureScenarios.cardsUseTwoColumns) }
        @Test func sharedCardRoundsTheEnds() async throws { try await expectScenario(FeatureScenarios.sharedCardRoundsTheEnds) }
        @Test func caloriesFollowBodyAndGoal() async throws { try await expectScenario(FeatureScenarios.caloriesFollowBodyAndGoal) }
        @Test func trainingDayRaisesTheCalorieTarget() async throws { try await expectScenario(FeatureScenarios.trainingDayRaisesTheCalorieTarget) }
        @Test func fastFoodCostsAndACleanDayPays() async throws { try await expectScenario(FeatureScenarios.fastFoodCostsAndACleanDayPays) }
        @Test func pinsStopAtFour() async throws { try await expectScenario(FeatureScenarios.pinsStopAtFour) }
        @Test func linkedSportCannotBeCheckedByHand() async throws { try await expectScenario(FeatureScenarios.linkedSportCannotBeCheckedByHand) }
        @Test func nutritionKeyDepotAndMealsFollowOneRule() async throws { try await expectScenario(FeatureScenarios.nutritionKeyDepotAndMealsFollowOneRule) }
        @Test func emptyCategoryHidesTheCheckCircle() async throws { try await expectScenario(FeatureScenarios.emptyCategoryHidesTheCheckCircle) }
        @Test func profileLibraryAndCalorieDeficit() async throws { try await expectScenario(FeatureScenarios.profileLibraryAndCalorieDeficit) }
        @Test func goalDecidesNutritionCoins() async throws { try await expectScenario(FeatureScenarios.goalDecidesNutritionCoins) }
        @Test func calendarOpensOnToday() async throws { try await expectScenario(FeatureScenarios.calendarOpensOnToday) }
        @Test func nutrientCardNamesTheMainThree() async throws { try await expectScenario(FeatureScenarios.nutrientCardNamesTheMainThree) }
        @Test func finishedChallengeStaysInItsGroup() async throws { try await expectScenario(FeatureScenarios.finishedChallengeStaysInItsGroup) }
        @Test func singleFilterShowsGroupedChallenges() async throws { try await expectScenario(FeatureScenarios.singleFilterShowsGroupedChallenges) }
        @Test func pinnedChallengesStayAboveTheFilter() async throws { try await expectScenario(FeatureScenarios.pinnedChallengesStayAboveTheFilter) }
        @Test func deletingAGroupCanLeaveTheChallenges() async throws { try await expectScenario(FeatureScenarios.deletingAGroupCanLeaveTheChallenges) }
        @Test func eventGroupStopsWhenTheSlotIsFull() async throws { try await expectScenario(FeatureScenarios.eventGroupStopsWhenTheSlotIsFull) }
    }

    @Suite("CoverageScenarios")
    @MainActor
    struct CoverageScenariosTests {
        @Test func balancesRespectTheAnchorAndTheSavingsGroup() async throws { try await expectScenario(CoverageScenarios.balancesRespectTheAnchorAndTheSavingsGroup) }
        @Test func forecastLabelsAndBankingDays() async throws { try await expectScenario(CoverageScenarios.forecastLabelsAndBankingDays) }
        @Test func occurrencesAndSavingsPlansFollowTheRules() async throws { try await expectScenario(CoverageScenarios.occurrencesAndSavingsPlansFollowTheRules) }
        @Test func budgetMathMatchesTheTiles() async throws { try await expectScenario(CoverageScenarios.budgetMathMatchesTheTiles) }
        @Test func carryShoppingAndGroupsStaySeparate() async throws { try await expectScenario(CoverageScenarios.carryShoppingAndGroupsStaySeparate) }
        @Test func portfolioCostAndSortLabels() async throws { try await expectScenario(CoverageScenarios.portfolioCostAndSortLabels) }
        @Test func holdingChangeAndSecurityPurchases() async throws { try await expectScenario(CoverageScenarios.holdingChangeAndSecurityPurchases) }
        @Test func importFilesKeepTheirRows() async throws { try await expectScenario(CoverageScenarios.importFilesKeepTheirRows) }
        @Test func fingerprintsAndImportErrors() async throws { try await expectScenario(CoverageScenarios.fingerprintsAndImportErrors) }
        @Test func importAsksAboutMissingDayRows() async throws { try await expectScenario(CoverageScenarios.importAsksAboutMissingDayRows) }
        @Test func backupRoundTripKeepsTheRecord() async throws { try await expectScenario(CoverageScenarios.backupRoundTripKeepsTheRecord) }
        @Test func shopBalanceAndRedemptionLabels() async throws { try await expectScenario(CoverageScenarios.shopBalanceAndRedemptionLabels) }
        @Test func trainingSetsAndExerciseNames() async throws { try await expectScenario(CoverageScenarios.trainingSetsAndExerciseNames) }
        @Test func tabsOnboardingAndMoreLinks() async throws { try await expectScenario(CoverageScenarios.tabsOnboardingAndMoreLinks) }
        @Test func developerToggleKeepsTheClock() async throws { try await expectScenario(CoverageScenarios.developerToggleKeepsTheClock) }
    }

    @Suite("SessionScenarios")
    @MainActor
    struct SessionScenariosTests {
        @Test func noticeReadsAmountDirectionAndTitle() async throws { try await expectScenario(SessionScenarios.noticeReadsAmountDirectionAndTitle) }
        @Test func sameBookingInsideTheWindowCountsOnce() async throws { try await expectScenario(SessionScenarios.sameBookingInsideTheWindowCountsOnce) }
        @Test func depotSetsQuantityAndCostAndInventsNothing() async throws { try await expectScenario(SessionScenarios.depotSetsQuantityAndCostAndInventsNothing) }
        @Test func deadSessionDoesNotStartAnotherLogin() async throws { try await expectScenario(SessionScenarios.deadSessionDoesNotStartAnotherLogin) }
        @Test func sparkasseAndTradeRepublicLandOnTheMatchingAccount() async throws { try await expectScenario(SessionScenarios.sparkasseAndTradeRepublicLandOnTheMatchingAccount) }
        @Test func noticeTemplateBooksTheExample() async throws { try await expectScenario(SessionScenarios.noticeTemplateBooksTheExample) }
    }
}
