package page.puzzak.geminilocal

import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.common.GenAiException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PaiosModelHelperTest {

    @Test
    fun isPolicyCheckException_matchesGenAiRequestProcessingError() {
        val ex = GenAiException(
            "Request doesn't pass certain policy check.",
            null,
            GenAiException.ErrorCode.REQUEST_PROCESSING_ERROR
        )
        assertTrue(PaiosModelHelper.isPolicyCheckException(ex))
    }

    @Test
    fun isPolicyCheckException_matchesWrappedCauseChain() {
        val root = GenAiException(
            "pre-processing failed",
            null,
            GenAiException.ErrorCode.REQUEST_PROCESSING_ERROR
        )
        val wrapped = RuntimeException("Stream failed", IllegalStateException(root))
        assertTrue(PaiosModelHelper.isPolicyCheckException(wrapped))
    }

    @Test
    fun isPolicyCheckException_matchesErrorCode4AndPolicyMessage() {
        assertTrue(
            PaiosModelHelper.isPolicyCheckException(
                Exception("[ErrorCode 4] Request doesn't pass certain policy check.")
            )
        )
        assertTrue(
            PaiosModelHelper.isPolicyCheckException(
                Exception("AICore returned REQUEST_PROCESSING_ERROR")
            )
        )
        assertTrue(
            PaiosModelHelper.isPolicyCheckException(
                Exception("Failed with Error 4")
            )
        )
    }

    @Test
    fun isPolicyCheckException_ignoresNonPolicyErrors() {
        val busyEx = GenAiException("Busy", null, GenAiException.ErrorCode.BUSY)
        assertFalse(PaiosModelHelper.isPolicyCheckException(busyEx))
        assertFalse(PaiosModelHelper.isPolicyCheckException(Exception("HTTP Error 404 Not Found")))
        assertFalse(PaiosModelHelper.isPolicyCheckException(Exception("Error 42: unrelated")))
        assertFalse(PaiosModelHelper.isPolicyCheckException(Exception("Connection timed out")))
    }

    @Test
    fun isBusyException_distinguishesBusyFromPolicyError() {
        val busyEx = GenAiException("Busy", null, GenAiException.ErrorCode.BUSY)
        val policyEx = GenAiException(
            "Policy",
            null,
            GenAiException.ErrorCode.REQUEST_PROCESSING_ERROR
        )
        assertTrue(PaiosModelHelper.isBusyException(busyEx))
        assertFalse(PaiosModelHelper.isBusyException(policyEx))
    }

    @Test
    fun trimSystemInstructionToWordLimit_handlesNullShortAndLongText() {
        assertNull(PaiosModelHelper.trimSystemInstructionToWordLimit(null))
        assertNull(PaiosModelHelper.trimSystemInstructionToWordLimit("   \n\t "))

        val shortPrompt = "You are PAIOS, an on-device assistant."
        assertEquals(shortPrompt, PaiosModelHelper.trimSystemInstructionToWordLimit(shortPrompt, maxWords = 10))

        val words = (1..200).map { "word$it" }
        val longPrompt = words.joinToString(" ")
        val trimmed = PaiosModelHelper.trimSystemInstructionToWordLimit(longPrompt, maxWords = 140)!!
        val resultWords = trimmed.split(Regex("""\s+"""))
        assertEquals(140, resultWords.size)
        assertEquals("word1", resultWords.first())
        assertEquals("word140", resultWords.last())
    }

    @Test
    fun isPureGreetingOrSmallTalk_matchesGreetingsAndRejectsRealQueries() {
        assertTrue(PaiosModelHelper.isPureGreetingOrSmallTalk("hi"))
        assertTrue(PaiosModelHelper.isPureGreetingOrSmallTalk("  Hi!  "))
        assertTrue(PaiosModelHelper.isPureGreetingOrSmallTalk("Hello there."))
        assertTrue(PaiosModelHelper.isPureGreetingOrSmallTalk("Good morning!"))
        assertTrue(PaiosModelHelper.isPureGreetingOrSmallTalk("How are you?"))
        assertTrue(PaiosModelHelper.isPureGreetingOrSmallTalk("Привіт!"))
        assertTrue(PaiosModelHelper.isPureGreetingOrSmallTalk("ok"))

        assertFalse(PaiosModelHelper.isPureGreetingOrSmallTalk(""))
        assertFalse(PaiosModelHelper.isPureGreetingOrSmallTalk("is there an air raid alert now in Kyiv?"))
        assertFalse(PaiosModelHelper.isPureGreetingOrSmallTalk("hi, what's on my screen?"))
        assertFalse(PaiosModelHelper.isPureGreetingOrSmallTalk("Summarize this page"))
    }

    @Test
    fun computeInsetCropRect_cropsAndScalesSafely() {
        val exact = PaiosModelHelper.computeInsetCropRect(
            bitmapWidth = 1080,
            bitmapHeight = 2400,
            insetLeft = 0,
            insetTop = 132,
            insetRight = 0,
            insetBottom = 64
        )
        assertEquals(PaiosModelHelper.CropRect(0, 132, 1080, 2204), exact)

        val scaled = PaiosModelHelper.computeInsetCropRect(
            bitmapWidth = 540,
            bitmapHeight = 1200,
            insetLeft = 0,
            insetTop = 132,
            insetRight = 0,
            insetBottom = 64,
            boundsWidth = 1080,
            boundsHeight = 2400
        )
        assertEquals(PaiosModelHelper.CropRect(0, 66, 540, 1102), scaled)

        assertNull(
            PaiosModelHelper.computeInsetCropRect(
                bitmapWidth = 1080,
                bitmapHeight = 2400,
                insetLeft = 0,
                insetTop = 0,
                insetRight = 0,
                insetBottom = 0
            )
        )
        assertNull(
            PaiosModelHelper.computeInsetCropRect(
                bitmapWidth = 100,
                bitmapHeight = 100,
                insetLeft = 40,
                insetTop = 40,
                insetRight = 40,
                insetBottom = 40,
                minRemainingPx = 64
            )
        )
    }

    @Test
    fun normalizeFinishReason_handlesNullUnknownAndValidCodes() {
        assertNull(PaiosModelHelper.normalizeFinishReason(null))
        assertNull(PaiosModelHelper.normalizeFinishReason(""))
        assertNull(PaiosModelHelper.normalizeFinishReason("null"))
        assertNull(PaiosModelHelper.normalizeFinishReason("UNKNOWN"))
        assertEquals("0", PaiosModelHelper.normalizeFinishReason(0))
        assertEquals("1", PaiosModelHelper.normalizeFinishReason(" 1 "))
        assertEquals("-100", PaiosModelHelper.normalizeFinishReason(-100))
        assertEquals("MAX_TOKENS", PaiosModelHelper.normalizeFinishReason("MAX_TOKENS"))
    }

    @Test
    fun isTruncationHeuristic_detectsMidClauseAndPreservesCompleteSentences() {
        assertTrue(PaiosModelHelper.isTruncationHeuristic("older,"))
        assertTrue(PaiosModelHelper.isTruncationHeuristic("Here'"))
        assertTrue(PaiosModelHelper.isTruncationHeuristic("I prioritize your"))
        assertTrue(PaiosModelHelper.isTruncationHeuristic("First point:"))
        assertTrue(
            PaiosModelHelper.isTruncationHeuristic(
                "The concept of a \"paperclip maximizer\" is a thought experiment that highlights a potential risk with advanced"
            )
        )
        assertTrue(PaiosModelHelper.isTruncationHeuristic("This highlights a potential"))
        assertTrue(PaiosModelHelper.isTruncationHeuristic("It reveals an important"))
        assertTrue(PaiosModelHelper.isTruncationHeuristic("We are testing the new"))
        assertTrue(PaiosModelHelper.isTruncationHeuristic("The risks of artificial"))
        assertTrue(PaiosModelHelper.isTruncationHeuristic("This leads to unintended"))

        assertFalse(PaiosModelHelper.isTruncationHeuristic("Yes"))
        assertFalse(PaiosModelHelper.isTruncationHeuristic("Hello!"))
        assertFalse(PaiosModelHelper.isTruncationHeuristic("Everything is complete."))
        assertFalse(PaiosModelHelper.isTruncationHeuristic("**All done.**"))
        assertFalse(PaiosModelHelper.isTruncationHeuristic("Thanks! All set."))
        assertFalse(PaiosModelHelper.isTruncationHeuristic("Everything looks good"))
        assertFalse(PaiosModelHelper.isTruncationHeuristic("Yes, happy to help"))
        assertFalse(PaiosModelHelper.isTruncationHeuristic("Sure, I can help with that today"))
        assertFalse(
            PaiosModelHelper.isTruncationHeuristic(
                "A paperclip maximizer is a thought experiment about AI alignment"
            )
        )
    }

    @Test
    fun shouldContinuePartialResponse_respectsReasonsCapsAndStallGuard() {
        // Explicit truncation reasons continue
        assertTrue(
            PaiosModelHelper.shouldContinuePartialResponse(
                finishReason = "1",
                partialText = "Partial answer",
                continuationCount = 0,
                lastRoundAddedChars = 14,
                isNanoV4 = false
            )
        )
        assertTrue(
            PaiosModelHelper.shouldContinuePartialResponse(
                finishReason = "-100",
                partialText = "Partial answer",
                continuationCount = 3,
                lastRoundAddedChars = 14,
                isNanoV4 = false
            )
        )
        assertTrue(
            PaiosModelHelper.shouldContinuePartialResponse(
                finishReason = "MAX_TOKENS",
                partialText = "Partial answer",
                continuationCount = 5,
                lastRoundAddedChars = 10,
                isNanoV4 = true
            )
        )

        // STOP / 0 rescues bounded mid-clause cutoffs on Nano v3 once, and rejects complete answers
        assertTrue(
            PaiosModelHelper.shouldContinuePartialResponse(
                finishReason = "0",
                partialText = "I prioritize your",
                continuationCount = 0,
                lastRoundAddedChars = 17,
                isNanoV4 = false,
                stopCutoffRetryCount = 0
            )
        )
        assertFalse(
            PaiosModelHelper.shouldContinuePartialResponse(
                finishReason = "0",
                partialText = "I prioritize your",
                continuationCount = 1,
                lastRoundAddedChars = 17,
                isNanoV4 = false,
                stopCutoffRetryCount = 1
            )
        )
        val paperclipCutoff =
            "The concept of a \"paperclip maximizer\" is a thought experiment that highlights a potential risk with advanced"
        assertTrue(
            PaiosModelHelper.shouldContinuePartialResponse(
                finishReason = "0",
                partialText = paperclipCutoff,
                continuationCount = 0,
                lastRoundAddedChars = paperclipCutoff.length,
                isNanoV4 = false,
                stopCutoffRetryCount = 0
            )
        )
        assertFalse(
            PaiosModelHelper.shouldContinuePartialResponse(
                finishReason = "STOP",
                partialText = paperclipCutoff,
                continuationCount = 1,
                lastRoundAddedChars = 40,
                isNanoV4 = false,
                stopCutoffRetryCount = 1
            )
        )
        assertFalse(
            PaiosModelHelper.shouldContinuePartialResponse(
                finishReason = "0",
                partialText = paperclipCutoff,
                continuationCount = 0,
                lastRoundAddedChars = paperclipCutoff.length,
                isNanoV4 = true,
                stopCutoffRetryCount = 0
            )
        )
        assertFalse(
            PaiosModelHelper.shouldContinuePartialResponse(
                finishReason = "0",
                partialText = "Sure, I can help with that today",
                continuationCount = 0,
                lastRoundAddedChars = 32,
                isNanoV4 = false,
                stopCutoffRetryCount = 0
            )
        )
        assertFalse(
            PaiosModelHelper.shouldContinuePartialResponse(
                finishReason = "0",
                partialText = "Thanks! All set.",
                continuationCount = 0,
                lastRoundAddedChars = 16,
                isNanoV4 = false,
                stopCutoffRetryCount = 0
            )
        )

        // Null reason on v3 triggers safety continuation when clearly cut mid-clause, capped at 2
        assertTrue(
            PaiosModelHelper.shouldContinuePartialResponse(
                finishReason = null,
                partialText = "I prioritize your",
                continuationCount = 0,
                lastRoundAddedChars = 17,
                isNanoV4 = false,
                nullReasonRetryCount = 0
            )
        )
        assertFalse(
            PaiosModelHelper.shouldContinuePartialResponse(
                finishReason = null,
                partialText = "I prioritize your",
                continuationCount = 2,
                lastRoundAddedChars = 17,
                isNanoV4 = false,
                nullReasonRetryCount = 2
            )
        )
        assertFalse(
            PaiosModelHelper.shouldContinuePartialResponse(
                finishReason = null,
                partialText = "I prioritize your",
                continuationCount = 0,
                lastRoundAddedChars = 17,
                isNanoV4 = true
            )
        )

        // Stall guard, stutter guard, and continuation cap
        assertFalse(
            PaiosModelHelper.shouldContinuePartialResponse(
                finishReason = "1",
                partialText = "Partial answer",
                continuationCount = 1,
                lastRoundAddedChars = 0,
                isNanoV4 = false
            )
        )
        assertFalse(
            PaiosModelHelper.shouldContinuePartialResponse(
                finishReason = "1",
                partialText = "Partial answer and... that and... that and... that",
                continuationCount = 1,
                lastRoundAddedChars = 18,
                isNanoV4 = false
            )
        )
        assertFalse(
            PaiosModelHelper.shouldContinuePartialResponse(
                finishReason = "1",
                partialText = "Partial answer",
                continuationCount = PaiosModelHelper.MAX_OVERLAY_CONTINUATIONS,
                lastRoundAddedChars = 10,
                isNanoV4 = false
            )
        )
    }

    @Test
    fun buildOverlayContinuationPrompt_boundsTailCleanlyAndStaysCompact() {
        val longPrefix = List(120) { "word$it" }.joinToString(" ")
        val exactEnd = "and I prioritize your"
        val partial = "$longPrefix $exactEnd"
        val longPersona = List(80) { "persona$it" }.joinToString(" ")
        val longQuestion = List(60) { "question$it" }.joinToString(" ")

        val spec = PaiosModelHelper.buildOverlayContinuationPrompt(
            originalQuestion = longQuestion,
            partialText = partial,
            personaAnchor = longPersona,
            languageCode = "en"
        )
        val sys = spec.instructions!!
        assertEquals("Continue.", spec.userPrompt)
        assertTrue(sys.contains("Continue seamlessly from the exact end without repeating."))
        assertTrue(
            sys.endsWith(
                "Do NOT prepend an ellipsis (...) or repeat words. Complete the answer concisely without starting new unrelated topics."
            )
        )
        assertFalse(sys.lines().first { it.startsWith("Persona:") }.endsWith("..."))
        assertFalse(sys.lines().first { it.startsWith("Question:") }.endsWith("...\""))
        assertTrue(sys.contains(exactEnd))
        assertTrue(sys.contains("If 'your' was cut mid-word, complete or rewrite it cleanly without spaces."))
        assertTrue(sys.length < 1400)
        assertFalse(sys.contains("word0 "))
    }

    @Test
    fun buildOverlayContinuationPrompt_preservesTrailingWordIntactAndAddsMidWordHintOnlyWhenNeeded() {
        val midWordSpec = PaiosModelHelper.buildOverlayContinuationPrompt(
            originalQuestion = "Who is Eliezer Yudkowsky?",
            partialText = "The author is Eliezer Yud"
        )
        val midWordSys = midWordSpec.instructions!!
        assertTrue(
            midWordSys.contains(
                "Partial answer tail:\nThe author is Eliezer Yud\nContinue seamlessly from the exact end without repeating. If 'Yud' was cut mid-word, complete or rewrite it cleanly without spaces."
            )
        )

        val advancedCutoffSpec = PaiosModelHelper.buildOverlayContinuationPrompt(
            originalQuestion = "what's a paperclip Maximizer?",
            partialText = "The concept of a \"paperclip maximizer\" is a thought experiment that highlights a potential risk with advanced"
        )
        val advancedSys = advancedCutoffSpec.instructions!!
        assertTrue(advancedSys.contains("highlights a potential risk with advanced\nContinue seamlessly"))
        assertTrue(advancedSys.contains("If 'advanced' was cut mid-word, complete or rewrite it cleanly without spaces."))

        val punctSpec = PaiosModelHelper.buildOverlayContinuationPrompt(
            originalQuestion = "Tell me more",
            partialText = "The author is older,"
        )
        assertTrue(punctSpec.instructions!!.contains("Partial answer tail:\nThe author is older,\n"))
        assertFalse(punctSpec.instructions.contains("was cut mid-word"))

        val spaceSpec = PaiosModelHelper.buildOverlayContinuationPrompt(
            originalQuestion = "Tell me more",
            partialText = "The author is Eliezer "
        )
        assertTrue(spaceSpec.instructions!!.contains("Partial answer tail:\nThe author is Eliezer \n"))
        assertFalse(spaceSpec.instructions.contains("was cut mid-word"))

        val longWord = "Supercalifragilisticexpialidocious"
        val longWordSpec = PaiosModelHelper.buildOverlayContinuationPrompt(
            originalQuestion = "Spell it",
            partialText = "Word: $longWord"
        )
        assertTrue(longWordSpec.instructions!!.contains("Word: $longWord"))
    }

    @Test
    fun consumeScreenContextTurn_tracksThreeTurnTtlAndExpiresSilently() {
        assertEquals(3, PaiosModelHelper.SCREEN_CONTEXT_TTL_TURNS)

        val turn1 = PaiosModelHelper.consumeScreenContextTurn(turnsRemaining = 3, hasContent = true)
        assertTrue(turn1.available)
        assertEquals(2, turn1.nextTurnsRemaining)
        assertFalse(turn1.shouldExpire)

        val turn2 = PaiosModelHelper.consumeScreenContextTurn(turnsRemaining = turn1.nextTurnsRemaining, hasContent = true)
        assertTrue(turn2.available)
        assertEquals(1, turn2.nextTurnsRemaining)
        assertFalse(turn2.shouldExpire)

        val turn3 = PaiosModelHelper.consumeScreenContextTurn(turnsRemaining = turn2.nextTurnsRemaining, hasContent = true)
        assertTrue(turn3.available)
        assertEquals(0, turn3.nextTurnsRemaining)
        assertTrue(turn3.shouldExpire)

        val turn4 = PaiosModelHelper.consumeScreenContextTurn(turnsRemaining = turn3.nextTurnsRemaining, hasContent = true)
        assertFalse(turn4.available)
        assertEquals(0, turn4.nextTurnsRemaining)
        assertTrue(turn4.shouldExpire)

        val empty = PaiosModelHelper.consumeScreenContextTurn(turnsRemaining = 3, hasContent = false)
        assertFalse(empty.available)
        assertEquals(0, empty.nextTurnsRemaining)
        assertTrue(empty.shouldExpire)
    }

    @Test
    fun buildOverlayContinuationPrompt_respectsHigherMaxQuestionCharsForSynthesis() {
        val toolResult = "Tool 'wikipedia_summary' returned: [TOOL RESULT: " +
            List(90) { "fact$it" }.joinToString(" ") + " EndOfWikiPayload]"
        val spec = PaiosModelHelper.buildOverlayContinuationPrompt(
            originalQuestion = toolResult,
            partialText = "Here is a summary of",
            maxQuestionChars = 1200
        )
        val sys = spec.instructions!!
        assertTrue(sys.contains("EndOfWikiPayload"))
        assertFalse(sys.lines().first { it.startsWith("Question:") }.endsWith("...\""))
    }

    @Test
    fun stripLeadingContinuationEllipsis_removesEllipsesAndPreservesNormalText() {
        assertEquals("", PaiosModelHelper.stripLeadingContinuationEllipsis(""))
        assertEquals("", PaiosModelHelper.stripLeadingContinuationEllipsis("..."))
        assertEquals("", PaiosModelHelper.stripLeadingContinuationEllipsis(".."))
        assertEquals("", PaiosModelHelper.stripLeadingContinuationEllipsis(". . ."))
        assertEquals("presented", PaiosModelHelper.stripLeadingContinuationEllipsis("...presented"))
        assertEquals("presented", PaiosModelHelper.stripLeadingContinuationEllipsis("... presented"))
        assertEquals("presented", PaiosModelHelper.stripLeadingContinuationEllipsis(".. presented"))
        assertEquals("presented", PaiosModelHelper.stripLeadingContinuationEllipsis(". . . presented"))
        assertEquals("presented", PaiosModelHelper.stripLeadingContinuationEllipsis(". . presented"))
        assertEquals("presented", PaiosModelHelper.stripLeadingContinuationEllipsis("…presented"))
        assertEquals("presented", PaiosModelHelper.stripLeadingContinuationEllipsis("  …  presented"))
        assertEquals("presented", PaiosModelHelper.stripLeadingContinuationEllipsis(".... presented"))
        assertEquals(".5 meters", PaiosModelHelper.stripLeadingContinuationEllipsis(".5 meters"))
        assertEquals("normal text", PaiosModelHelper.stripLeadingContinuationEllipsis("normal text"))
    }

    @Test
    fun stitchOverlayContinuation_joinsCleanlyWithoutBrokenSpacing() {
        assertEquals(
            "Here's the summary",
            PaiosModelHelper.stitchOverlayContinuation("Here'", "s the summary")
        )
        assertEquals(
            "older, and wiser.",
            PaiosModelHelper.stitchOverlayContinuation("older,", "and wiser.")
        )
        assertEquals(
            "I prioritize your privacy.",
            PaiosModelHelper.stitchOverlayContinuation("I prioritize your", "privacy.")
        )
        assertEquals(
            "I prioritize your privacy.",
            PaiosModelHelper.stitchOverlayContinuation("I prioritize your privacy", "your privacy.")
        )
        assertEquals(
            "often presented",
            PaiosModelHelper.stitchOverlayContinuation("often", "...presented")
        )
        assertEquals(
            "often presented",
            PaiosModelHelper.stitchOverlayContinuation("often", "… presented")
        )
        assertEquals(
            "often presented",
            PaiosModelHelper.stitchOverlayContinuation("often ", "...presented")
        )
        assertEquals(
            "often presented",
            PaiosModelHelper.stitchOverlayContinuation("often...", "presented")
        )
        assertEquals(
            "often presented",
            PaiosModelHelper.stitchOverlayContinuation("often…", "...presented")
        )
        assertEquals(
            "often presented",
            PaiosModelHelper.stitchOverlayContinuation("often..", ". . . presented")
        )
        assertEquals(
            "Wait what?",
            PaiosModelHelper.stitchOverlayContinuation("Wait...", "Wait... what?")
        )
        assertEquals(
            "I prioritize your privacy.",
            PaiosModelHelper.stitchOverlayContinuation("I prioritize your privacy", "...your privacy.")
        )
        assertEquals(
            "Wait",
            PaiosModelHelper.stitchOverlayContinuation("Wait", "...")
        )
        assertEquals(
            "```dart\nprint('hi');\n```",
            PaiosModelHelper.stitchOverlayContinuation("```dart\nprint('hi');", "```dart\n```")
        )
    }

    @Test
    fun stitchOverlayContinuation_deduplicatesLongWeatherClausesAndMidWordSubwords() {
        val weatherPrefix = "The forecast for November 16th is -0.5°C to "
        assertEquals(
            "The forecast for November 16th is -0.5°C to 4.5°C with light wind.",
            PaiosModelHelper.stitchOverlayContinuation(
                weatherPrefix,
                "${weatherPrefix}4.5°C with light wind."
            )
        )
        assertEquals(
            weatherPrefix,
            PaiosModelHelper.stitchOverlayContinuation(weatherPrefix, weatherPrefix.trimEnd())
        )

        val longRepeatedClause = "Today in Kyiv, expect mostly cloudy skies with temperatures ranging from -0.5°C overnight up to "
        assertTrue(longRepeatedClause.length > 80)
        assertEquals(
            "${longRepeatedClause}3.2°C in the afternoon.",
            PaiosModelHelper.stitchOverlayContinuation(
                "Weather report: $longRepeatedClause",
                "${longRepeatedClause}3.2°C in the afternoon."
            ).removePrefix("Weather report: ")
        )

        // Mid-word subword completion without inserting space
        assertEquals(
            "Eliezer Yudkowsky is a decision theorist.",
            PaiosModelHelper.stitchOverlayContinuation(
                "Eliezer Yud",
                "Yudkowsky is a decision theorist."
            )
        )
        assertEquals(
            "...Yudkowsky...",
            PaiosModelHelper.stitchOverlayContinuation("...Yud", "Yudkowsky...")
        )

        // Single-letter accidental overlap must not over-strip
        assertEquals(
            "I saw a apple",
            PaiosModelHelper.stitchOverlayContinuation("I saw a", "apple")
        )
    }

    @Test
    fun hasContinuationStutter_detectsRepeatedClausesAndIgnoresNormalText() {
        assertTrue(
            PaiosModelHelper.hasContinuationStutter(
                "The outlook is cold and... that and... that and... that"
            )
        )
        assertTrue(
            PaiosModelHelper.hasContinuationStutter(
                "Forecast summary: expect light snow tomorrow, expect light snow tomorrow, expect light snow tomorrow"
            )
        )
        assertFalse(
            PaiosModelHelper.hasContinuationStutter(
                "The forecast for November 16th is -0.5°C to 4.5°C with partly cloudy skies."
            )
        )
        assertFalse(
            PaiosModelHelper.hasContinuationStutter(
                "Section divider:\n------------------------------------\nEnd of report."
            )
        )
        assertFalse(PaiosModelHelper.hasContinuationStutter("Short text"))
    }

    @Test
    fun formatNanoAuthor_resolvesVersionsAndFallbacks() {
        assertEquals("Gemini Nano", PaiosModelHelper.formatNanoAuthor(null))
        assertEquals("Gemini Nano", PaiosModelHelper.formatNanoAuthor(""))
        assertEquals("Gemini Nano", PaiosModelHelper.formatNanoAuthor("Unknown"))
        assertEquals("Gemini Nano v3", PaiosModelHelper.formatNanoAuthor("nano-v3"))
        assertEquals("Gemini Nano v3", PaiosModelHelper.formatNanoAuthor("Gemini Nano 3"))
        assertEquals("Gemini Nano v4", PaiosModelHelper.formatNanoAuthor("nano-v4"))
        assertEquals("Gemini Nano v4", PaiosModelHelper.formatNanoAuthor("Unknown", isNanoV4 = true))
        assertEquals("Gemini Nano v2", PaiosModelHelper.formatNanoAuthor("nano-v2"))
        assertEquals("Gemini Nano v1.5", PaiosModelHelper.formatNanoAuthor("gemini-nano-1.5"))
    }

    @Test
    fun comboStatuses_toVariantList_mapsAllFourStandardCombos() {
        val combos = PaiosModelHelper.ComboStatuses(
            stableFullStatus = FeatureStatus.AVAILABLE,
            stableFastStatus = FeatureStatus.DOWNLOADABLE,
            previewFullStatus = FeatureStatus.AVAILABLE,
            previewFastStatus = FeatureStatus.UNAVAILABLE,
            stableFullBaseModelName = "nano-v3",
            previewFullBaseModelName = "nano-v4"
        )
        val variants = combos.toVariantList(
            activeStage = PaiosModelHelper.STAGE_PREVIEW,
            activePreference = PaiosModelHelper.PREF_FULL,
            activeBaseModelName = "nano-v4"
        )
        assertEquals(4, variants.size)
        assertEquals("stable", variants[0].releaseStage)
        assertEquals("full", variants[0].preference)
        assertTrue(variants[0].available)
        assertFalse(variants[0].isActive)
        assertEquals("nano-v3", variants[0].baseModelName)

        assertEquals("downloadable", variants[1].status)
        assertFalse(variants[1].available)

        assertEquals("preview", variants[2].releaseStage)
        assertEquals("full", variants[2].preference)
        assertTrue(variants[2].isActive)
        assertEquals("nano-v4", variants[2].baseModelName)

        assertEquals("unavailable", variants[3].status)
        assertTrue(variants[3].isUnavailable)
        assertFalse(variants[0].isUnavailable)
        assertTrue(combos.hasAnySupportedModel)
        assertTrue(combos.hasAnyAvailableModel)
    }

    @Test
    fun comboStatuses_reportsHasAnySupportedAndAvailableModelCorrectly() {
        val allUnavailable = PaiosModelHelper.ComboStatuses(
            stableFullStatus = FeatureStatus.UNAVAILABLE,
            stableFastStatus = FeatureStatus.UNAVAILABLE,
            previewFullStatus = FeatureStatus.UNAVAILABLE,
            previewFastStatus = FeatureStatus.UNAVAILABLE
        )
        assertFalse(allUnavailable.hasAnySupportedModel)
        assertFalse(allUnavailable.hasAnyAvailableModel)

        val onlyDownloadable = PaiosModelHelper.ComboStatuses(
            stableFullStatus = FeatureStatus.DOWNLOADABLE,
            stableFastStatus = FeatureStatus.UNAVAILABLE,
            previewFullStatus = FeatureStatus.UNAVAILABLE,
            previewFastStatus = FeatureStatus.UNAVAILABLE
        )
        assertTrue(onlyDownloadable.hasAnySupportedModel)
        assertFalse(onlyDownloadable.hasAnyAvailableModel)

        val onlyDownloading = PaiosModelHelper.ComboStatuses(
            stableFullStatus = FeatureStatus.UNAVAILABLE,
            stableFastStatus = FeatureStatus.UNAVAILABLE,
            previewFullStatus = FeatureStatus.UNAVAILABLE,
            previewFastStatus = FeatureStatus.DOWNLOADING
        )
        assertTrue(onlyDownloading.hasAnySupportedModel)
        assertFalse(onlyDownloading.hasAnyAvailableModel)

        val oneAvailable = PaiosModelHelper.ComboStatuses(
            stableFullStatus = FeatureStatus.UNAVAILABLE,
            stableFastStatus = FeatureStatus.AVAILABLE,
            previewFullStatus = FeatureStatus.DOWNLOADABLE,
            previewFastStatus = FeatureStatus.UNAVAILABLE
        )
        assertTrue(oneAvailable.hasAnySupportedModel)
        assertTrue(oneAvailable.hasAnyAvailableModel)
    }
}
