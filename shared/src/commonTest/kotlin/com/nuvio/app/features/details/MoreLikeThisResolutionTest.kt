package com.nuvio.app.features.details

import com.nuvio.app.features.home.MetaPreview
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class MoreLikeThisResolutionTest {

    private fun preview(id: String) = MetaPreview(id = id, type = "movie", name = id)

    private fun meta(
        list: List<MetaPreview> = emptyList(),
        source: MoreLikeThisSource? = null,
    ) = MetaDetails(
        id = "tt1",
        type = "movie",
        name = "One",
        moreLikeThis = list,
        moreLikeThisSource = source,
    )

    @Test
    fun `no meta gives an empty list and never applies the source chain`() = runTest {
        var applied = false
        val result = resolveMoreLikeThis(null) { applied = true; it }
        assertTrue(result.isEmpty())
        assertEquals(false, applied)
    }

    @Test
    fun `a meta with a resolved source keeps its list without re-applying`() = runTest {
        var applied = false
        val m = meta(listOf(preview("a"), preview("b")), MoreLikeThisSource.TRAKT)
        val result = resolveMoreLikeThis(m) { applied = true; it }
        assertEquals(listOf("a", "b"), result.map { it.id })
        assertEquals(false, applied)
    }

    @Test
    fun `a meta without a source runs the Detail source chain and returns its list`() = runTest {
        val m = meta(listOf(preview("raw")), null)
        val result = resolveMoreLikeThis(m) {
            it.copy(moreLikeThis = listOf(preview("simkl-1")), moreLikeThisSource = MoreLikeThisSource.SIMKL)
        }
        assertEquals(listOf("simkl-1"), result.map { it.id })
    }

    @Test
    fun `a source chain that turns the source off yields an empty list`() = runTest {
        val m = meta(listOf(preview("raw")), null)
        val result = resolveMoreLikeThis(m) { it.copy(moreLikeThis = emptyList(), moreLikeThisSource = null) }
        assertTrue(result.isEmpty())
    }

    private val dropX: (MetaDetails) -> MetaDetails =
        { m -> m.copy(moreLikeThis = m.moreLikeThis.filter { it.id != "x" }) }

    @Test
    fun `a fetched meta goes through the filter before its list is used`() = runTest {
        val fetched = meta(listOf(preview("a"), preview("x")), MoreLikeThisSource.TRAKT)
        val result = resolveFilteredMoreLikeThis(
            peeked = null, fetch = { fetched }, filter = dropX, apply = { it },
        )
        assertEquals(listOf("a"), result.map { it.id })
    }

    @Test
    fun `a peeked meta is used as is and never fetched`() = runTest {
        var fetchCalled = false
        val peeked = meta(listOf(preview("a")), MoreLikeThisSource.TRAKT)
        val result = resolveFilteredMoreLikeThis(
            peeked = peeked, fetch = { fetchCalled = true; null }, filter = dropX, apply = { it },
        )
        assertEquals(listOf("a"), result.map { it.id })
        assertEquals(false, fetchCalled)
    }

    @Test
    fun `the source chain result goes through the filter`() = runTest {
        val m = meta(listOf(preview("raw")), null)
        val result = resolveFilteredMoreLikeThis(
            peeked = m, fetch = { null }, filter = dropX,
            apply = { it.copy(moreLikeThis = listOf(preview("x"), preview("simkl")), moreLikeThisSource = MoreLikeThisSource.SIMKL) },
        )
        assertEquals(listOf("simkl"), result.map { it.id })
    }
}
