package com.payriff.flutter

import android.content.Context
import android.view.View
import com.google.android.gms.wallet.button.ButtonOptions
import com.google.android.gms.wallet.button.PayButton
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * The platform view `payriff/google_pay_button` (CONTRACT §17.10): Google's own [PayButton],
 * initialised with [ButtonOptions] from the creation parameters: `type`, `theme` (Dart resolves
 * `automatic` from the page), `cornerRadius` in logical pixels (converted to device pixels here)
 * and `allowedPaymentMethods`, the `buttonAllowedPaymentMethods` JSON. No key or client secret is
 * among them. A tap goes to Dart as `tap` on the view's channel `payriff/google_pay_button/<id>`.
 */
internal class GooglePayButtonFactory(private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        GooglePayButtonView(context, viewId, args as? Map<*, *>, messenger)

    companion object {
        const val VIEW_TYPE = "payriff/google_pay_button"
    }
}

internal class GooglePayButtonView(
    context: Context,
    viewId: Int,
    args: Map<*, *>?,
    messenger: BinaryMessenger,
) : PlatformView {
    private val channel = MethodChannel(messenger, "${GooglePayButtonFactory.VIEW_TYPE}/$viewId")
    private val button = PayButton(context)

    init {
        val density = context.resources.displayMetrics.density
        try {
            button.initialize(
                ButtonOptions.newBuilder()
                    .setButtonType(GooglePayValues.buttonType(args?.get("type") as? String))
                    .setButtonTheme(GooglePayValues.buttonTheme(args?.get("theme") as? String))
                    .setCornerRadius(
                        GooglePayValues.cornerRadiusPx(
                            (args?.get("cornerRadius") as? Number)?.toDouble(),
                            density,
                        ),
                    )
                    .setAllowedPaymentMethods(args?.get("allowedPaymentMethods") as? String ?: "[]")
                    .build(),
            )
        } catch (e: Exception) {
            // Options the button refuses leave it empty; the Dart side still owns the tap.
        }
        button.setOnClickListener { channel.invokeMethod("tap", null) }
    }

    override fun getView(): View = button

    override fun dispose() {}
}
