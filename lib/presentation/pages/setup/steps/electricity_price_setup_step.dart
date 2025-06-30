import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ElectricityPriceSetupStep extends StatefulWidget {
  final VoidCallback onNext;
  final VoidCallback onPrevious;

  const ElectricityPriceSetupStep(
      {super.key, required this.onNext, required this.onPrevious});

  @override
  State<ElectricityPriceSetupStep> createState() =>
      _ElectricityPriceSetupStepState();
}

class _ElectricityPriceSetupStepState extends State<ElectricityPriceSetupStep> {
  final _formKey = GlobalKey<FormState>();
  final _priceController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSavedPrice();
  }

  Future<void> _loadSavedPrice() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPrice = prefs.getDouble('energy_rate');
    if (savedPrice != null) {
      _priceController.text = savedPrice.toString();
    }
  }

  Future<void> _saveElectricityPrice() async {
    if (_formKey.currentState!.validate()) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('energy_rate', double.parse(_priceController.text));
      widget.onNext();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onPrevious,
        ),
        title: const Text('Prix de l\'électricité'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Veuillez entrer le prix moyen de votre électricité (par kWh).',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _priceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Prix par kWh (€)',
                  hintText: 'Ex: 0.25',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Veuillez entrer un prix';
                  }
                  if (double.tryParse(value) == null) {
                    return 'Veuillez entrer un nombre valide';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: _saveElectricityPrice,
                child: const Text('Suivant'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
