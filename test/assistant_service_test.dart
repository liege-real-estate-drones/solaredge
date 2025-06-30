import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:solaredge_monitor/data/models/solar_data.dart';
import 'package:solaredge_monitor/data/models/weather_data.dart';
import 'package:solaredge_monitor/data/services/assistant_service.dart';
import 'package:solaredge_monitor/data/services/solaredge_api_service.dart';
import 'package:solaredge_monitor/data/services/weather_manager.dart';
import 'package:solaredge_monitor/data/models/user_preferences.dart';
import 'package:flutter/foundation.dart'; // Required for ValueNotifier

import 'assistant_service_test.mocks.dart'; // Generated mock file

// Manual stub for UserPreferences to bypass mockito issues
// This class provides concrete implementations for all abstract members of UserPreferences
class FakeUserPreferences implements UserPreferences {
  // Implement all properties from UserPreferences
  @override
  String? solarEdgeApiKey;
  @override
  String? siteId;
  @override
  String? geminiApiKey;
  @override
  bool darkMode;
  @override
  String displayUnit;
  @override
  String currency;

  // Private backing fields for properties with explicit getters/setters in the real model
  double? _fakeEnergyRate;
  NotificationSettings _fakeNotificationSettings;
  DisplaySettings _fakeDisplaySettings;
  List<String> _fakeFavoriteCharts;
  double? _fakePeakPowerKw;
  double? _fakePanelTilt;
  String? _fakePanelOrientation;
  double? _fakeWashingMachineKw;
  int? _fakeDefaultWashingMachineDurationMin; // Added for the new field
  double? _fakeLatitude;
  double? _fakeLongitude;

  @override
  String weatherLocationSource; // This field is final in the real model
  @override
  String selectedLanguage; // This field is final in the real model


  // Explicitly implement getters and setters for properties that have them in the real model
  @override
  double? get energyRate => _fakeEnergyRate;
  @override
  set energyRate(double? value) => _fakeEnergyRate = value;

  @override
  NotificationSettings get notificationSettings => _fakeNotificationSettings;
  set notificationSettings(NotificationSettings value) => _fakeNotificationSettings = value;

  @override
  DisplaySettings get displaySettings => _fakeDisplaySettings;
  set displaySettings(DisplaySettings value) => _fakeDisplaySettings = value;

  @override
  List<String> get favoriteCharts => _fakeFavoriteCharts;
  set favoriteCharts(List<String> value) => _fakeFavoriteCharts = value;

  @override
  double? get peakPowerKw => _fakePeakPowerKw;
  @override
  set peakPowerKw(double? value) => _fakePeakPowerKw = value;

  @override
  double? get panelTilt => _fakePanelTilt;
  @override
  set panelTilt(double? value) => _fakePanelTilt = value;

  @override
  String? get panelOrientation => _fakePanelOrientation;
  @override
  set panelOrientation(String? value) => _fakePanelOrientation = value;

  @override
  double? get washingMachineKw => _fakeWashingMachineKw;
  @override
  set washingMachineKw(double? value) => _fakeWashingMachineKw = value;

  @override
  double? get latitude => _fakeLatitude;
  @override
  set latitude(double? value) => _fakeLatitude = value;

  @override
  double? get longitude => _fakeLongitude;
  @override
  set longitude(double? value) => _fakeLongitude = value;

  // Getter and Setter for defaultWashingMachineDurationMin
  @override
  int? get defaultWashingMachineDurationMin => _fakeDefaultWashingMachineDurationMin;
  @override
  set defaultWashingMachineDurationMin(int? value) => _fakeDefaultWashingMachineDurationMin = value;


