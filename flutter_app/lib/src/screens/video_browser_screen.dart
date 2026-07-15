import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../widgets/glass.dart';

class VideoBrowserScreen extends StatefulWidget {
  const VideoBrowserScreen({super.key});

  @override
  State<VideoBrowserScreen> createState() => _VideoBrowserScreenState();
}

class _VideoBrowserScreenState extends State<VideoBrowserScreen> {
  final address = TextEditingController();
  WebViewController? browser;
  String currentUrl = 'https://www.google.com/';
  bool loading = true;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      browser = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(NavigationDelegate(
          onPageStarted: (url) => updatePage(url, true),
          onPageFinished: (url) => updatePage(url, false),
        ))
        ..loadRequest(Uri.parse(currentUrl));
    }
  }

  void updatePage(String url, bool isLoading) {
    if (!mounted) return;
    setState(() {
      currentUrl = url;
      loading = isLoading;
      address.text = url;
    });
  }

  Future<void> navigate(String value) async {
    final input = value.trim();
    if (input.isEmpty || browser == null) return;
    final parsed = Uri.tryParse(input);
    final uri = parsed != null && parsed.hasScheme
        ? parsed
        : Uri.https('www.google.com', '/search', {'q': input});
    await browser!.loadRequest(uri);
  }

  @override
  void dispose() {
    address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GlowScaffold(
        child: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Row(children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded),
                ),
                Expanded(
                  child: TextField(
                    controller: address,
                    textInputAction: TextInputAction.go,
                    onSubmitted: navigate,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Поиск Google или адрес сайта',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Открыть',
                  onPressed: () => navigate(address.text),
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
              ]),
            ),
            if (loading && !kIsWeb) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: kIsWeb
                  ? const Center(
                      child: Text(
                        'Встроенный браузер доступен в приложении для iPhone.',
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: WebViewWidget(controller: browser!),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(children: [
                const Text(
                  'Открой страницу самого видео. DRM и закрытые плееры не поддерживаются.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Colors.white60),
                ),
                const SizedBox(height: 7),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: kIsWeb
                        ? null
                        : () => Navigator.pop(context, currentUrl),
                    icon: const Icon(Icons.add_link_rounded),
                    label: const Text('Использовать эту ссылку'),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
