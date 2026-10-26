package com.opennest.app

import android.content.Context
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileWriter

/**
 * 内嵌引擎的原生桥。
 *
 * Android 10（API 29）起禁止在应用可写目录执行二进制，唯一可行位置是
 * 系统解压原生库得到的 nativeLibraryDir —— 那里以 `libopenlist.so` 的形式
 * 存放 OpenList 服务端可执行文件（构建时由 tool/fetch_openlist.sh 放入 jniLibs）。
 */
object SidecarBridge {
    private var process: Process? = null
    private var logWriter: FileWriter? = null

    fun handle(context: Context, call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "nativeLibraryDir" -> result.success(context.applicationInfo.nativeLibraryDir)
            "start" -> {
                try {
                    val dataDir = call.argument<String>("dataDir") ?: error("缺少数据目录")
                    val password = call.argument<String>("password") ?: ""
                    val logPath = call.argument<String>("logPath") ?: ""
                    result.success(startEngine(context, dataDir, password, logPath))
                } catch (error: Exception) {
                    result.error("start_failed", error.message ?: "启动失败", null)
                }
            }
            "stop" -> {
                stopEngine()
                result.success(true)
            }
            "isRunning" -> {
                val current = process
                result.success(current != null && isAlive(current))
            }
            else -> result.notImplemented()
        }
    }

    /** Android 的 Process 没有 Java 9 的 pid()，用 exitValue 反推是否存活。 */
    private fun isAlive(target: Process): Boolean = try {
        target.exitValue()
        false
    } catch (error: IllegalThreadStateException) {
        true
    }

    private fun startEngine(context: Context, dataDir: String, password: String, logPath: String): Boolean {
        process?.let { if (isAlive(it)) return true }

        val binary = File(context.applicationInfo.nativeLibraryDir, "libopenlist.so")
        if (!binary.exists()) {
            throw IllegalStateException("未找到内嵌引擎：${binary.absolutePath}")
        }
        // Android 10+ 从 APK 解压出的原生库默认没有可执行位，直接 exec 会
        // 报 "Permission denied"。这里显式补上（系统允许应用对自己的
        // nativeLibraryDir 里的文件改权限）。
        if (!binary.canExecute()) {
            runCatching { binary.setExecutable(true, /* ownerOnly = */ false) }
        }
        if (!binary.canExecute()) {
            throw IllegalStateException("内嵌引擎没有可执行权限：${binary.absolutePath}")
        }

        val config = File(dataDir, "config.json")
        val builder = ProcessBuilder(
            binary.absolutePath,
            "--data", dataDir,
            "--config", config.absolutePath,
            "server"
        )
        builder.directory(File(dataDir))
        builder.environment()["OPENLIST_ADMIN_PASSWORD"] = password
        builder.redirectErrorStream(true)

        val started = builder.start()
        process = started
        attachLog(started, logPath)

        // 引擎若因参数或权限问题秒退，这里返回 true 会让 Dart 侧干等
        // 40 秒健康检查超时才报错。短暂等待一次，把「立刻就挂」的情况
        // 变成明确的失败信息。
        Thread.sleep(600)
        if (!isAlive(started)) {
            val code = runCatching { started.exitValue() }.getOrDefault(-1)
            process = null
            throw IllegalStateException("内嵌引擎启动后立即退出（退出码 $code），请查看日志")
        }
        return true
    }

    private fun attachLog(started: Process, logPath: String) {
        if (logPath.isEmpty()) return
        try {
            val writer = FileWriter(logPath, true)
            logWriter = writer
            Thread {
                runCatching {
                    started.inputStream.bufferedReader().useLines { lines ->
                        lines.forEach { line ->
                            runCatching { writer.appendLine(line) }
                        }
                    }
                }
            }.apply { isDaemon = true }.start()
        } catch (_: Exception) {
            // 日志失败不影响主流程
        }
    }

    private fun stopEngine() {
        val running = process ?: return
        runCatching { running.destroy() }
        runCatching { running.waitFor() }
        runCatching { running.destroyForcibly() }
        runCatching { logWriter?.close() }
        process = null
        logWriter = null
    }
}
