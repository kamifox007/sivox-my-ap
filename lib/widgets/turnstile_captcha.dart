import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// An invisible Cloudflare Turnstile CAPTCHA widget that executes in the background.
class TurnstileCaptcha extends StatefulWidget {
  final Function(String token) onVerified;
  final String siteKey;

  const TurnstileCaptcha({
    super.key,
    required this.onVerified,
    // By default, use Cloudflare's official testing sitekey that always passes
    this.siteKey = '1x00000000000000000000AA',
  });

  @override
  State<TurnstileCaptcha> createState() => _TurnstileCaptchaState();
}

class _TurnstileCaptchaState extends State<TurnstileCaptcha> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();

    final htmlContent = '''
      <!DOCTYPE html>
      <html>
      <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <script src="https://challenges.cloudflare.com/turnstile/v0/api.js" async defer></script>
        <style>
          body { background: transparent; margin: 0; padding: 0; }
        </style>
      </head>
      <body>
        <div class="cf-turnstile" 
             data-sitekey="${widget.siteKey}" 
             data-size="invisible" 
             data-callback="onSuccess"
             data-error-callback="onError"></div>

        <script>
          function onSuccess(token) {
            if (window.CaptchaChannel) {
              window.CaptchaChannel.postMessage(token);
            }
          }
          function onError(error) {
            if (window.CaptchaChannel) {
              window.CaptchaChannel.postMessage("error:" + error);
            }
          }
        </script>
      </body>
      </html>
    ''';

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel(
        'CaptchaChannel',
        onMessageReceived: (JavaScriptMessage message) {
          final text = message.message;
          if (text.startsWith('error:')) {
            debugPrint('Cloudflare Turnstile Error: ${text.substring(6)}');
          } else {
            widget.onVerified(text);
          }
        },
      )
      ..loadHtmlString(htmlContent);
  }

  @override
  Widget build(BuildContext context) {
    // Render offstage so the WebView is in the tree and runs JS, but is completely invisible.
    return Offstage(
      offstage: true,
      child: SizedBox(
        width: 1,
        height: 1,
        child: WebViewWidget(controller: _controller),
      ),
    );
  }
}