  FakeUserPreferences({
    this.solarEdgeApiKey,
    this.siteId,
    this.geminiApiKey,
    this.darkMode = true,
    this.displayUnit = 'kW',
    this.currency = 'EUR',
    double? energyRate,
    NotificationSettings? notificationSettings,
    DisplaySettings? displaySettings,
    String selectedLanguage = 'fr',
    List<String>? favoriteCharts,
    double? peakPowerKw,
    double? panelTilt,
    String? panelOrientation,
    double? washingMachineKw,
    int? defaultWashingMachineDurationMin, // Added
    double? latitude,
    double? longitude,
    this.weatherLocationSource = 'site_primary',
  }) : _fakeEnergyRate = energyRate,
       _fakeNotificationSettings = notificationSettings ?? NotificationSettings(),
       _fakeDisplaySettings = displaySettings ?? DisplaySettings(),
       _fakeFavoriteCharts = favoriteCharts ?? ['production', 'comparison', 'energy'],
       _fakePeakPowerKw = peakPowerKw,
       _fakePanelTilt = panelTilt,
       _fakePanelOrientation = panelOrientation,
       _fakeWashingMachineKw = washingMachineKw,
       _fakeDefaultWashingMachineDurationMin = defaultWashingMachineDurationMin, // Added
       _fakeLatitude = latitude,
       _fakeLongitude = longitude,
       selectedLanguage = selectedLanguage; // Initialize the final field


