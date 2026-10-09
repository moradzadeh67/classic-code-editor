import 'package:flutter/material.dart';

import '../../services/debug_service.dart';
import '../../services/theme_service.dart';
import 'retro_border.dart';

class RetroWatchWindow extends StatefulWidget {
  const RetroWatchWindow({super.key});

  @override
  State<RetroWatchWindow> createState() => _RetroWatchWindowState();
}

class _RetroWatchWindowState extends State<RetroWatchWindow> {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DebugService.instance,
      builder: (context, _) {
        final colors = ThemeService.instance.colors;
        final variables = DebugService.instance.variables;

        return Container(
          decoration: RetroBorder.sunken(backgroundColor: colors.panel),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                height: 22,
                color: colors.selection,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: const Text(
                  'Watch Window',
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'Tahoma',
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              // Table Header
              Container(
                color: colors.panel,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: const [
                    Expanded(
                      flex: 2,
                      child: Text(
                        'Variable',
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'Tahoma',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'Value',
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'Tahoma',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Text(
                        'Type',
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'Tahoma',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, thickness: 1),
              // Body
              Expanded(
                child: variables.isEmpty
                    ? const Center(
                        child: Text(
                          '(No watches defined)',
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'Tahoma',
                            color: Colors.grey,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: variables.length,
                        itemBuilder: (context, index) {
                          final v = variables[index];
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: colors.shadow.withValues(alpha: 0.3),
                                  width: 0.5,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    v.name,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontFamily: 'Courier New',
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    v.value,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontFamily: 'Courier New',
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 1,
                                  child: Text(
                                    v.type,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontFamily: 'Courier New',
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
