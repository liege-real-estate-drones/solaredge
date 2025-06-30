// This is a basic Flutter widget test.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solaredge_monitor/data/services/notification_service.dart';
import 'package:solaredge_monitor/main.dart';
import 'package:mockito/annotations.dart';
import 'package:flutter/foundation.dart'; // Pour ValueNotifier
import 'package:mockito/mockito.dart'; // Pour when, any
import 'package:provider/provider.dart'; // Import Provider
import 'package:solaredge_monitor/data/services/assistant_service.dart'; // Import AssistantService
import 'package:solaredge_monitor/data/services/auth_service.dart'; // Import AuthService
import 'package:solaredge_monitor/data/services/service_manager.dart'; // Import ServiceManager
import 'package:solaredge_monitor/presentation/pages/splash_screen.dart';

import 'package:solaredge_monitor/data/services/solaredge_api_service.dart';
import 'package:solaredge_monitor/data/services/weather_manager.dart';
import 'package:solaredge_monitor/data/services/location_service.dart';

import 'widget_test.mocks.dart';


@GenerateMocks([
  NotificationService,
  AuthService,
  AssistantService,
  ServiceManager,
  // --- Correction: Ajouter les autres services pour le provider ---
  SolarEdgeApiService,
  WeatherManager,
  LocationService,
  SharedPreferences
  // --- Fin Correction ---
])
void main() {
  // Initialiser SharedPreferences pour les tests
  setUpAll(() {
    // Utilise une implémentation en mémoire pour les tests
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('App builds smoke test', (WidgetTester tester) async {
    // Créer les instances des mocks générés
    final mockAuthService = MockAuthService();
    final mockAssistantService = MockAssistantService();
    final mockNotificationService = MockNotificationService();
    final mockServiceManager = MockServiceManager();
    // --- Correction: Créer les autres mocks ---
    final mockApiService = MockSolarEdgeApiService();
    final mockWeatherManager = MockWeatherManager();
    final mockLocationService = MockLocationService();
    final mockPrefs = MockSharedPreferences();
    // --- Fin Correction ---

    // Configurer le comportement par défaut des mocks si nécessaire
    // Exemple :
    // when(mockAssistantService.insights).thenReturn([]);
    // when(mockAuthService.authStateChanges).thenAnswer((_) => Stream.value(null));
    // when(mockServiceManager.apiService).thenReturn(mockApiService); // Retourne le mock API
    // when(mockServiceManager.weatherManager).thenReturn(mockWeatherManager);
    // when(mockServiceManager.locationService).thenReturn(mockLocationService);
    // when(mockServiceManager.authService).thenReturn(mockAuthService);
    // when(mockServiceManager.notificationService).thenReturn(mockNotificationService);
    // when(mockServiceManager.assistantService).thenReturn(mockAssistantService); // Assurer le retour du mock Assistant
    // Configurer le comportement par défaut des mocks
    when(mockAssistantService.insights).thenReturn([]); // Exemple
    when(mockAuthService.authStateChanges).thenAnswer((_) => Stream.value(null));
    when(mockServiceManager.apiService).thenReturn(mockApiService); // Retourne le mock API
    when(mockServiceManager.weatherManager).thenReturn(mockWeatherManager);
    when(mockServiceManager.locationService).thenReturn(mockLocationService);
    when(mockServiceManager.authService).thenReturn(mockAuthService);
    when(mockServiceManager.notificationService).thenReturn(mockNotificationService);
    when(mockServiceManager.assistantService).thenReturn(mockAssistantService); // Assurer le retour du mock Assistant
    when(mockServiceManager.prefs).thenReturn(mockPrefs); // Retourne le mock Prefs

    // Configurer le comportement spécifique pour l'initialisation
    // Simuler que les services sont bien initialisés par le ServiceManager
    when(mockServiceManager.initializeCoreServices())
        .thenAnswer((_) async => {});
    // Simuler que l'API n'est pas configurée au départ (ou configurée si besoin)
    // Utiliser la méthode correcte initializeApiServiceFromPreferences
    when(mockServiceManager.initializeApiServiceFromPreferences())
        .thenAnswer((_) async => null); // ou mockApiService
    // Configurer le mock pour apiConfigChangedStream pour retourner un Stream<SolarEdgeApiService?>
    when(mockServiceManager.apiConfigChangedStream)
        .thenAnswer((_) => Stream.value(null)); // Simule API non configurée au début
    when(mockServiceManager.isApiConfigured).thenReturn(false); // ou true
    // S'assurer que les getters retournent les mocks appropriés
    when(mockServiceManager.authService).thenReturn(mockAuthService);
    when(mockServiceManager.apiService).thenReturn(null); // Simule API non configurée au début
    when(mockServiceManager.locationService).thenReturn(mockLocationService);
    when(mockServiceManager.weatherManager).thenReturn(mockWeatherManager);
    when(mockServiceManager.notificationService)
        .thenReturn(mockNotificationService);
    when(mockServiceManager.assistantService).thenReturn(mockAssistantService);
    when(mockServiceManager.prefs).thenReturn(mockPrefs);

    // Construire l'application en fournissant les mocks nécessaires via Provider
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          // Fournir le mock du ServiceManager lui-même
          Provider<ServiceManager>.value(value: mockServiceManager),
          // Fournir les mocks des services individuels, récupérés via le mock ServiceManager
          Provider<SharedPreferences>.value(
              value: mockServiceManager.prefs!), // Utiliser le getter du mock
          Provider<AuthService>.value(value: mockServiceManager.authService!),
          ChangeNotifierProvider<ValueNotifier<SolarEdgeApiService?>>.value(
            value: ValueNotifier(
                mockServiceManager.apiService), // Utiliser le getter du mock
          ),
          Provider<SolarEdgeApiService?>.value(
              value: mockServiceManager.apiService), // Idem
          Provider<LocationService>.value(
              value: mockServiceManager.locationService!),
          ChangeNotifierProvider<WeatherManager>.value(
              value: mockServiceManager.weatherManager!),
          Provider<NotificationService>.value(
              value: mockServiceManager.notificationService!),
          ChangeNotifierProvider<AssistantService>.value(
              value: mockServiceManager.assistantService!),
          // BackgroundWorkerService n'est pas dans ServiceManager, le créer/mocker séparément si besoin
        ],
        child:
            const MyApp(), // --- Correction: MyApp ne prend plus d'arguments directs ---
      ),
    );

    // Attendre que toutes les futures (initialisation dans main, SplashScreen) se terminent
    // Un délai peut être nécessaire si l'initialisation est complexe
    await tester.pumpAndSettle(
        const Duration(seconds: 2)); // Ajuster la durée si besoin

    // Vérifier qu'un élément clé de l'application est présent (SplashScreen)
    expect(find.byType(SplashScreen), findsOneWidget);

    // Vous pouvez ajouter d'autres vérifications ici si nécessaire
  });
}
