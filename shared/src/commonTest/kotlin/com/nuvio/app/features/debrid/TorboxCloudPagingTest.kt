package com.nuvio.app.features.debrid

import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull

/**
 * Upstream be81802c8 (#2215) ported into `shared/`. [fetchTorboxCloudPages] is `internal` to this
 * module, so composeApp's `TorboxCloudLibraryProviderApiTest` cannot reach it; the pager is
 * covered here with a fake page fetcher.
 */
class TorboxCloudPagingTest {
    private fun item(n: Int) = TorboxCloudItemDto(id = JsonPrimitive(n), name = "item-$n")

    private fun page(items: List<TorboxCloudItemDto>, status: Int = 200, success: Boolean? = true) =
        DebridApiResponse(
            status = status,
            body = TorboxEnvelopeDto(success = success, data = items),
            rawBody = "{\"data\":[${items.size} items]}",
        )

    private fun truncated() =
        DebridApiResponse<TorboxEnvelopeDto<List<TorboxCloudItemDto>>>(
            status = 200,
            body = null,
            rawBody = "{\"success\":true,\"data\":[{\"id\":1\n...[truncated]",
        )

    @Test
    fun `merges three pages at offsets 0 100 200 and strips the raw body`() = runBlocking {
        val all = (1..237).map(::item)
        val requests = mutableListOf<Pair<Int, Int>>()

        val response = fetchTorboxCloudPages { offset, limit ->
            requests += offset to limit
            page(all.drop(offset).take(limit))
        }

        assertEquals(listOf(0 to 100, 100 to 100, 200 to 100), requests)
        assertEquals(237, response.body?.data?.size)
        assertEquals(all, response.body?.data)
        assertEquals("", response.rawBody)
        assertEquals(200, response.status)
    }

    @Test
    fun `a short first page ends after one request`() = runBlocking {
        val all = (1..37).map(::item)
        var calls = 0

        val response = fetchTorboxCloudPages { offset, limit ->
            calls += 1
            page(all.drop(offset).take(limit))
        }

        assertEquals(1, calls)
        assertEquals(all, response.body?.data)
    }

    @Test
    fun `an exact multiple of the page size requests one extra empty page`() = runBlocking {
        val all = (1..200).map(::item)
        val requests = mutableListOf<Int>()

        val response = fetchTorboxCloudPages { offset, limit ->
            requests += offset
            page(all.drop(offset).take(limit))
        }

        assertEquals(listOf(0, 100, 200), requests)
        assertEquals(all, response.body?.data)
    }

    @Test
    fun `a truncated body halves the limit and retries the same offset`() = runBlocking {
        val all = (1..120).map(::item)
        val requests = mutableListOf<Pair<Int, Int>>()

        val response = fetchTorboxCloudPages { offset, limit ->
            requests += offset to limit
            if (limit > 50) truncated() else page(all.drop(offset).take(limit))
        }

        assertEquals(listOf(0 to 100, 0 to 50, 50 to 50, 100 to 50), requests)
        assertEquals(all, response.body?.data)
        assertEquals("", response.rawBody)
    }

    @Test
    fun `an api failure envelope is returned as is without a retry`() = runBlocking {
        var calls = 0
        val failed = DebridApiResponse(
            status = 200,
            body = TorboxEnvelopeDto<List<TorboxCloudItemDto>>(success = false, error = "BAD_TOKEN"),
            rawBody = "{\"success\":false,\"error\":\"BAD_TOKEN\"}",
        )

        val response = fetchTorboxCloudPages { _, _ ->
            calls += 1
            failed
        }

        assertEquals(1, calls)
        assertEquals(failed, response)
        assertEquals(false, response.body?.success)
        assertEquals("BAD_TOKEN", response.body?.error)
    }

    @Test
    fun `a non-2xx status is returned as is without a retry`() = runBlocking {
        var calls = 0
        val unauthorized = DebridApiResponse<TorboxEnvelopeDto<List<TorboxCloudItemDto>>>(
            status = 401,
            body = null,
            rawBody = "{\"detail\":\"unauthorized\"}",
        )

        val response = fetchTorboxCloudPages { _, _ ->
            calls += 1
            unauthorized
        }

        assertEquals(1, calls)
        assertEquals(unauthorized, response)
        assertFalse(response.isSuccessful)
        assertNull(response.body)
    }

    @Test
    fun `a later page failure returns that failure rather than the partial merge`() = runBlocking {
        val all = (1..150).map(::item)
        var calls = 0

        val response = fetchTorboxCloudPages { offset, limit ->
            calls += 1
            if (offset == 0) page(all.take(limit)) else page(emptyList(), status = 500, success = null)
        }

        assertEquals(2, calls)
        assertEquals(500, response.status)
        assertNotNull(response.body)
        assertEquals(emptyList(), response.body?.data)
    }
}
