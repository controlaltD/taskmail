import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/serveos_venue.dart';
import 'board_repository.dart';

/// A ServeOS-be küldéshez választja ki a venue-t, a bejelentkezett user
/// `venue_users` (ServeOS admin séma) kapcsolatai alapján.
Future<ServeosVenue?> showVenuePickerDialog(BuildContext context, WidgetRef ref) {
  return showDialog<ServeosVenue>(
    context: context,
    builder: (context) => const _VenuePickerDialog(),
  );
}

class _VenuePickerDialog extends ConsumerWidget {
  const _VenuePickerDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final venuesAsync = ref.watch(serveosVenuesProvider);

    return AlertDialog(
      title: const Text('Küldés ServeOS-be'),
      content: SizedBox(
        width: 320,
        child: venuesAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text('Hiba: $e'),
          data: (venues) {
            if (venues.isEmpty) {
              return const Text(
                'Nincs ServeOS venue-hoz kötve a fiókod. Kérd meg az admint, '
                'hogy kössön össze egy venue-val a ServeOS admin panelen.',
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: venues
                  .map(
                    (v) => ListTile(
                      title: Text(v.name),
                      subtitle: Text(v.role),
                      onTap: () => Navigator.of(context).pop(v),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Mégse')),
      ],
    );
  }
}
