import 'package:dartapi_core/dartapi_core.dart';

void main() async {
  final app = DartAPI(appName: 'minimal');

  app.addControllers([
    InlineController([
      ApiRoute(
        method: ApiMethod.get,
        path: '/hello',
        summary: 'Hello world',
        typedHandler: (req, _) async => {
          'message': 'Hello from dartapi_core!',
          'docs': 'http://localhost:8080/docs',
        },
      ),
    ]),
  ]);

  app.enableDocs(title: 'Minimal API', version: '1.0.0');
  app.enableHealthCheck();

  await app.start(port: 8080);
}
