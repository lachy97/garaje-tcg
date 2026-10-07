// Reemplaza el test de ejemplo de `flutter create` (buscaba una clase MyApp
// que no existe en este proyecto). Comprueba que el tema y los componentes
// de marca se construyen sin errores.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garaje_tcg/app/theme.dart';
import 'package:garaje_tcg/app/widgets/brand.dart';

void main() {
  testWidgets('El tema oscuro y el título de marca se pintan', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: Column(
            children: [
              BrandTitle(),
              NeonCard(glow: true, child: Text('Mesa 1')),
            ],
          ),
        ),
      ),
    );

    expect(find.text('GARAJE TCG'), findsOneWidget);
    expect(find.text('Mesa 1'), findsOneWidget);

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, isNull); // usa el del tema
    expect(AppTheme.dark.scaffoldBackgroundColor, AppColors.background);
  });
}
