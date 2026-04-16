import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import '../../core/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  List<BluetoothInfo> _devices = [];
  bool _isScanning = false;
  bool _connected = false;
  String _targetMac = "";

  @override
  void initState() {
    super.initState();
    _loadSavedPrinter();
  }

  Future<void> _loadSavedPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _targetMac = prefs.getString('saved_printer_mac') ?? "";
    });
    if (_targetMac.isNotEmpty) {
      _checkConnection();
    }
  }

  Future<void> _checkConnection() async {
    try {
      final isConn = await PrintBluetoothThermal.connectionStatus;
      setState(() => _connected = isConn);
    } catch (e) {
      setState(() => _connected = false);
    }
  }

  Future<void> _scanDevices() async {
    setState(() {
      _isScanning = true;
      _devices = [];
    });
    
    try {
      final devices = await PrintBluetoothThermal.pairedBluetooths;
      setState(() {
        _devices = devices;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error buscando dispositivos: $e')));
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  Future<void> _connect(String mac) async {
    setState(() => _isScanning = true);
    try {
      bool isConnected = await PrintBluetoothThermal.connect(macPrinterAddress: mac);
      if (isConnected) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('saved_printer_mac', mac);
        setState(() {
          _connected = true;
          _targetMac = mac;
        });
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impresora Conectada')));
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo conectar')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  Future<void> _disconnect() async {
    await PrintBluetoothThermal.disconnect;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('saved_printer_mac');
    setState(() {
      _connected = false;
      _targetMac = "";
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Impresora Tickets'),
      ),
      body: kIsWeb 
        ? _buildWebMessage()
        : Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                color: _connected ? AppColors.success.withValues(alpha: 0.1) : AppColors.error.withValues(alpha: 0.1),
                child: Row(
                  children: [
                    Icon(_connected ? Icons.print_rounded : Icons.print_disabled_rounded, 
                      color: _connected ? AppColors.success : AppColors.error, size: 32),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Estado: ${_connected ? "Conectada" : "Desconectada"}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          if (_targetMac.isNotEmpty) Text('MAC: $_targetMac', style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                    if (_connected)
                      TextButton(
                        onPressed: _disconnect,
                        child: const Text('Desconectar', style: TextStyle(color: AppColors.error)),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: FilledButton.icon(
                  onPressed: _isScanning ? null : _scanDevices,
                  icon: _isScanning ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.bluetooth_searching_rounded),
                  label: const Text('Buscar Dispositivos Vinculados'),
                  style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: _devices.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final device = _devices[index];
                    return ListTile(
                      leading: const Icon(Icons.bluetooth_rounded),
                      title: Text(device.name),
                      subtitle: Text(device.macAdress),
                      trailing: _targetMac == device.macAdress && _connected
                          ? const Icon(Icons.check_circle_rounded, color: AppColors.success)
                          : TextButton(
                              onPressed: () => _connect(device.macAdress),
                              child: const Text('Conectar'),
                            ),
                    );
                  },
                ),
              ),
            ],
          ),
    );
  }

  Widget _buildWebMessage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 80, color: Colors.grey),
            const SizedBox(height: 24),
            const Text(
              'Hardware Bluetooth no disponible en Web',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'La impresión directa por Bluetooth está reservada para nuestras aplicaciones nativas de Android e iOS.\n\nEn la versión Web, puedes imprimir usando el diálogo del sistema del navegador seleccionando tu impresora térmica instalada.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Regresar'),
            ),
          ],
        ),
      ),
    );
  }
}

