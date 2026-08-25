package com.k9i.ccpocket

import android.content.ComponentName
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

private const val APP_ICON_CHANNEL = "ccpocket/app_icon"
private const val INSTALLER_CHANNEL = "ccpocket/android_installer"

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            APP_ICON_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "supportsAlternateIcons" -> result.success(true)
                "getCurrentIcon" -> result.success(getCurrentIcon())
                "setIcon" -> {
                    val icon = call.argument<String>("icon")
                    try {
                        setLauncherIcon(icon)
                        result.success(null)
                    } catch (error: IllegalArgumentException) {
                        result.error("invalid_icon", error.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            INSTALLER_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath.isNullOrEmpty()) {
                        result.error("invalid_path", "File path cannot be empty", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val file = java.io.File(filePath)
                        if (!file.exists()) {
                            result.error("file_not_found", "APK file does not exist at $filePath", null)
                            return@setMethodCallHandler
                        }
                        val uri = androidx.core.content.FileProvider.getUriForFile(
                            context,
                            "${context.packageName}.fileprovider",
                            file,
                        )
                        val intent = android.content.Intent(android.content.Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/vnd.android.package-archive")
                            flags = android.content.Intent.FLAG_ACTIVITY_NEW_TASK or
                                    android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION
                        }
                        context.startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("install_failed", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun getCurrentIcon(): String? {
        val aliases = mapOf(
            "$packageName.MainActivitySupporterLightOutline" to "light_outline",
            "$packageName.MainActivitySupporterProCopperEmerald" to "pro_copper_emerald",
        )

        for ((alias, iconId) in aliases) {
            val state = packageManager.getComponentEnabledSetting(
                ComponentName(packageName, alias),
            )
            if (state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED) {
                return iconId
            }
        }
        return null
    }

    private fun setLauncherIcon(icon: String?) {
        val targetAlias = when (icon) {
            null, "default" -> "$packageName.MainActivityDefault"
            "light_outline" -> "$packageName.MainActivitySupporterLightOutline"
            "pro_copper_emerald" -> "$packageName.MainActivitySupporterProCopperEmerald"
            else -> throw IllegalArgumentException("Unknown app icon: $icon")
        }
        val aliases = listOf(
            "$packageName.MainActivityDefault",
            "$packageName.MainActivitySupporterLightOutline",
            "$packageName.MainActivitySupporterProCopperEmerald",
        )

        for (alias in aliases) {
            packageManager.setComponentEnabledSetting(
                ComponentName(packageName, alias),
                if (alias == targetAlias) {
                    PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                } else {
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED
                },
                PackageManager.DONT_KILL_APP,
            )
        }
    }
}
