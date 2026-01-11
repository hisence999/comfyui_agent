package com.comfyui.mobile.comfy_mobile

import android.content.ContentUris
import android.content.Context
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.app.RecoverableSecurityException
import android.app.Activity
import android.content.IntentSender
import io.flutter.plugin.common.MethodChannel

class MediaStoreHelper(private val context: Context) {

    /**
     * Delete image from MediaStore by filename
     * Uses direct SQL query instead of iterating through all images
     * Performance: O(1) query vs O(n) iteration
     */
    fun deleteImageByFilename(filename: String, result: MethodChannel.Result) {
        try {
            val contentResolver = context.contentResolver
            val uri = MediaStore.Images.Media.EXTERNAL_CONTENT_URI

            // Query for the image with matching filename
            val projection = arrayOf(MediaStore.Images.Media._ID)
            val selection = "${MediaStore.Images.Media.DISPLAY_NAME} = ? OR ${MediaStore.Images.Media.DISPLAY_NAME} LIKE ?"
            val selectionArgs = arrayOf(filename, "%$filename")

            val cursor = contentResolver.query(uri, projection, selection, selectionArgs, null)

            cursor?.use {
                if (it.moveToFirst()) {
                    val idColumn = it.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
                    val id = it.getLong(idColumn)
                    val deleteUri = ContentUris.withAppendedId(uri, id)

                    try {
                        val rowsDeleted = contentResolver.delete(deleteUri, null, null)
                        result.success(rowsDeleted > 0)
                    } catch (e: SecurityException) {
                        // Handle Android 10+ scoped storage
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            val recoverableSecurityException = e as? RecoverableSecurityException
                            if (recoverableSecurityException != null) {
                                // For Android 11+, we need user confirmation
                                // Return false and let Flutter handle the fallback
                                result.success(false)
                            } else {
                                result.error("SECURITY_ERROR", e.message, null)
                            }
                        } else {
                            result.error("DELETE_ERROR", e.message, null)
                        }
                    }
                } else {
                    // Image not found in MediaStore, consider it already deleted
                    result.success(true)
                }
            } ?: run {
                result.success(true) // Cursor is null, image not found
            }
        } catch (e: Exception) {
            result.error("QUERY_ERROR", e.message, null)
        }
    }

    /**
     * Delete image from MediaStore by full path
     * Extracts filename from path and uses the optimized query
     */
    fun deleteImageByPath(path: String, result: MethodChannel.Result) {
        val filename = path.substringAfterLast("/")
        deleteImageByFilename(filename, result)
    }

    /**
     * Check if image exists in MediaStore
     */
    fun imageExistsInMediaStore(filename: String): Boolean {
        val contentResolver = context.contentResolver
        val uri = MediaStore.Images.Media.EXTERNAL_CONTENT_URI

        val projection = arrayOf(MediaStore.Images.Media._ID)
        val selection = "${MediaStore.Images.Media.DISPLAY_NAME} = ?"
        val selectionArgs = arrayOf(filename)

        val cursor = contentResolver.query(uri, projection, selection, selectionArgs, null)
        return cursor?.use { it.count > 0 } ?: false
    }
}
