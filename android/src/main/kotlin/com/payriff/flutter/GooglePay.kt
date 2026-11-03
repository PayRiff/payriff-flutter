package com.payriff.flutter

import android.app.Activity
import android.content.Context
import android.content.Intent
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.common.api.CommonStatusCodes
import com.google.android.gms.common.api.ResolvableApiException
import com.google.android.gms.wallet.AutoResolveHelper
import com.google.android.gms.wallet.IsReadyToPayRequest
import com.google.android.gms.wallet.PaymentData
import com.google.android.gms.wallet.PaymentDataRequest
import com.google.android.gms.wallet.PaymentsClient
import com.google.android.gms.wallet.Wallet
import com.google.android.gms.wallet.WalletConstants
import com.google.android.gms.wallet.button.ButtonConstants
import io.flutter.plugin.common.MethodChannel
import org.json.JSONException
import org.json.JSONObject

/**
 * Google Pay (CONTRACT §17.5) behind the plugin's channel. Dart builds the request JSON
 * (`wallet.json` → `googlePayRequests`); this side only runs the Google Pay API:
 *
 * - `googlePayIsReady` {environment, request} -> bool: `PaymentsClient.isReadyToPay`; an error
 *   counts as false.
 * - `googlePayLoad` {environment, request} -> {status: ok, token} | {status: cancelled} |
 *   {status: error, code}: `PaymentsClient.loadPaymentData`. A `FlutterActivity` has no
 *   `ActivityResultRegistry`, so the sheet is resolved through the activity and its result comes
 *   back in [onActivityResult] (`AutoResolveHelper.RESULT_ERROR` and `getStatusFromIntent` for
 *   errors). This works with every play-services-wallet version, also those without
 *   `AutoResolveHelper.resolveTask`.
 *
 * Only `paymentMethodData.tokenizationData.token` leaves this class; the rest of `PaymentData`
 * (card details, contact data) is dropped. Nothing here logs.
 */
internal class GooglePay {
    /** The reply of the running `googlePayLoad`: one Google Pay sheet at a time. */
    private var pending: MethodChannel.Result? = null

    fun isReady(
        activity: Activity?,
        context: Context?,
        environment: String?,
        request: String?,
        result: MethodChannel.Result,
    ) {
        val readyRequest =
            try {
                request?.let { IsReadyToPayRequest.fromJson(it) }
            } catch (e: Exception) {
                null
            }
        val client =
            try {
                paymentsClient(activity, context, environment)
            } catch (e: Exception) {
                null
            }
        if (readyRequest == null || client == null) {
            result.success(false)
            return
        }
        client.isReadyToPay(readyRequest).addOnCompleteListener { task ->
            val ready =
                try {
                    task.isSuccessful && task.result == true
                } catch (e: Exception) {
                    false
                }
            result.success(ready)
        }
    }

    fun load(
        activity: Activity?,
        environment: String?,
        request: String?,
        result: MethodChannel.Result,
    ) {
        if (pending != null) {
            result.success(GooglePayValues.error(CommonStatusCodes.INTERNAL_ERROR))
            return
        }
        val dataRequest =
            try {
                request?.let { PaymentDataRequest.fromJson(it) }
            } catch (e: Exception) {
                null
            }
        if (activity == null || dataRequest == null) {
            result.success(GooglePayValues.error(CommonStatusCodes.DEVELOPER_ERROR))
            return
        }
        pending = result
        try {
            paymentsClient(activity, null, environment)!!
                .loadPaymentData(dataRequest)
                .addOnCompleteListener { task ->
                    if (task.isSuccessful) {
                        deliver(GooglePayValues.ok(tokenOf(task.result)))
                        return@addOnCompleteListener
                    }
                    when (val exception = task.exception) {
                        // The Google Pay sheet: its result arrives in onActivityResult.
                        is ResolvableApiException ->
                            try {
                                exception.startResolutionForResult(activity, REQUEST_CODE)
                            } catch (e: Exception) {
                                deliver(GooglePayValues.error(CommonStatusCodes.INTERNAL_ERROR))
                            }
                        is ApiException -> deliver(GooglePayValues.error(exception.statusCode))
                        else -> deliver(GooglePayValues.error(CommonStatusCodes.INTERNAL_ERROR))
                    }
                }
        } catch (e: Exception) {
            deliver(GooglePayValues.error(CommonStatusCodes.INTERNAL_ERROR))
        }
    }