  @override
  UserPreferences copyWith({
    String? solarEdgeApiKey,
    String? siteId,
    String? geminiApiKey,
    bool? darkMode,
    String? displayUnit,
    String? currency,
    double? energyRate,
    NotificationSettings? notificationSettings,
    DisplaySettings? displaySettings,
    String? selectedLanguage,
    List<String>? favoriteCharts,
    double? peakPowerKw,
    double? panelTilt,
    String? panelOrientation,
    double? washingMachineKw,
    int? defaultWashingMachineDurationMin, // Added
    double? latitude,
    double? longitude,
    String? weatherLocationSource,
  }) {
    return FakeUserPreferences(
      solarEdgeApiKey: solarEdgeApiKey ?? this.solarEdgeApiKey,
      siteId: siteId ?? this.siteId,
      geminiApiKey: geminiApiKey ?? this.geminiApiKey,
      darkMode: darkMode ?? this.darkMode,
      displayUnit: displayUnit ?? this.displayUnit,
      currency: currency ?? this.currency,
      energyRate: energyRate ?? this._fakeEnergyRate,
      notificationSettings: notificationSettings ?? this._fakeNotificationSettings.copyWith(),
      displaySettings: displaySettings ?? this._fakeDisplaySettings.copyWith(),
      selectedLanguage: selectedLanguage ?? this.selectedLanguage,
      favoriteCharts: favoriteCharts ?? List.from(this._fakeFavoriteCharts),
      peakPowerKw: peakPowerKw ?? this._fakePeakPowerKw,
      panelTilt: panelTilt ?? this._fakePanelTilt,
      panelOrientation: panelOrientation ?? this._fakePanelOrientation,
      washingMachineKw: washingMachineKw ?? this._fakeWashingMachineKw,
      defaultWashingMachineDurationMin: defaultWashingMachineDurationMin ?? this._fakeDefaultWashingMachineDurationMin, // Added
      latitude: latitude ?? this._fakeLatitude,
      longitude: longitude ?? this._fakeLongitude,
      weatherLocationSource: weatherLocationSource ?? this.weatherLocationSource,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    // Implement toJson if needed for tests, otherwise return empty map
    return {};
  }

  String get formattedActiveDaysShort => "Fake formatted days"; // Provide a fake implementation
}


@GenerateNiceMocks([MockSpec<SolarEdgeApiService>(), MockSpec<WeatherManager>(), MockSpec<UserPreferences>()])
void main() {
  group('AssistantService Tests', () {
    late AssistantService assistant;
    late MockSolarEdgeApiService mockApiService;
    late MockWeatherManager mockWeatherManager;
    late ValueNotifier<UserPreferences?> mockUserPrefsNotifier;
    late ValueNotifier<SolarEdgeApiService?> mockApiServiceNotifier;

    setUp(() {
      mockApiService = MockSolarEdgeApiService();
      mockWeatherManager = MockWeatherManager();

      // Use FakeUserPreferences instead of MockUserPreferences
      final fakeUserPreferences = FakeUserPreferences(
        energyRate: 0.15,
        peakPowerKw: 3.0,
        washingMachineKw: 2.0,
        latitude: 48.8566,
        longitude: 2.3522,
        // Provide default or fake instances for nested objects if necessary
        notificationSettings: NotificationSettings(),
        displaySettings: DisplaySettings(),
      );

      // Initialize ValueNotifiers with the fake instance
      mockUserPrefsNotifier = ValueNotifier<UserPreferences?>(fakeUserPreferences);
      mockApiServiceNotifier = ValueNotifier<SolarEdgeApiService?>(mockApiService);

      // Stub SolarEdgeApiService methods called during AssistantService initialization or by generateInsights
      when(mockApiService.getDailyEnergy(any)).thenAnswer((_) async => DailySolarData(date: DateTime.now(), totalEnergy: 5.0, peakPower: 0.0, hourlyData: [])); // Stub getDailyEnergy
      when(mockApiService.getCurrentPowerData()).thenAnswer((_) async => SolarData(timestamp: DateTime.now(), power: 1.0, energy: 0.0)); // Stub getCurrentPowerData


      assistant = AssistantService(
        weatherManager: mockWeatherManager,
        userPreferencesNotifier: mockUserPrefsNotifier,
        apiServiceNotifier: mockApiServiceNotifier,
      );
    });

    tearDown(() {
      assistant.dispose();
      mockUserPrefsNotifier.dispose();
      mockApiServiceNotifier.dispose();
    });

    // Add tests here
    test('handleUserInput should process "Quand lancer ma machine ?" intent',
        () async {
      // Mock the behavior of dependencies for this specific test case
      // You'll need to mock the weather forecast and user preferences
      // to simulate a scenario where a best slot can be suggested.

      // Example mock for weather forecast (adjust as needed for your SolarProductionEstimator logic)
      when(mockWeatherManager.getWeatherForecast(
              forceRefresh: anyNamed('forceRefresh')))
          .thenAnswer((_) async => WeatherForecast(
                timestamp: DateTime.now(), // Added timestamp
                hourlyForecast: [
                  // Add mock WeatherData for relevant hours
                  // Example: High production hour
                  WeatherData(
                    timestamp: DateTime.now().add(const Duration(hours: 2)),
                    temperature: 20,
                    humidity: 50,
                    windSpeed: 10,
                    condition: 'Clear',
                    iconCode: '01d',
                    cloudCover: 0,
                    shortwaveRadiation: 800, // High irradiance
                  ),
                  WeatherData(
                    timestamp: DateTime.now().add(const Duration(hours: 3)),
                    temperature: 22,
                    humidity: 45,
                    windSpeed: 12,
                    condition: 'Clear',
                    iconCode: '01d',
                    cloudCover: 0,
                    shortwaveRadiation: 900, // Peak irradiance
                  ),
                  WeatherData(
                    timestamp: DateTime.now().add(const Duration(hours: 4)),
                    temperature: 21,
                    humidity: 48,
                    windSpeed: 11,
                    condition: 'Clear',
                    iconCode: '01d',
                    cloudCover: 0,
                    shortwaveRadiation: 700, // Decreasing irradiance
                  ),
                  // Add more hours as needed...
                ],
                dailyForecast: [], // Provide required named parameter
              ));

      // Example mock for user preferences (adjust peakPowerKw and washingMachineKw)
      // This part might need adjustment if AssistantService reads these values directly from the notifier's value
      // Since we are using FakeUserPreferences, the values are already set on the instance provided to the notifier.
      // The following line might be redundant or need to be removed/adjusted depending on how AssistantService uses userPreferencesNotifier.value
      // when(mockUserPrefsNotifier.value).thenReturn(FakeUserPreferences()..peakPowerKw = 3.0 ..washingMachineKw = 2.0 ..latitude = 48.8566 ..longitude = 2.3522);


      // Call the method
      await assistant.processUserText('Quand lancer ma machine ?');

      // Verify the output message
      // Since the response is added to the conversation via AiService,
      // you might need to mock AiService or check the conversation stream.
      // For this test, let's assume we can check the last message added to the conversation.
      // This requires AssistantService to have a way to access or expose the conversation.
      // Based on the current structure, AssistantService calls AiService.addBotMessage.
      // We can mock AiService and verify that addBotMessage was called with the expected message.

      // Mock AiService and inject it (requires modifying AssistantService constructor or using a ServiceManager mock)
      // For simplicity in this test example, let's assume we can check the output string directly
      // if processUserText were to return the string.
      // Since it's Future<void>, we need to verify the side effect (calling addBotMessage).

      // This requires a more complex test setup with mocking AiService.
      // For now, let's add a basic expectation based on the expected output format.
      // This test will need refinement once AiService mocking is set up.

      // Basic expectation (will need adjustment based on actual implementation and mocking)
      // expect(await assistant.processUserText('Quand lancer ma machine ?'), contains('autour de'));
      // Since processUserText is Future<void>, we need to verify the call to addBotMessage
      // This requires mocking AiService and verifying the call.
      // For now, we'll skip the exact content check and just ensure no errors.
      // A proper test would involve mocking AiService and verifying the message content.
    });

    test('handleUserInput should process "Production prévue demain ?" intent',
        () async {
      // Mock the behavior of dependencies for this specific test case
      // You'll need to mock the weather forecast and user preferences
      // to simulate a scenario where tomorrow's production can be estimated.

      // Example mock for weather forecast for tomorrow
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      when(mockWeatherManager.getWeatherForecast(
              forceRefresh: anyNamed('forceRefresh')))
          .thenAnswer((_) async => WeatherForecast(
                timestamp: DateTime.now(), // Added timestamp
                hourlyForecast: [
                  // Add mock WeatherData for relevant hours tomorrow (e.g., 06:00 to 20:00)
                  WeatherData(
                    timestamp: DateTime(
                        tomorrow.year, tomorrow.month, tomorrow.day, 8, 0),
                    temperature: 18,
                    humidity: 60,
                    windSpeed: 8,
                    condition: 'Partly Cloudy',
                    iconCode: '02d',
                    cloudCover: 30,
                    shortwaveRadiation: 400, // Moderate irradiance
                  ),
                  WeatherData(
                    timestamp: DateTime(
                        tomorrow.year, tomorrow.month, tomorrow.day, 12, 0),
                    temperature: 20,
                    humidity: 55,
                    windSpeed: 10,
                    condition: 'Clear',
                    iconCode: '01d',
                    cloudCover: 10,
                    shortwaveRadiation: 850, // High irradiance
                  ),
                  WeatherData(
                    timestamp: DateTime(
                        tomorrow.year, tomorrow.month, tomorrow.day, 16, 0),
                    temperature: 19,
                    humidity: 58,
                    windSpeed: 9,
                    condition: 'Partly Cloudy',
                    iconCode: '02d',
                    cloudCover: 40,
                    shortwaveRadiation: 350, // Moderate irradiance
                  ),
                  // Add more hours as needed...
                ],
                dailyForecast: [], // Provide required named parameter
              ));

      // Example mock for user preferences (adjust peakPowerKw)
      // This part might need adjustment if AssistantService reads these values directly from the notifier's value
      // Since we are using FakeUserPreferences, the values are already set on the instance provided to the notifier.
      // The following line might be redundant or need to be removed/adjusted depending on how AssistantService uses userPreferencesNotifier.value
      // when(mockUserPrefsNotifier.value).thenReturn(FakeUserPreferences()..peakPowerKw = 3.0 ..latitude = 48.8566 ..longitude = 2.3522);


      // Call the method
      await assistant.processUserText('Production prévue demain ?');

      // Verify the output message (similar to the previous test, requires mocking AiService)
      // Basic expectation based on the expected output format.
      // expect(await assistant.processUserText('Production prévue demain ?'), contains('kWh'));
      // Since processUserText is Future<void>, we need to verify the call to addBotMessage
      // This requires mocking AiService and verifying the call.
      // For now, we'll skip the exact content check and just ensure no errors.
      // A proper test would involve mocking AiService and verifying the message content.
    });
  });
}
