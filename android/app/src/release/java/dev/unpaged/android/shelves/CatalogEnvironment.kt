package dev.unpaged.android.shelves

import android.content.Context

object CatalogEnvironment {
    fun featuredIDs(@Suppress("UNUSED_PARAMETER") context: Context, books: List<CatalogBook>): List<String> = featuredCatalogIDs(books)

    fun savedOnly(@Suppress("UNUSED_PARAMETER") context: Context) = false
    fun heroDay(@Suppress("UNUSED_PARAMETER") context: Context, day: Int) = day
}