    /** The Google Pay sheet's result; false for other requests. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val token =
            if (resultCode == Activity.RESULT_OK && data != null) {
                tokenOf(PaymentData.getFromIntent(data))
            } else {
                null
            }
        val statusCode =
            if (resultCode == AutoResolveHelper.RESULT_ERROR) {
                AutoResolveHelper.getStatusFromIntent(data)?.statusCode
            } else {
                null
            }
        deliver(GooglePayValues.resultFor(resultCode, token, statusCode))
        return true
    }

    /** The activity is gone for good: a sheet that is still open cannot report any more. */
    fun cancel() {
        deliver(GooglePayValues.cancelled())
    }

    private fun deliver(value: Map<String, Any?>) {
        val result = pending ?: return
        pending = null
        result.success(value)
    }

    private fun paymentsClient(
        activity: Activity?,
        context: Context?,
        environment: String?,
    ): PaymentsClient? {
        val options =
            Wallet.WalletOptions.Builder()
                .setEnvironment(GooglePayValues.environment(environment))
                .build()
        return when {
            activity != null -> Wallet.getPaymentsClient(activity, options)
            context != null -> Wallet.getPaymentsClient(context, options)
            else -> null
        }
    }

    /** `paymentMethodData.tokenizationData.token`, exactly as Google Pay returned it. */
    private fun tokenOf(paymentData: PaymentData?): String? {
        val json = paymentData?.toJson() ?: return null
        return try {
            JSONObject(json)
                .optJSONObject("paymentMethodData")
                ?.optJSONObject("tokenizationData")
                ?.opt("token") as? String
        } catch (e: JSONException) {
            null
        }
    }

    companion object {
        /** The request code of the Google Pay sheet; below 0x10000 for `FragmentActivity`. */
        const val REQUEST_CODE = 0x5052
    }
}

/** The pure mappings of the Google Pay side, for the plugin and its unit tests. */
internal object GooglePayValues {
    /** `TEST` or `PRODUCTION` (CONTRACT §17.4, from Dart) as a `WalletConstants` environment. */
    fun environment(name: String?): Int =
        if (name == "TEST") WalletConstants.ENVIRONMENT_TEST else WalletConstants.ENVIRONMENT_PRODUCTION

    /** A `ButtonConstants.ButtonType` name (`wallet.json` → `buttonStyles`); `PLAIN` otherwise. */
    fun buttonType(name: String?): Int =
        when (name) {
            "BUY" -> ButtonConstants.ButtonType.BUY
            "PAY" -> ButtonConstants.ButtonType.PAY
            "CHECKOUT" -> ButtonConstants.ButtonType.CHECKOUT
            "BOOK" -> ButtonConstants.ButtonType.BOOK
            "DONATE" -> ButtonConstants.ButtonType.DONATE
            "ORDER" -> ButtonConstants.ButtonType.ORDER
            "SUBSCRIBE" -> ButtonConstants.ButtonType.SUBSCRIBE
            else -> ButtonConstants.ButtonType.PLAIN
        }

    /** A `ButtonConstants.ButtonTheme` name; `DARK` otherwise. Dart resolves `automatic`. */
    fun buttonTheme(name: String?): Int =
        if (name == "LIGHT") ButtonConstants.ButtonTheme.LIGHT else ButtonConstants.ButtonTheme.DARK

    /** A corner radius in logical pixels as device pixels; a negative radius counts as 0. */
    fun cornerRadiusPx(dp: Double?, density: Float): Int {
        val radius = dp ?: 16.0
        if (radius.isNaN() || radius <= 0) return 0
        return Math.round(radius * density).toInt()
    }

    /** The reply of the Google Pay sheet's activity result. */
    fun resultFor(resultCode: Int, token: String?, statusCode: Int?): Map<String, Any?> =
        when (resultCode) {
            Activity.RESULT_OK -> ok(token)
            Activity.RESULT_CANCELED -> cancelled()
            AutoResolveHelper.RESULT_ERROR -> error(statusCode ?: CommonStatusCodes.INTERNAL_ERROR)
            else -> error(CommonStatusCodes.INTERNAL_ERROR)
        }

    fun ok(token: String?): Map<String, Any?> = mapOf("status" to "ok", "token" to token)

    fun cancelled(): Map<String, Any?> = mapOf("status" to "cancelled")

    fun error(code: Int): Map<String, Any?> = mapOf("status" to "error", "code" to code)
}
