package com.example.signboard_reader_app

import android.util.Log
import com.googlecode.tesseract.android.TessBaseAPI
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val kannadaOcrChannel = "sighttosound/kannada_ocr"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, kannadaOcrChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "recognize") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                val imagePath = call.argument<String>("imagePath")
                if (imagePath.isNullOrBlank()) {
                    result.error("INVALID_IMAGE_PATH", "An image path is required.", null)
                    return@setMethodCallHandler
                }

                Thread {
                    try {
                        val text = recognizeKannadaAndEnglish(imagePath)
                        runOnUiThread { result.success(text) }
                    } catch (error: Exception) {
                        Log.e("SightToSoundOCR", "Kannada OCR failed", error)
                        runOnUiThread {
                            result.error(
                                "KANNADA_OCR_FAILED",
                                error.message ?: "Kannada OCR could not initialize.",
                                null
                            )
                        }
                    }
                }.start()
            }
    }

    private fun recognizeKannadaAndEnglish(imagePath: String): String {
        val dataRoot = File(filesDir, "sighttosound_tesseract")
        val tessdataDir = File(dataRoot, "tessdata")
        if (!tessdataDir.exists() && !tessdataDir.mkdirs()) {
            throw IllegalStateException("Could not create the local OCR model directory.")
        }

        // Copy bundled models into app-private storage once; subsequent scans reuse them.
        listOf("kan.traineddata", "eng.traineddata").forEach { modelName ->
            val destination = File(tessdataDir, modelName)
            if (!destination.exists() || destination.length() < 100_000L) {
                val assetPath = "flutter_assets/assets/tessdata/$modelName"
                assets.open(assetPath).use { input ->
                    FileOutputStream(destination).use { output -> input.copyTo(output) }
                }
            }
            if (!destination.exists() || destination.length() < 100_000L) {
                throw IllegalStateException(
                    "OCR model $modelName is missing. Run scripts/setup_kannada_ocr.ps1 and rebuild."
                )
            }
        }

        val imageFile = File(imagePath)
        if (!imageFile.exists()) {
            throw IllegalArgumentException("The temporary OCR image no longer exists.")
        }

        val api = TessBaseAPI()
        try {
            val initialized = api.init(
                dataRoot.absolutePath + File.separator,
                "kan+eng",
                TessBaseAPI.OEM_LSTM_ONLY
            )
            if (!initialized) {
                throw IllegalStateException(
                    "Tesseract could not load Kannada models. Run scripts/setup_kannada_ocr.ps1 and rebuild."
                )
            }
            api.setPageSegMode(TessBaseAPI.PageSegMode.PSM_SINGLE_BLOCK)
            api.setVariable("preserve_interword_spaces", "1")
            api.setImage(imageFile)
            return api.getUTF8Text().orEmpty().trim()
        } finally {
            api.recycle()
        }
    }
}
