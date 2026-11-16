package page.puzzak.geminilocal

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class InternalToolsHelperTest {

    private fun loadBundledGenAiDocs(): String {
        val candidates = listOf(
            File("../../assets/docs/genai.md.txt"),
            File("../assets/docs/genai.md.txt"),
            File("assets/docs/genai.md.txt"),
        )
        val found = candidates.firstOrNull { it.exists() && it.isFile }
        if (found != null) {
            return found.readText(Charsets.UTF_8)
        }
        return """
            # Supported Hardware & Device Eligibility Matrix

            ## Qualified Device Families & Hardware Accelerators
            Google Pixel 9 and Samsung Galaxy S24 support Gemini Nano via Android AICore.

            ## Error Taxonomy & Troubleshooting Codes
            -101 MODEL_BUSY, -100 CONTEXT_OVERFLOW, -102 BACKGROUND_USE_BLOCKED.

            ## PAIOS Overview, Identity & Privacy (Who Are You / About PAIOS)
            PAIOS (Personal AI Operating System) is a 100% offline-by-default, private on-device AI assistant created by Puzzak and powered by Google Gemini Nano.

            ## PAIOS Extensions & M3x Mesh Ecosystem
            Includes paios.docs, paios.device, paios.wikipedia, paios.search, and paios.weather (weather_forecast).
        """.trimIndent()
    }

    @Test
    fun toolSpecs_includeQueryAicoreDocumentationWithSearchesOfficialPrefixAndPaios() {
        val docsModule = InternalToolsHelper.moduleById(InternalToolsHelper.MODULE_DOCS)
        assertNotNull(docsModule)
        assertTrue(docsModule!!.defaultEnabled)
        assertFalse(docsModule.requiresInternet)

        val docsTool = docsModule.tools.firstOrNull { it.name == "query_aicore_documentation" }
        assertNotNull(docsTool)
        assertTrue(docsTool!!.description.startsWith("Searches official "))
        assertTrue(docsTool.description.contains("PAIOS"))
        assertTrue(docsTool.description.contains("who are you?"))
        assertTrue(docsTool.description.contains("tell me about yourself"))
    }

    @Test
    fun docsToolAliases_routeToQueryAicoreDocumentationAndDocsModule() {
        val docsModule = InternalToolsHelper.moduleById(InternalToolsHelper.MODULE_DOCS)
        assertNotNull(docsModule)

        val aliases = listOf(
            "query_aicore_documentation",
            "about_paios",
            "paios_info",
            "get_paios_info",
            "  ABOUT_PAIOS  ",
            "Get_Paios_Info",
        )
        for (alias in aliases) {
            assertEquals("query_aicore_documentation", InternalToolsHelper.canonicalToolName(alias))
            assertTrue(InternalToolsHelper.isInternalTool(alias))
            assertEquals(docsModule, InternalToolsHelper.moduleForTool(alias))
        }
        assertTrue(
            InternalToolsHelper.DOCS_TOOL_ALIASES.containsAll(
                listOf("query_aicore_documentation", "about_paios", "paios_info", "get_paios_info")
            )
        )
    }

    @Test
    fun normalizeDocumentationQuery_and_normalizeToolArgs_mapAllAliasKeysToQuery() {
        assertEquals(
            "token limits",
            InternalToolsHelper.normalizeDocumentationQuery(mapOf("topic" to "token limits"))
        )
        assertEquals(
            "-101",
            InternalToolsHelper.normalizeDocumentationQuery(mapOf("q" to "-101"))
        )
        assertEquals(
            "Pixel 9",
            InternalToolsHelper.normalizeDocumentationQuery(mapOf("question" to "Pixel 9"))
        )
        assertEquals(
            "inspect_screen",
            InternalToolsHelper.normalizeDocumentationQuery(mapOf("search" to "inspect_screen"))
        )
        assertEquals(
            "Gemini Nano v4",
            InternalToolsHelper.normalizeDocumentationQuery(mapOf("subject" to "Gemini Nano v4"))
        )

        // Self-identity questions normalize to "PAIOS overview features"
        assertEquals(
            "PAIOS overview features",
            InternalToolsHelper.normalizeDocumentationQuery(mapOf("query" to "Who are you?"))
        )
        assertEquals(
            "PAIOS overview features",
            InternalToolsHelper.normalizeDocumentationQuery(mapOf("question" to "Tell me about yourself!"))
        )
        assertEquals(
            "PAIOS overview features",
            InternalToolsHelper.normalizeDocumentationQuery(emptyMap())
        )

        // Verify normalizeToolArgs maps topic, q, question, search, subject -> query across aliases
        for (key in listOf("topic", "q", "question", "search", "subject")) {
            val normalized = InternalToolsHelper.normalizeToolArgs(
                "about_paios",
                mapOf(key to "PAIOS extensions")
            )
            assertEquals("PAIOS extensions", normalized["query"])
        }
    }

    @Test
    fun rankDocumentationSections_ranksPaiosSelfKnowledgeAndTechnicalSectionsCleanly() {
        val docText = loadBundledGenAiDocs()
        assertTrue(docText.isNotBlank())

        val whoMatch = InternalToolsHelper.rankDocumentationSections(docText, "Who are you?")
        assertTrue(whoMatch.found)
        assertEquals("PAIOS overview features", whoMatch.query)
        assertTrue(whoMatch.sectionTitle.contains("PAIOS Overview"))
        assertTrue(whoMatch.content.contains("PAIOS"))
        assertTrue(whoMatch.content.contains("Puzzak"))
        assertTrue(whoMatch.content.contains("Gemini Nano"))

        val aboutMatch = InternalToolsHelper.rankDocumentationSections(docText, "tell me about yourself")
        assertTrue(aboutMatch.found)
        assertTrue(aboutMatch.sectionTitle.contains("PAIOS Overview"))
        assertTrue(aboutMatch.content.contains("offline"))

        val extMatch = InternalToolsHelper.rankDocumentationSections(docText, "PAIOS extensions weather_forecast")
        assertTrue(extMatch.found)
        assertTrue(extMatch.content.contains("paios.wikipedia"))
        assertTrue(extMatch.content.contains("weather_forecast"))

        val errorMatch = InternalToolsHelper.rankDocumentationSections(docText, "-101 MODEL_BUSY")
        assertTrue(errorMatch.found)
        assertTrue(errorMatch.content.contains("-101"))
        assertTrue(errorMatch.content.contains("MODEL_BUSY"))
    }
}
